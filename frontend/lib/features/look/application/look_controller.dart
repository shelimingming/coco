import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/audio/mic_pcm_stream.dart';
import '../../../core/audio/pcm_wav.dart';
import '../../../core/audio/speech_end_detector.dart';
import '../../../core/network/api_exception.dart';
import '../data/look_api.dart';
import '../data/screenshot_picker.dart';
import '../domain/look_state.dart';

/// 看一看单页控制器：取图 → 识图 → 朗读 → 自动开麦追问。
class LookController extends StateNotifier<LookState> {
  LookController(this._ref) : super(const LookState()) {
    _speechDetector = SpeechEndDetector();
    _mic = createMicPcmStream();
  }

  final Ref _ref;
  final ImagePicker _picker = ImagePicker();
  final ScreenshotPicker _screenshotPicker = createScreenshotPicker();
  final AudioPlayer _player = AudioPlayer();
  late final MicPcmStream _mic;

  late SpeechEndDetector _speechDetector;
  StreamSubscription<Uint8List>? _micSub;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  Uint8List? _lastSpeech;
  int _opGen = 0;
  bool _finishingListen = false;

  LookApi get _lookApi => _ref.read(lookApiProvider);
  AudioApi get _audioApi => _ref.read(audioApiProvider);

  /// 按来源取图，成功后自动识图。
  Future<void> pick(LookSource source) async {
    if (state.isBusy || state.phase == LookPhase.analyzing) return;

    state = state.copyWith(clearError: true, clearNotice: true, source: source);

    try {
      final picked = await _pickBytes(source);
      if (picked == null) return;

      state = state.copyWith(
        imageBytes: picked.bytes,
        phase: LookPhase.analyzing,
        clearError: true,
      );
      await _analyze(
        source: source,
        bytes: picked.bytes,
        filename: picked.filename,
      );
    } catch (_) {
      _fail(title: '打不开相机或相册', message: '请允许可可使用相机和相册，然后再试一次。');
    }
  }

