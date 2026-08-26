enum UserRole {
  parent,
  child;

  static UserRole fromJson(String value) {
    return UserRole.values.firstWhere(
      (item) => item.name == value,
      orElse: () => UserRole.parent,
    );
  }

  /// 对外展示文案：长辈 / 子女（与角色选择页一致）。
  String get label => this == UserRole.parent ? '长辈' : '子女';
}

class AppUser {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.role,
    required this.phoneMasked,
    required this.status,
  });

  final String id;
  final String displayName;
  final UserRole role;
  final String phoneMasked;
  final String status;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      role: UserRole.fromJson(json['role'] as String),
      phoneMasked: json['phone_masked'] as String,
      status: json['status'] as String,
    );
  }
}

class PhoneChallenge {
  const PhoneChallenge({
    required this.challengeId,
    required this.expiresAt,
    required this.isRegistered,
    this.devCode,
  });

  final String challengeId;
  final DateTime expiresAt;
  final bool isRegistered;
  final String? devCode;

  factory PhoneChallenge.fromJson(Map<String, dynamic> json) {
    return PhoneChallenge(
      challengeId: json['challenge_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      isRegistered: json['is_registered'] as bool? ?? false,
      devCode: json['dev_code'] as String?,
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AppUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

enum LoginStep { role, phone, code }

class AuthState {
  const AuthState({
    this.isBootstrapped = false,
    this.isBusy = false,
    this.user,
    this.selectedRole = UserRole.parent,
    this.step = LoginStep.role,
    this.phone = '',
    this.challenge,
    this.errorMessage,
  });

  final bool isBootstrapped;
  final bool isBusy;
  final AppUser? user;
  final UserRole selectedRole;
  final LoginStep step;
  final String phone;
  final PhoneChallenge? challenge;
  final String? errorMessage;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    bool? isBootstrapped,
    bool? isBusy,
    AppUser? user,
    bool clearUser = false,
    UserRole? selectedRole,
    LoginStep? step,
    String? phone,
    PhoneChallenge? challenge,
    bool clearChallenge = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      isBootstrapped: isBootstrapped ?? this.isBootstrapped,
      isBusy: isBusy ?? this.isBusy,
      user: clearUser ? null : (user ?? this.user),
      selectedRole: selectedRole ?? this.selectedRole,
      step: step ?? this.step,
      phone: phone ?? this.phone,
      challenge: clearChallenge ? null : (challenge ?? this.challenge),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
