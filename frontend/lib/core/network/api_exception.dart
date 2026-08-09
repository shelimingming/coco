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
      case 'auth.sms_unavailable':
        return '短信服务暂时不可用，请稍后再试。';
      case 'request.invalid':
        return '请求参数不正确，请检查后重试。';
      default:
        return fallback ?? '出了点问题，请稍后再试。';
    }
  }
}