  Future<({Uint8List bytes, String filename})?> _pickBytes(
    LookSource source,
  ) async {
    switch (source) {
      case LookSource.camera:
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked == null) return null;
        return (
          bytes: await picked.readAsBytes(),
          filename: picked.name.isNotEmpty ? picked.name : 'camera.jpg',
        );
      case LookSource.album:
        final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked == null) return null;
        return (
          bytes: await picked.readAsBytes(),
          filename: picked.name.isNotEmpty ? picked.name : 'album.jpg',
        );
      case LookSource.screenshot:
        final result = await _screenshotPicker.pickLatestOrFallback();
        switch (result) {
          case ScreenshotPickSuccess(
            :final bytes,
            :final filename,
            :final notice,
          ):
            if (notice != null) {
              state = state.copyWith(notice: notice);
            }
            return (bytes: bytes, filename: filename);
          case ScreenshotPickFallback(:final reason):
            _fail(title: '读不到截屏', message: reason);
            return null;
          case ScreenshotPickCancelled():
            return null;
        }
    }
  }

  Future<void> _analyze({
    required LookSource source,
    required Uint8List bytes,
    required String filename,
  }) async {
    final gen = ++_opGen;
    try {
      final result = await _lookApi.look(
        imageBytes: bytes,
        filename: filename,
        question: source.defaultQuestion,
      );
      if (!_alive(gen)) return;

      final canFollowUp =
          result.conversationId != null && result.conversationId!.isNotEmpty;
      final spoken = result.spokenSummary;

      state = state.copyWith(
        phase: LookPhase.speaking,
        conversationId: result.conversationId,
        headline: result.headline,
        detail: result.detail,
        safetyNote: result.safetyNote,
        replyText: spoken,
        isClear: result.isClear,
        canFollowUp: canFollowUp,
        notice: canFollowUp ? state.notice : '这次不能继续问，可以换一张再看。照片没有保存在可可这边。',
        clearError: true,
      );

      await _speak(spoken, gen: gen, autoListenAfter: canFollowUp);
    } on ApiException catch (e) {
      if (!_alive(gen)) return;
      _fail(title: '刚才没看清', message: e.message);
    } catch (_) {
      if (!_alive(gen)) return;
      _fail(title: '刚才没看清', message: '网络或服务暂时不可用。您可以换一张，照片没有保存在可可这边。');
    }
  }

  /// 换一张：清空当前会话，回到选来源。
  Future<void> reset() async {
    _opGen++;
    await _teardownMic();
    await _player.stop();
    state = const LookState();
    _speechDetector.reset();
    _lastSpeech = null;
  }

  Future<void> interrupt() async {
    if (state.phase != LookPhase.speaking) return;
    _opGen++;
    await _player.stop();
    state = state.copyWith(phase: LookPhase.idle, clearError: true);
  }

  Future<void> replay() async {
    final bytes = _lastSpeech;
    final text = state.replyText.trim();
    if (bytes != null && bytes.isNotEmpty) {
      final gen = ++_opGen;
      state = state.copyWith(phase: LookPhase.speaking, clearError: true);
      try {
        await _playMp3(bytes);
      } catch (_) {
        if (text.isNotEmpty) await _speak(text, gen: gen);
      } finally {
        if (_alive(gen) && state.phase == LookPhase.speaking) {
          state = state.copyWith(phase: LookPhase.idle);
        }
      }
      return;
    }
    if (text.isNotEmpty) {
      await _speak(text, gen: ++_opGen);
    }
  }

  Future<void> onPrimaryPressed() async {
    switch (state.phase) {
      case LookPhase.idle:
        if (state.hasImage) await startListening();
        return;
      case LookPhase.listening:
        await finishListening(manual: true);
        return;
      case LookPhase.speaking:
        await interrupt();
        return;
      case LookPhase.error:
        await reset();
        return;
      case LookPhase.analyzing:
      case LookPhase.thinking:
        return;
    }
  }

  Future<void> startListening() async {
    if (!state.canFollowUp) {
      _fail(title: '没法继续问', message: '这次不能继续问，可以换一张再看。照片没有保存在可可这边。');
      return;
    }
    if (state.phase == LookPhase.listening ||
        state.phase == LookPhase.thinking) {
      return;
    }

    await _player.stop();
    await _teardownMic();
    _pcm.clear();
    _speechDetector.reset();

    state = state.copyWith(
      phase: LookPhase.listening,
      userCaption: '',
      clearError: true,
    );

    try {
      final ok = await _mic.hasPermission();
      if (!ok) {
        _fail(title: '打不开麦克风', message: '请允许可可使用麦克风，然后再试一次。');
        return;
      }

      await _mic.start();
      _micSub = _mic.pcmStream.listen((chunk) async {
        if (chunk.isEmpty) return;
        _pcm.add(chunk);
        if (_speechDetector.feed(chunk)) {
          await finishListening(manual: false);
        }
      });
    } on MicPcmException catch (e) {
      _fail(title: '打不开麦克风', message: e.message);
    } catch (_) {
      _fail(title: '打不开麦克风', message: '请稍后再试，或换一张重新看。刚才没有录下声音。');
    }
  }

  Future<void> finishListening({required bool manual}) async {
    if (state.phase != LookPhase.listening || _finishingListen) return;
    _finishingListen = true;

    state = state.copyWith(phase: LookPhase.thinking, clearError: true);

    Uint8List pcm = Uint8List(0);
    try {
      await _mic.stop();
      await _micSub?.cancel();
      _micSub = null;
      pcm = _pcm.takeBytes();
    } catch (_) {
      pcm = _pcm.takeBytes();
    }

    if (!_speechDetector.hadSpeech && !manual) {
      state = state.copyWith(phase: LookPhase.idle, clearError: true);
      _finishingListen = false;
      return;
    }

    if (pcm.isEmpty) {
      _fail(title: '没有听到声音', message: '请靠近一点，再说一次。');
      _finishingListen = false;
      return;
    }

    final gen = ++_opGen;
    final wav = pcm16ToWav(pcm, sampleRate: 16000);

    try {
      final text = await _audioApi.transcribe(wav);
      if (!_alive(gen)) return;

      state = state.copyWith(userCaption: text);

      final conversationId = state.conversationId;
      if (conversationId == null || conversationId.isEmpty) {
        _fail(title: '没法继续问', message: '这次不能继续问，可以换一张再看。照片没有保存在可可这边。');
        return;
      }

      final reply = await _lookApi.followUp(
        conversationId: conversationId,
        text: text,
      );
      if (!_alive(gen)) return;

      state = state.copyWith(replyText: reply, phase: LookPhase.speaking);
      await _speak(reply, gen: gen, autoListenAfter: true);
    } on ApiException catch (e) {
      if (!_alive(gen)) return;
      if (e.statusCode == 410 || e.code == 'vision.image_expired') {
        _fail(
          title: '图已经过期了',
          message: '刚才那张图我这边已经不留了，重新拍一张就行，照片没有保存。',
          resetImage: true,
        );
        return;
      }
      _fail(title: '刚才没办成', message: e.message);
    } catch (_) {
      if (!_alive(gen)) return;
      _fail(title: '刚才没办成', message: '网络或服务暂时不可用。您可以再说一次，刚才没有保存错误数据。');
    } finally {
      _finishingListen = false;
    }
  }

  Future<void> _speak(
    String text, {
    required int gen,
    bool autoListenAfter = false,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      if (_alive(gen)) {
        state = state.copyWith(phase: LookPhase.idle);
        if (autoListenAfter && state.canFollowUp) {
          await startListening();
        }
      }
      return;
    }

    if (_alive(gen)) {
      state = state.copyWith(phase: LookPhase.speaking, replyText: cleaned);
    }

    try {
      final bytes = await _audioApi.speech(cleaned);
      _lastSpeech = bytes;
      if (!_alive(gen)) return;
      await _playMp3(bytes);
    } catch (_) {
      // TTS 失败仍保留大字文案
    } finally {
      if (_alive(gen) && state.phase == LookPhase.speaking) {
        state = state.copyWith(phase: LookPhase.idle);
        if (autoListenAfter && state.canFollowUp) {
          await startListening();
        }
      }
    }
  }

  /// 用 data URI 播放，避免 Web 无临时文件。
  Future<void> _playMp3(Uint8List bytes) async {
    await _player.stop();
    await _player.setAudioSource(
      AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/mpeg')),
    );
    await _player.play();
    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.idle,
    );
  }

  void _fail({
    required String title,
    required String message,
    bool resetImage = false,
  }) {
    if (resetImage) {
      state = LookState(
        phase: LookPhase.error,
        errorTitle: title,
        errorMessage: message,
      );
      return;
    }
    state = state.copyWith(
      phase: LookPhase.error,
      errorTitle: title,
      errorMessage: message,
    );
  }

  bool _alive(int gen) => mounted && gen == _opGen;

  Future<void> _teardownMic() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _mic.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _opGen++;
    unawaited(_teardownMic());
    unawaited(_player.dispose());
    unawaited(_mic.dispose());
    super.dispose();
  }
}

final lookControllerProvider =
    StateNotifierProvider.autoDispose<LookController, LookState>((ref) {
      return LookController(ref);
    });
