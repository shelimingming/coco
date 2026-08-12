import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 用服务端下发的长辈号码打开系统拨号盘；Web 改为复制号码。
Future<void> callParentPhone(
  BuildContext context, {
  required String parentName,
  required String? parentPhone,
}) async {
  final phone = parentPhone?.trim() ?? '';
  if (phone.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('暂时没有$parentName的手机号。请让长辈重新登录一次后，再试拨打。数据未受影响。')),
    );
    return;
  }

  if (kIsWeb) {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制$parentName的号码 $phone，请用手机拨打。')));
    return;
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
