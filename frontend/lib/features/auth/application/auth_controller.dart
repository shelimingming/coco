import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/auth_repository.dart';
import '../domain/models.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository) : super(const AuthState()) {
    // 启动后立刻尝试静默续期
    Future<void>.microtask(bootstrap);
  }

  final AuthRepository _repository;

  Future<void> bootstrap() async {
    if (state.isBootstrapped) {
      return;
    }
    try {
      final user = await _repository.bootstrap();
      state = state.copyWith(
        isBootstrapped: true,
        user: user,
        clearUser: user == null,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isBootstrapped: true,
        clearUser: true,
        errorMessage: _messageOf(error),
      );
    }
  }

  void selectRole(UserRole role) {
    state = state.copyWith(
      selectedRole: role,
      step: LoginStep.phone,
      clearError: true,
    );
  }

  void backToRole() {
    state = state.copyWith(
      step: LoginStep.role,
      clearChallenge: true,
      clearError: true,
    );
  }

  void backToPhone() {
    state = state.copyWith(
      step: LoginStep.phone,
      clearChallenge: true,
      clearError: true,
    );
  }

  Future<void> requestCode(String phone) async {
    state = state.copyWith(isBusy: true, clearError: true, phone: phone);
    try {
      final challenge = await _repository.requestPhoneCode(phone);
      state = state.copyWith(
        isBusy: false,
        challenge: challenge,
        step: LoginStep.code,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: _messageOf(error));
    }
  }

  Future<bool> verifyCode({
    required String code,
    String? displayName,
  }) async {
    final challenge = state.challenge;
    if (challenge == null) {
      state = state.copyWith(errorMessage: '请先获取验证码。');
      return false;
    }

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repository.loginWithPhone(
        challengeId: challenge.challengeId,
        phone: state.phone,
        code: code,
        role: state.selectedRole,
        displayName: displayName,
      );
      state = state.copyWith(
        isBusy: false,
        user: user,
        step: LoginStep.role,
        clearChallenge: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: _messageOf(error));
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isBusy: true, clearError: true);
    await _repository.logout();
    state = const AuthState(isBootstrapped: true);
  }

  String _messageOf(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return '出了点问题，请稍后再试。';
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
