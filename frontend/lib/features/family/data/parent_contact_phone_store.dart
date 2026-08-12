import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 子女端本地保存的长辈联系电话。
/// 登录手机号服务端只存 HMAC，无法下发明文，故由子女首次填写并本机复用。
class ParentContactPhoneStore {
  ParentContactPhoneStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String parentUserId) =>
      'coco_parent_contact_phone_$parentUserId';

  Future<String?> read(String parentUserId) {
    if (parentUserId.isEmpty) return Future.value(null);
    return _storage.read(key: _key(parentUserId));
  }

  Future<void> write(String parentUserId, String phone) {
    return _storage.write(key: _key(parentUserId), value: phone);
  }

  Future<void> clear(String parentUserId) {
    return _storage.delete(key: _key(parentUserId));
  }
}

final parentContactPhoneStoreProvider = Provider<ParentContactPhoneStore>((
  ref,
) {
  return ParentContactPhoneStore();
});
