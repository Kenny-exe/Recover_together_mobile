import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/dto.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, anonymous, authenticated }

/// Session state for the app: bootstraps from the stored refresh token, owns
/// login/register/logout, and drops to anonymous whenever a silent refresh
/// fails anywhere in the app.
class AuthController extends ChangeNotifier {
  AuthController({required this._client, required this._storage}) {
    _client.onSessionExpired = _handleSessionExpired;
  }

  final ApiClient _client;
  final TokenStorage _storage;

  AuthStatus status = AuthStatus.unknown;
  UserResponse? user;

  Future<void> bootstrap() async {
    if (status != AuthStatus.unknown) return;

    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      status = AuthStatus.anonymous;
      notifyListeners();
      return;
    }

    try {
      final tokens = await _client.authApi.refresh(refreshToken);
      await _storage.save(
        accessToken: tokens.token,
        refreshToken: tokens.refreshToken,
      );
      status = AuthStatus.authenticated;
      notifyListeners();
      await loadMe();
    } on ApiException {
      await _client.clearSession();
      status = AuthStatus.anonymous;
      notifyListeners();
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final tokens = await _client.authApi.login(
      email: email,
      password: password,
    );
    await _storage.save(
      accessToken: tokens.token,
      refreshToken: tokens.refreshToken,
    );
    status = AuthStatus.authenticated;
    notifyListeners();
    await loadMe();
  }

  /// The contract's register response carries the new user but no tokens, so
  /// registration is followed by a login.
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final registered = await _client.authApi.register(
      name: name,
      email: email,
      password: password,
    );
    final tokens = await _client.authApi.login(
      email: email,
      password: password,
    );
    await _storage.save(
      accessToken: tokens.token,
      refreshToken: tokens.refreshToken,
    );
    user = registered;
    status = AuthStatus.authenticated;
    notifyListeners();
  }

  /// GET /users/me — refreshes the profile shown on the home screen.
  Future<void> loadMe() async {
    try {
      final res = await _client.api.get<Map<String, dynamic>>('/users/me');
      user = UserResponse.fromJson(res.data!);
      notifyListeners();
    } on ApiException {
      // The profile is cosmetic here; 401s are already handled by the
      // silent-refresh interceptor.
    }
  }

  /// Best-effort server-side revocation, then the local pair is dropped
  /// regardless (the contract treats logout as client-authoritative for the
  /// UX; the refresh token becomes unusable either way once rotated).
  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    final accessToken = await _storage.readAccessToken();
    try {
      if (refreshToken != null && accessToken != null) {
        await _client.authApi.logout(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
      }
    } on ApiException {
      // Server revocation failed (e.g. offline) — still drop the local pair.
    }
    await _client.clearSession();
    status = AuthStatus.anonymous;
    user = null;
    notifyListeners();
  }

  void _handleSessionExpired() {
    status = AuthStatus.anonymous;
    user = null;
    notifyListeners();
  }
}
