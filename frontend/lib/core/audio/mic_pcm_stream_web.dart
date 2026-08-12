import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'mic_pcm_stream.dart';

/// Web：getUserMedia + ScriptProcessor，重采样为 16k Int16 PCM。
MicPcmStream createMicPcmStream() => WebMicPcmStream();

class WebMicPcmStream implements MicPcmStream {
  web.AudioContext? _ctx;
  web.MediaStream? _mediaStream;
  web.ScriptProcessorNode? _processor;
  web.MediaStreamAudioSourceNode? _source;
  final _controller = StreamController<Uint8List>.broadcast();
  bool _suppress = false;
  bool _recording = false;

  // 线性重采样状态（输入采样率 → 16000）
  double _resamplePos = 0;
  double _lastSample = 0;

  static const int _targetRate = 16000;
  static const int _bufferSize = 4096;

  @override
  Stream<Uint8List> get pcmStream => _controller.stream;

  @override
  bool get isRecording => _recording;

  @override
  set suppress(bool value) => _suppress = value;

  @override
  Future<bool> hasPermission() async {
    // 浏览器无预检 API；真正授权在 start 时弹出。
    return true;
  }

  @override
  Future<void> start() async {
    await stop();
    try {
      final devices = web.window.navigator.mediaDevices;
      final stream = await devices
          .getUserMedia(
            web.MediaStreamConstraints(audio: true.toJS, video: false.toJS),
          )
          .toDart;
      _mediaStream = stream;

      final ctx = web.AudioContext();
      _ctx = ctx;
      if (ctx.state == 'suspended') {
        await ctx.resume().toDart;
      }

      _source = ctx.createMediaStreamSource(stream);
      // ScriptProcessor 虽弃用，但无需单独 worklet 文件，MVP 足够。
      final processor = ctx.createScriptProcessor(_bufferSize, 1, 1);
      _processor = processor;
      _resamplePos = 0;
      _lastSample = 0;

      processor.onaudioprocess = ((web.AudioProcessingEvent event) {
        if (_suppress || _controller.isClosed || !_recording) return;
        final input = event.inputBuffer.getChannelData(0).toDart;
        final pcm = _resampleToPcm16(input, ctx.sampleRate.toDouble());
        if (pcm.isNotEmpty) {
          _controller.add(pcm);
        }
      }).toJS;

      _source!.connect(processor);
      // 接到 destination 才会拉起 onaudioprocess；增益 0 避免扬声器回授。
      final mute = ctx.createGain();
      mute.gain.value = 0;
      processor.connect(mute);
      mute.connect(ctx.destination);
      _recording = true;
    } catch (_) {
      await stop();
      throw const MicPcmException(
        '麦克风还没有允许使用。请在浏览器地址栏允许麦克风，然后再点形象。刚才没有录下任何声音。',
      );
    }
  }

  /// 将 Float32 输入重采样并转为 little-endian Int16 PCM bytes。
  Uint8List _resampleToPcm16(Float32List input, double inputRate) {
    if (input.isEmpty || inputRate <= 0) return Uint8List(0);
    final ratio = inputRate / _targetRate;
    final outLen = ((input.length - _resamplePos) / ratio).floor();
    if (outLen <= 0) return Uint8List(0);

    final bytes = Uint8List(outLen * 2);
    final bd = ByteData.sublistView(bytes);
    var pos = _resamplePos;
    var last = _lastSample;
    var outIndex = 0;

    for (var i = 0; i < outLen; i++) {
      final idx = pos.floor();
      final frac = pos - idx;
      final s0 = idx < input.length ? input[idx] : last;
      final s1 = (idx + 1) < input.length ? input[idx + 1] : s0;
      final sample = s0 + (s1 - s0) * frac;
      last = sample;
      final clamped = sample.clamp(-1.0, 1.0);
      final int16 = (clamped * 32767).round();
      bd.setInt16(outIndex * 2, int16, Endian.little);
      outIndex++;
      pos += ratio;
    }

    // 保留小数相位，跨 buffer 连续
    _resamplePos = pos - input.length;
    if (_resamplePos < 0) _resamplePos = 0;
    _lastSample = last;
    return bytes;
  }

  @override
  Future<void> stop() async {
    _recording = false;
    try {
      _processor?.disconnect();
    } catch (_) {}
    try {
      _source?.disconnect();
    } catch (_) {}
    _processor = null;
    _source = null;

    final tracks = _mediaStream?.getTracks().toDart ?? const [];
    for (final track in tracks) {
      track.stop();
    }
    _mediaStream = null;

    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _ctx = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
