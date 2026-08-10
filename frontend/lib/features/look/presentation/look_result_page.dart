import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../parent/domain/coco_companion_pose.dart';
import '../../parent/presentation/widgets/coco_companion_view.dart';
import '../domain/models.dart';

/// 识图结果：结论 / 看不清 同一页两种状态。
class LookResultPage extends ConsumerWidget {
  const LookResultPage({super.key, required this.session});

  final LookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = session.result;
    final clear = result.isClear;

    return CocoScaffold(
      title: clear ? '可可看懂了' : '没有看清',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CocoCompanionView(
                      pose: clear
                          ? CocoCompanionPose.done
                          : CocoCompanionPose.uncertain,
                      size: 140,
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s5),
                  if (clear) ...[
                    Text(
                      result.headline,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: CocoColors.parentPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    if (result.detail.trim().isNotEmpty) ...[
                      const SizedBox(height: CocoSpace.s3),
                      Text(
                        result.detail,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: CocoColors.neutral700,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (result.safetyNote.trim().isNotEmpty) ...[
                      const SizedBox(height: CocoSpace.s5),
                      Container(
                        padding: const EdgeInsets.all(CocoSpace.s4),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            CocoColors.warning.withValues(alpha: 0.12),
                            CocoColors.parentSurface,
                          ),
                          borderRadius: BorderRadius.circular(CocoRadius.md),
                        ),
                        child: Text(
                          result.safetyNote,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: CocoColors.warning,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    Text(
                      '我看不太清这上面的字',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: CocoColors.neutral950,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s3),
                    Text(
                      result.detail.trim().isNotEmpty
                          ? result.detail
                          : '请拿稳一点，重新拍一张；也可以请家人帮忙看。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: CocoColors.neutral700,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (clear) ...[
            CocoPrimaryButton(
              label: '还想问',
              onPressed: () {
                final conversationId = result.conversationId;
                if (conversationId == null || conversationId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('这次没法继续问。请重新拍一张。')),
                  );
                  return;
                }
                // 同会话追问：留在识图链路，不跳回实时语音
                context.push(
                  '/parent/look/ask',
                  extra: LookAskArgs(
                    conversationId: conversationId,
                    imagePath: session.imagePath,
                    headline: result.headline,
                    spokenSummary: result.spokenSummary,
                  ),
                );
              },
            ),
            const SizedBox(height: CocoSpace.s3),
            CocoSecondaryButton(
              label: '知道了',
              onPressed: () => context.go('/parent'),
            ),
            const SizedBox(height: CocoSpace.s3),
            CocoSecondaryButton(label: '重新拍一张', onPressed: () => context.pop()),
          ] else ...[
            CocoPrimaryButton(label: '重新拍一张', onPressed: () => context.pop()),
            const SizedBox(height: CocoSpace.s3),
            CocoSecondaryButton(
              label: '让家人帮忙看',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('可以给家人打电话或发消息，请他们帮忙看。')),
                );
                context.go('/parent');
              },
            ),
          ],
        ],
      ),
    );
  }
}
