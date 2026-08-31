import 'dart:typed_data';

/// 轻量帧指纹：抽样字节 XOR / 累加，用于判断画面是否离开可可、是否 settle。
/// 不做加密哈希，只求快、稳定、够用。
int screenFrameFingerprint(Uint8List bytes) {
  if (bytes.isEmpty) return 0;
  var h = bytes.length;
  // 均匀抽样最多 256 个点，避免整图扫描
  final step = (bytes.length / 256).ceil().clamp(1, bytes.length);
  for (var i = 0; i < bytes.length; i += step) {
    h = 0x1fffffff & (h * 31 + bytes[i]);
  }
  return h;
}

/// 两帧指纹是否「足够不同」（异于基线 / 换屏）。
bool screenFramesDiffer(int a, int b, {int minDelta = 8}) {
  if (a == 0 || b == 0) return a != b;
  final d = (a - b).abs();
  return d >= minDelta;
}

/// 连续样本是否已稳定（相邻指纹差异小）。
bool screenFramesSettled(List<int> recent, {int maxDelta = 4}) {
  if (recent.length < 2) return false;
  for (var i = 1; i < recent.length; i++) {
    if ((recent[i] - recent[i - 1]).abs() > maxDelta) return false;
  }
  return true;
}
