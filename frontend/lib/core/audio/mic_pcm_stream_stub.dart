import 'mic_pcm_stream.dart';

/// 非 IO/Web 环境占位（如部分测试 VM）。
MicPcmStream createMicPcmStream() {
  throw UnsupportedError('当前平台不支持麦克风 PCM 采集');
}
