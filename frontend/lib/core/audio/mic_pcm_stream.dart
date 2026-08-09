import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// 麦克风权限或采麦失败时抛出；文案可直接展示给老人。
class MicPcmException implements Exception {
  const MicPcmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 上行 16kHz / 16bit / mono PCM 流；与播放器解耦，便于单测替换。
class MicPcmStream {
  MicPcmStream({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<Uint8List>.broadcast();
  bool _suppress = false;

  Stream<Uint8List> get pcmStream => _controller.stream;

  bool get isRecording => _subscription != null;

  /// 外放播报时抑制上行，避免喇叭回灌触发误打断。
  set suppress(bool value) => _suppress = value;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    await stop();
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      throw const MicPcmException('麦克风还没有允许使用。您可以到手机设置里允许，然后再点我。刚才没有录下任何声音。');
    }
    try {
      // iosConfig 默认带 defaultToSpeaker，保证外放；须在播放器 setup 之后调用。
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
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

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
    await _recorder.dispose();
  }
}
