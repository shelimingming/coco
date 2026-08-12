import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_text_field.dart';
import '../data/parent_contact_phone_store.dart';

/// 打开系统电话并预填长辈号码；无本地号码时先让子女输入。
Future<void> callParentPhone(
  BuildContext context,
  WidgetRef ref, {
  required String? parentUserId,
  required String parentName,
  bool forceEdit = false,
}) async {
  final store = ref.read(parentContactPhoneStoreProvider);
  final key = parentUserId?.trim() ?? '';
  String? phone = key.isEmpty ? null : await store.read(key);

  if (forceEdit || phone == null || phone.isEmpty) {
    if (!context.mounted) return;
    phone = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ParentPhoneDialog(parentName: parentName, initialPhone: phone),
    );
    if (phone == null) return;
    if (key.isNotEmpty) {
      await store.write(key, phone);
    }
  }

  final ok = await _launchDialer(phone);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('未能打开电话。请确认设备支持拨号后重试。')));
  }
}

Future<bool> _launchDialer(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  // 部分模拟器对 canLaunchUrl(tel) 返回 false，仍尝试打开
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 规范化并校验手机号；非法返回 null。
String? normalizeParentPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('1')) return digits;
  if (digits.length >= 8 && digits.length <= 15) return digits;
  return null;
}

/// 弹窗内自管 TextEditingController，避免路由关闭后提前 dispose。
class _ParentPhoneDialog extends StatefulWidget {
  const _ParentPhoneDialog({required this.parentName, this.initialPhone});

  final String parentName;
  final String? initialPhone;

  @override
  State<_ParentPhoneDialog> createState() => _ParentPhoneDialogState();
}

class _ParentPhoneDialogState extends State<_ParentPhoneDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPhone ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = normalizeParentPhone(_controller.text);
    if (normalized == null) {
      setState(() => _errorText = '请输入有效的手机号码后再试。');
      return;
    }
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CocoColors.childSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CocoRadius.lg),
      ),
      title: Text('拨打${widget.parentName}的电话'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '请输入长辈手机号。号码只保存在本机，用于下次一键拨打。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: CocoColors.neutral700),
          ),
          const SizedBox(height: CocoSpace.s4),
          CocoTextField(
            controller: _controller,
            label: '手机号',
            hint: '请输入11位手机号',
            keyboardType: TextInputType.phone,
            maxLength: 15,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: CocoSpace.s2),
            Text(
              _errorText!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: CocoColors.danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('打开电话')),
      ],
    );
  }
}
