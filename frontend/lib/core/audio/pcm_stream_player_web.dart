import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pcm_stream_player.dart';

/// Web Audio：队列调度 Int16 PCM，排空后触发 onDrained。
PcmStreamPlayer createPcmStreamPlayer({int sampleRate = 24000}) =>
    WebPcmStreamPlayer(sampleRate: sampleRate);

class WebPcmStreamPlayer implements PcmStreamPlayer {
  WebPcmStreamPlayer({this.sampleRate = 24000});

  final int sampleRate;
  void Function()? _onDrained;
  web.AudioContext? _ctx;
  double _nextStart = 0;
  int _pendingSources = 0;
  bool _expectDrain = false;
  bool _disposed = false;
  final List<web.AudioBufferSourceNode> _active = [];

  @override
  set onDrained(void Function()? callback) => _onDrained = callback;

  @override
  Future<void> prepare() async {
    if (_disposed) return;
    final ctx = _ctx ?? web.AudioContext();
    _ctx = ctx;
    if (ctx.state == 'suspended') {
      await ctx.resume().toDart;
    }
    _nextStart = ctx.currentTime;
  }

  @override
  Future<void> feed(Uint8List pcm, {required int sampleRate}) async {
    if (_disposed || pcm.isEmpty) return;
    await prepare();
    final ctx = _ctx!;
    final rate = sampleRate > 0 ? sampleRate : this.sampleRate;
    final frameCount = pcm.length ~/ 2;
    if (frameCount <= 0) return;

    final buffer = ctx.createBuffer(1, frameCount, rate.toDouble());
    final channel = buffer.getChannelData(0).toDart;
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i < frameCount; i++) {
      channel[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }

    final source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);

    final startAt = _nextStart < ctx.currentTime ? ctx.currentTime : _nextStart;
    source.start(startAt);
    _nextStart = startAt + buffer.duration;
    _pendingSources++;
    _active.add(source);

    source.onended = ((web.Event _) {
      _active.remove(source);
      _pendingSources = (_pendingSources - 1).clamp(0, 1 << 30);
      _maybeDrain();
    }).toJS;
  }

  @override
  void markResponseComplete() {
    _expectDrain = true;
    _maybeDrain();
  }

  void _maybeDrain() {
    if (!_expectDrain || _pendingSources > 0 || _disposed) return;
    _expectDrain = false;
    _onDrained?.call();
  }

  @override
  Future<void> clear() async {
    _expectDrain = false;
    for (final source in List<web.AudioBufferSourceNode>.from(_active)) {
      try {
        source.onended = null;
        source.stop();
        source.disconnect();
      } catch (_) {}
    }
    _active.clear();
    _pendingSources = 0;
    final ctx = _ctx;
    if (ctx != null) {
      _nextStart = ctx.currentTime;
    }
  }

  @override
  Future<void> stop() => clear();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _onDrained = null;
    await clear();
    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _ctx = null;
  }
}
