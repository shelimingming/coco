import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 客户端与 Coco Realtime WebSocket 的精简事件。
class RealtimeSocketEvent {
  const RealtimeSocketEvent(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;

  String? get text {
    final value = payload['text'];
    return value is String ? value : null;
  }

  String? get audioBase64 {
    final value = payload['audio'];
    return value is String ? value : null;
  }

  int get sampleRate {
    final value = payload['sample_rate'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 24000;
  }

  String? get message {
    final value = payload['message'];
    return value is String ? value : null;
  }

  String? get code {
    final value = payload['code'];
    return value is String ? value : null;
  }
}

/// 鉴权 Realtime WebSocket：密钥不在此层，仅携带服务端下发的 access_token。
class RealtimeVoiceSocket {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _events = StreamController<RealtimeSocketEvent>.broadcast();

  Stream<RealtimeSocketEvent> get events => _events.stream;

  bool get isConnected => _channel != null;

  /// 由 Dio baseUrl 推导 ws/wss，并附带 JWT。
  /// 空 baseUrl（Docker 同源部署）时用当前页面 origin。
  static Uri buildUri({
    required String httpBaseUrl,
    required String accessToken,
  }) {
    final trimmed = httpBaseUrl.trim();
    final parsed = trimmed.isEmpty ? Uri.base : Uri.parse(trimmed);
    // 无 host 时视为同源（相对地址 / 空配置）
    final base = parsed.hasAuthority ? parsed : Uri.base;
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/v1/voice/realtime',
      queryParameters: {'access_token': accessToken},
    );
  }

  Future<void> connect(Uri uri) async {
    await close();
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
    _subscription = channel.stream.listen(
      _onRawMessage,
      onError: (_) {
        if (!_events.isClosed) {
          _events.add(
            const RealtimeSocketEvent('error', {
              'code': 'realtime.connection_lost',
              'message': '语音连接中断了。您可以重新点形象开始。刚才的内容没有额外保存。',
            }),
          );
        }
      },
      onDone: () {
        if (!_events.isClosed) {
          _events.add(const RealtimeSocketEvent('closed', {}));
        }
      },
      cancelOnError: false,
    );
  }

  void _onRawMessage(dynamic raw) {
    if (_events.isClosed) return;
    try {
      final decoded = raw is String
          ? jsonDecode(raw)
          : jsonDecode(utf8.decode(raw as List<int>));
      if (decoded is! Map) return;
      final type = decoded['type'];
      if (type is! String) return;
      final payload = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key == 'type') continue;
        payload[entry.key.toString()] = entry.value;
      }
      _events.add(RealtimeSocketEvent(type, payload));
    } catch (_) {
      // 忽略无法解析的帧，避免打断通话。
    }
  }

  Future<void> sendAudioPcm(Uint8List pcm) async {
    final channel = _channel;
    if (channel == null || pcm.isEmpty) return;
    channel.sink.add(
      jsonEncode({'type': 'audio.append', 'audio': base64Encode(pcm)}),
    );
  }

  Future<void> cancelResponse() async {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({'type': 'response.cancel'}));
  }

  /// 大卡点确认：服务端落库并告知模型已办妥。
  Future<void> confirmPendingAction(String draftId) async {
    final channel = _channel;
    if (channel == null || draftId.isEmpty) return;
    channel.sink.add(
      jsonEncode({'type': 'action.confirm', 'draft_id': draftId}),
    );
  }

  /// 大卡「先不要」：取消草稿，不落库。
  Future<void> cancelPendingAction(String draftId) async {
    final channel = _channel;
    if (channel == null || draftId.isEmpty) return;
    channel.sink.add(
      jsonEncode({'type': 'action.cancel', 'draft_id': draftId}),
    );
  }

  /// 把多模态读图结果注入当前 Realtime 会话，触发可可开口讲照片。
  Future<void> injectVisionContext({
    required String sceneDescription,
    String? source,
  }) async {
    final channel = _channel;
    if (channel == null) return;
    final scene = sceneDescription.trim();
    if (scene.isEmpty) return;
    channel.sink.add(
      jsonEncode({
        'type': 'vision.inject',
        'scene_description': scene,
        if (source != null && source.isNotEmpty) 'source': source,
      }),
    );
  }

  Future<void> endSession() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': 'session.end'}));
    } catch (_) {}
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }
}
