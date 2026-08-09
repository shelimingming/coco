import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../../core/widgets/coco_text_field.dart';
import '../application/messages_providers.dart';
import '../data/messages_api.dart';
import '../domain/models.dart';

/// 子女报平安撰写：快捷状态 + 自定义，预览确认后发送。
class ChildComposeMessagePage extends ConsumerStatefulWidget {
  const ChildComposeMessagePage({super.key});

  @override
  ConsumerState<ChildComposeMessagePage> createState() =>
      _ChildComposeMessagePageState();
}

class _ChildComposeMessagePageState
    extends ConsumerState<ChildComposeMessagePage> {
  static const _presets = ['吃过饭了', '正在忙，一切都好', '已经到家', '准备休息'];

  final _customController = TextEditingController();
  MessagePreview? _preview;
  // 区分预览/发送，让对应按钮显示语义 loading
  _ComposeBusy? _busy;
  String? _error;

  bool get _isBusy => _busy != null;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _previewText(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      setState(() => _error = '请先选择或输入要发送的内容。');
      return;
    }
    setState(() {
      _busy = _ComposeBusy.preview;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await ref.read(messagesApiProvider).preview(cleaned);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = error is ApiException
            ? error.message
            : '预览失败。您可以再试一次，消息没有发出去。';
      });
    }
  }

  Future<void> _send() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _busy = _ComposeBusy.send;
      _error = null;
    });
    try {
      await ref
          .read(messagesApiProvider)
          .send(
            originalText: preview.originalText,
            deliveredText: preview.deliveredText,
          );
      // 回到列表并刷新，让新消息置顶出现
      ref.invalidate(familyMessagesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已发送给父母。')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = error is ApiException
            ? error.message
            : '发送失败。您可以再试一次，消息没有发出去。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return CocoScaffold(
      title: '报个平安',
      body: ListView(
        children: [
          Text(
            '选一句快捷状态，或自己写一句。发送前会先让您预览。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s5),
          Wrap(
            spacing: CocoSpace.s3,
            runSpacing: CocoSpace.s3,
            children: _presets
                .map(
                  (text) => ActionChip(
                    label: Text(text),
                    backgroundColor: CocoColors.childPrimarySoft,
                    onPressed: _isBusy ? null : () => _previewText(text),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: CocoSpace.s6),
          CocoTextField(
            controller: _customController,
            label: '自己写一句',
            hint: '例如：刚开完会，晚上再联系',
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '预览这句话',
            loading: _busy == _ComposeBusy.preview,
            loadingLabel: '正在预览…',
            onPressed: _isBusy
                ? null
                : () => _previewText(_customController.text),
          ),
          if (preview != null) ...[
            const SizedBox(height: CocoSpace.s6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(CocoSpace.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('发送预览', style: theme.textTheme.titleMedium),
                    const SizedBox(height: CocoSpace.s3),
                    Text(
                      preview.deliveredText,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: CocoSpace.s2),
                    Text(
                      preview.translated
                          ? '以上由 AI 转译，便于父母理解。'
                          : '当前为原文直发（未走 AI 转译）。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: CocoSpace.s4),
            CocoPrimaryButton(
              label: '确认发送',
              loading: _busy == _ComposeBusy.send,
              loadingLabel: '正在发送…',
              onPressed: _isBusy ? null : _send,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: CocoSpace.s4),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.danger,
              ),
            ),
          ],
          const SizedBox(height: CocoSpace.s6),
          CocoSecondaryButton(
            label: '返回',
            onPressed: _isBusy ? null : () => context.pop(),
          ),
        ],
      ),
    );
  }
}

enum _ComposeBusy { preview, send }
