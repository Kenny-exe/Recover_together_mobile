import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session's token pair. Abstracted so tests can swap in an
/// in-memory implementation.
abstract class TokenStorage {
  Future<void> save({String? accessToken, String? refreshToken});
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> clear();
}

/// Secure (encrypted) storage on device. On Android this is backed by the
/// Keystore; tokens never touch shared preferences or plain files.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'rt_access_token';
  static const _refreshTokenKey = 'rt_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save({String? accessToken, String? refreshToken}) async {
    if (accessToken != null) {
      await _storage.write(key: _accessTokenKey, value: accessToken);
    }
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
