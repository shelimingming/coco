import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/coco_loading.dart';

/// 旧撰写全屏页并入报平安 Tab，保留路由以免深链失效。
class ChildComposeMessagePage extends StatelessWidget {
  const ChildComposeMessagePage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.go('/child/messages');
      }
    });
    return const Scaffold(body: CocoPageLoading(message: '正在打开报平安…'));
  }
}
