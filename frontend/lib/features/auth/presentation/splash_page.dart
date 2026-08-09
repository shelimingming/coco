import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CocoColors.parentBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '可可',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: CocoColors.parentPrimary,
                  ),
            ),
            const SizedBox(height: CocoSpace.s6),
            const CircularProgressIndicator(),
            const SizedBox(height: CocoSpace.s4),
            Text(
              '正在准备…',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
