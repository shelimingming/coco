/// 可直接展示给用户的 API 错误。
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;

  /// 将后端 error.code 映射为中文兜底文案。
  static String messageForCode(String? code, {String? fallback}) {
    switch (code) {
      case 'auth.invalid_phone':
        return '请输入正确的大陆手机号。';
      case 'auth.too_many_codes':
        return '验证码发送过于频繁，请稍后再试。';
      case 'auth.invalid_or_expired_code':
        return '验证码不正确或已过期。';
      case 'auth.too_many_attempts':
        return '尝试次数过多，请重新获取验证码。';
      case 'auth.session_expired':
      case 'auth.invalid_token':
      case 'auth.missing_token':
        return '登录已失效，请重新登录。';
      case 'auth.user_disabled':
        return '账号不可用，请联系支持。';
      case 'auth.role_locked':
        return '您的账号已绑定家庭，请用正确的身份登录。';
      case 'auth.sms_unavailable':
        return '短信服务暂时不可用，请稍后再试。';
      case 'family.not_found':
        return '还没有绑定家庭。请先完成父母与子女的绑定。';
      case 'family.invalid_invite':
        return '邀请无效或已被使用。请向家人重新索取。';
      case 'family.already_bound':
      case 'family.already_joined':
        return '家庭已经绑定过了，不能重复操作。';
      case 'family.parent_required':
      case 'reminder.parent_required':
      case 'memory.parent_required':
      case 'care.parent_required':
        return '这项操作需要在老人模式下完成。';
      case 'family.child_required':
      case 'care.child_required':
      case 'message.child_required':
        return '这项操作需要在子女模式下完成。';
      case 'care.no_child':
        return '还没有绑定子女，无法分享。';
      case 'reminder.not_found':
        return '找不到这个提醒，可能已被删除。';
      case 'memory.not_found':
        return '找不到这条记忆，可能已被删除。';
      case 'request.invalid':
        return '请求参数不正确，请检查后重试。';
      default:
        return fallback ?? '出了点问题，请稍后再试。';
    }
  }
}
