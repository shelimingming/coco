import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'mic_pcm_stream.dart';

/// iOS/Android：record 插件输出 16k PCM。
MicPcmStream createMicPcmStream() => IoMicPcmStream();

class IoMicPcmStream implements MicPcmStream {
  IoMicPcmStream({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<Uint8List>.broadcast();
  bool _suppress = false;

  @override
  Stream<Uint8List> get pcmStream => _controller.stream;

  @override
  bool get isRecording => _subscription != null;

  @override
  set suppress(bool value) => _suppress = value;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    await stop();
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      throw const MicPcmException('麦克风还没有允许使用。您可以到手机设置里允许，然后再点我。刚才没有录下任何声音。');
    }
    try {
      // iOS：iosConfig 默认带 defaultToSpeaker，保证外放；须在播放器 setup 之后调用。
      // Android：speakerphone + voiceCommunication，避免走听筒并利于回声抑制。
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            speakerphone: true,
            audioManagerMode: AudioManagerMode.modeInCommunication,
          ),
        ),
      );
      _subscription = stream.listen(
        (chunk) {
          if (_suppress || _controller.isClosed || chunk.isEmpty) return;
          _controller.add(chunk);
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } on MicPcmException {
      rethrow;
    } catch (_) {
      throw const MicPcmException('麦克风暂时没有准备好。您可以再点一次形象。刚才没有录下任何声音。');
    }
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
    await _recorder.dispose();
  }
}
