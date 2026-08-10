import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';

/// 识图结果页「还想问」：暂存结论，回首页后注入语音开场。
final pendingLookContextProvider = StateProvider<LookResult?>((ref) => null);
