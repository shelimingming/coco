import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../../../core/audio/pcm_wav.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../parent/domain/coco_companion_pose.dart';
import '../../parent/presentation/widgets/coco_companion_view.dart';
import '../application/look_providers.dart';
import '../data/look_api.dart';
import '../domain/models.dart';

/// 同图追问：ASR → qwen3.7-plus → TTS，不跳回实时语音模型。
class LookAskPage extends ConsumerStatefulWidget {
  const LookAskPage({super.key, required this.args});

  final LookAskArgs args;

  @override
  ConsumerState<LookAskPage> createState() => _LookAskPageState();
}

class _LookAskPageState extends ConsumerState<LookAskPage> {
  LookAskUiState _state = const LookAskUiState();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _micSub;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  Uint8List? _lastSpeech;

  @override
  void initState() {
    super.initState();
    _state = LookAskUiState(replyText: widget.args.spokenSummary);
    // 进入追问页先把识图结论读一遍
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_speak(widget.args.spokenSummary));
    });
  }

  @override
  void dispose() {
    unawaited(_teardownMic());
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  CocoCompanionPose get _pose => switch (_state.phase) {
    LookAskPhase.idle => CocoCompanionPose.looking,
    LookAskPhase.listening => CocoCompanionPose.listening,
    LookAskPhase.thinking => CocoCompanionPose.thinking,
    LookAskPhase.speaking => CocoCompanionPose.speaking,
    LookAskPhase.error => CocoCompanionPose.uncertain,
  };

  String get _primaryLabel => switch (_state.phase) {
    LookAskPhase.listening => '我说完了',
    LookAskPhase.thinking => '可可正在想…',
    LookAskPhase.speaking => '打断',
    _ => '点一下开始说',
  };

  Future<void> _onPrimary() async {
    switch (_state.phase) {
      case LookAskPhase.idle:
      case LookAskPhase.error:
        await _startListening();
        return;
      case LookAskPhase.listening:
        await _finishListening();
        return;
      case LookAskPhase.speaking:
        await _player.stop();
        if (mounted) {
          setState(() {
            _state = _state.copyWith(
              phase: LookAskPhase.idle,
              clearError: true,
            );
          });
        }
        return;
      case LookAskPhase.thinking:
        return;
    }
  }

  Future<void> _startListening() async {
    await _player.stop();
    await _teardownMic();
    _pcm.clear();
    setState(() {
      _state = _state.copyWith(
        phase: LookAskPhase.listening,
        userCaption: '',
        clearError: true,
      );
    });
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        _fail(title: '打不开麦克风', message: '请到系统设置里允许可可使用麦克风，然后再试一次。');
        return;
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _micSub = stream.listen((chunk) {
        if (chunk.isNotEmpty) _pcm.add(chunk);
      });
    } catch (_) {
      _fail(title: '打不开麦克风', message: '请稍后再试，或改用重新拍一张。刚才没有录下声音。');
    }
  }

  Future<void> _finishListening() async {
    setState(() {
      _state = _state.copyWith(phase: LookAskPhase.thinking, clearError: true);
    });
    Uint8List pcm = Uint8List(0);
    try {
      await _recorder.stop();
      await _micSub?.cancel();
      _micSub = null;
      pcm = _pcm.takeBytes();
    } catch (_) {
      // 继续用已缓冲的 PCM
      pcm = _pcm.takeBytes();
    }
    if (pcm.isEmpty) {
      _fail(title: '没有听到声音', message: '请靠近一点，再说一次。');
      return;
    }
    final wav = pcm16ToWav(pcm, sampleRate: 16000);
    try {
      final text = await ref.read(audioApiProvider).transcribe(wav);
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(userCaption: text);
      });
      final reply = await ref
          .read(lookApiProvider)
          .followUp(conversationId: widget.args.conversationId, text: text);
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(replyText: reply, phase: LookAskPhase.idle);
      });
      await _speak(reply);
    } on ApiException catch (e) {
      _fail(title: '刚才没办成', message: e.message);
    } catch (_) {
      _fail(title: '刚才没办成', message: '网络或服务暂时不可用。您可以再说一次，刚才没有保存错误数据。');
    }
  }

  Future<void> _speak(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty || !mounted) return;
    setState(() {
      _state = _state.copyWith(
        phase: LookAskPhase.speaking,
        replyText: cleaned,
      );
    });
    try {
      final bytes = await ref.read(audioApiProvider).speech(cleaned);
      _lastSpeech = bytes;
      if (!mounted) return;
      await _playMp3(bytes);
    } catch (_) {
      // TTS 失败仍保留大字文案
    } finally {
      if (mounted && _state.phase == LookAskPhase.speaking) {
        setState(() {
          _state = _state.copyWith(phase: LookAskPhase.idle);
        });
      }
    }
  }

  Future<void> _replay() async {
    final bytes = _lastSpeech;
    final text = _state.replyText.trim();
    if (bytes != null && bytes.isNotEmpty) {
      setState(() {
        _state = _state.copyWith(phase: LookAskPhase.speaking);
      });
      try {
        await _playMp3(bytes);
      } catch (_) {
        if (text.isNotEmpty) await _speak(text);
      } finally {
        if (mounted) {
          setState(() {
            _state = _state.copyWith(phase: LookAskPhase.idle);
          });
        }
      }
      return;
    }
    if (text.isNotEmpty) await _speak(text);
  }

  /// iOS 上 data URI 不稳定，写入临时文件再播；播完即删。
  Future<void> _playMp3(Uint8List bytes) async {
    await _player.stop();
    final path =
        '${Directory.systemTemp.path}/coco-look-tts-${DateTime.now().microsecondsSinceEpoch}.mp3';
    final file = File(path);
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _player.setFilePath(path);
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (s) => s == ProcessingState.completed || s == ProcessingState.idle,
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  void _fail({required String title, required String message}) {
    if (!mounted) return;
    setState(() {
      _state = _state.copyWith(
        phase: LookAskPhase.error,
        errorTitle: title,
        errorMessage: message,
      );
    });
  }

  Future<void> _teardownMic() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy =
        _state.phase == LookAskPhase.thinking ||
        _state.phase == LookAskPhase.speaking;
    return CocoScaffold(
      title: '还想问',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '返回',
              onPressed: busy
                  ? null
                  : () {
                      unawaited(_player.stop());
                      context.pop();
                    },
            ),
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinBar(args: widget.args),
          const SizedBox(height: CocoSpace.s4),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  CocoCompanionView(pose: _pose, size: 132),
                  const SizedBox(height: CocoSpace.s4),
                  if (_state.userCaption.isNotEmpty) ...[
                    Text(
                      '您说：${_state.userCaption}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s3),
                  ],
                  Text(
                    _state.replyText.isNotEmpty
                        ? _state.replyText
                        : '想继续问什么，点一下开始说。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: CocoColors.neutral950,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                  if (_state.errorTitle != null) ...[
                    const SizedBox(height: CocoSpace.s4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(CocoSpace.s4),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          CocoColors.warning.withValues(alpha: 0.12),
                          CocoColors.parentSurface,
                        ),
                        borderRadius: BorderRadius.circular(CocoRadius.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _state.errorTitle!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: CocoColors.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: CocoSpace.s2),
                          Text(
                            _state.errorMessage ?? '',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: CocoColors.neutral700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          CocoPrimaryButton(
            label: _primaryLabel,
            loading: _state.phase == LookAskPhase.thinking,
            loadingLabel: '可可正在想…',
            onPressed: _state.phase == LookAskPhase.thinking
                ? null
                : _onPrimary,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '再听一遍',
            onPressed:
                (_state.phase == LookAskPhase.idle ||
                        _state.phase == LookAskPhase.error) &&
                    _state.replyText.trim().isNotEmpty
                ? () => unawaited(_replay())
                : null,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '问完了',
            onPressed: busy
                ? null
                : () {
                    unawaited(_player.stop());
                    context.go('/parent');
                  },
          ),
        ],
      ),
    );
  }
}

class _PinBar extends StatelessWidget {
  const _PinBar({required this.args});

  final LookAskArgs args;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CocoSpace.s3),
      decoration: BoxDecoration(
        color: CocoColors.neutral100,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(CocoRadius.md),
            child: Image.file(
              File(args.imagePath),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 64,
                height: 64,
                color: CocoColors.parentPrimarySoft,
                child: const Icon(Icons.image_outlined),
              ),
            ),
          ),
          const SizedBox(width: CocoSpace.s3),
          Expanded(
            child: Text(
              args.headline.trim().isNotEmpty ? args.headline : '刚才看过的图',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: CocoColors.neutral950,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
