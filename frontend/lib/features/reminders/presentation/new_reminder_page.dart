import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../../core/widgets/coco_text_field.dart';
import '../application/reminders_providers.dart';
import '../data/reminders_api.dart';

/// 父母端手动创建提醒（语音创建是主路径，这里是兜底）。
class NewReminderPage extends ConsumerStatefulWidget {
  const NewReminderPage({super.key});

  @override
  ConsumerState<NewReminderPage> createState() => _NewReminderPageState();
}

class _NewReminderPageState extends ConsumerState<NewReminderPage> {
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
          .create(
            title: title,
            scheduleType: _daily ? 'DAILY' : 'ONCE',
            scheduleTime: '$hh:$mm:00',
          );
      ref.invalidate(remindersListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已设好：$title，$hh:$mm')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : '提醒没有设成功。您可以再试一次，没有写入错误数据。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hh = _time.hour.toString().padLeft(2, '0');
    final mm = _time.minute.toString().padLeft(2, '0');

    return CocoScaffold(
      title: '新建提醒',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            activeThumbColor: CocoColors.parentPrimary,
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
            label: '确认这个提醒',
            loading: _busy,
            loadingLabel: '正在保存…',
            onPressed: _submit,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(label: '取消', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}
