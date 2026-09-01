import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 页面底部展示的版本号；每次 git commit 小版本 +1（见 AGENTS.md）。
abstract final class AppVersionConfig {
  static const String label = 'v1.0.25';
}

/// 页面底部小号版本号，不抢主内容注意力。
class CocoAppVersionLabel extends StatelessWidget {
  const CocoAppVersionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      AppVersionConfig.label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 10,
        height: 1.2,
        color: CocoColors.neutral500,
      ),
    );
  }
}
