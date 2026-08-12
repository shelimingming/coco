import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../../core/widgets/coco_text_field.dart';
import '../../reminders/application/reminders_providers.dart';
import '../../reminders/data/reminders_api.dart';

/// 子女为父母创建提醒建议；须父母确认后才调度。
class ChildSuggestReminderPage extends ConsumerStatefulWidget {
  const ChildSuggestReminderPage({super.key});

  @override
  ConsumerState<ChildSuggestReminderPage> createState() =>
      _ChildSuggestReminderPageState();
}

class _ChildSuggestReminderPageState
    extends ConsumerState<ChildSuggestReminderPage> {
  final _titleController = TextEditingController();
  bool _daily = true;
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请先写下要提醒的事情。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');
    try {
      await ref
          .read(remindersApiProvider)
          .createSuggestion(
            title: title,
            scheduleType: _daily ? 'DAILY' : 'ONCE',
            scheduleTime: '$hh:$mm:00',
          );
      ref.invalidate(childSuggestionsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已发给父母确认：$title，$hh:$mm')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : '提醒建议没有发出去。您可以再试一次，没有写入错误数据。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');

    return CocoScaffold(
      title: '给父母设提醒',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '提醒会先发给父母确认，确认后才会到点提醒。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s5),
          CocoTextField(
            controller: _titleController,
            label: '提醒什么',
            hint: '例如：吃药',
          ),
          const SizedBox(height: CocoSpace.s5),
          Text('什么时候', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(label: '时间 $hh:$mm', onPressed: _pickTime),
          const SizedBox(height: CocoSpace.s4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('每天提醒', style: theme.textTheme.bodyLarge),
            value: _daily,
            activeThumbColor: CocoColors.childPrimary,
            onChanged: (value) => setState(() => _daily = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: CocoSpace.s3),
            Text(
              _error!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: CocoColors.danger,
              ),
            ),
          ],
          const Spacer(),
          CocoPrimaryButton(
            label: '发给父母确认',
            loading: _busy,
            loadingLabel: '正在发送…',
            onPressed: _submit,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(label: '取消', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}
