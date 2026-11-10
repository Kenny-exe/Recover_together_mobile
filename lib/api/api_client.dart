import 'package:dio/dio.dart';

import '../auth/token_storage.dart';
import '../config.dart';
import 'auth_api.dart';
import 'dto.dart';

/// HTTP surface of the RecoverTogether backend.
///
/// Two Dio instances, per the contract's auth rules:
/// - [auth]: the PUBLIC endpoints (login, register, refresh, forgot/reset
///   password). No bearer header is attached, so a stale token can never turn
///   a public call into a refresh loop.
/// - [api]: every authenticated endpoint. Attaches the stored bearer token and
///   implements the contract's silent refresh: on a 401, refresh once and
///   replay the request once; if the refresh itself fails, the session is
///   dropped and [onSessionExpired] fires.
class ApiClient {
  ApiClient({required this._storage, String? baseUrl})
      : _baseUrl = baseUrl ?? kBaseUrl {
    final options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    );

    auth = Dio(options);
    api = Dio(options);

    api.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await _storage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }));

    // A plain (non-queued) error interceptor plus the [_refreshInFlight] guard
    // below: parallel 401s share one in-flight refresh. A QueuedInterceptor
    // would deadlock here — it handles errors one at a time, and the replay
    // issued below can 401 again, which would queue behind this very handler.
    api.interceptors.add(InterceptorsWrapper(onError: _onApiError));
  }

  final TokenStorage _storage;
  final String _baseUrl;
  late final Dio auth;
  late final Dio api;
  late final AuthApi authApi = AuthApi(auth);

  /// Invoked when the refresh flow determines the session is over. The UI
  /// drops back to the login screen.
  void Function()? onSessionExpired;

  /// In-flight silent refresh, shared by every 401 that lands while it runs.
  Future<LoginResponse>? _refreshInFlight;

  Future<void> _onApiError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (err.response?.statusCode != 401 || request.extra['__retried'] == true) {
      return handler.next(err);
    }

    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return handler.next(err);
    }

    // Contract: exactly one silent refresh per expired token pair; a failed
    // one ends the session (refresh tokens are rotated single-use, so a 401
    // here means the pair is dead).
    LoginResponse tokens;
    try {
      tokens = await (_refreshInFlight ??= _refreshAndStore(refreshToken));
    } on ApiException {
      await clearSession();
      return handler.next(err);
    } finally {
      _refreshInFlight = null;
    }

    request.extra['__retried'] = true;
    request.headers['Authorization'] = 'Bearer ${tokens.token}';
    try {
      final replay = await api.fetch<dynamic>(request);
      return handler.resolve(replay);
    } on DioException catch (replayErr) {
      // The replay failed despite fresh tokens — surface its own error (not
      // the original 401) and never drop the session for it.
      return handler.next(replayErr);
    }
  }

  /// Refreshes the token pair and persists the rotated one.
  Future<LoginResponse> _refreshAndStore(String refreshToken) async {
    final tokens = await authApi.refresh(refreshToken);
    await _storage.save(
      accessToken: tokens.token,
      refreshToken: tokens.refreshToken,
    );
    return tokens;
  }

  /// Drops tokens and notifies the UI. Safe to call repeatedly.
  Future<void> clearSession() async {
    await _storage.clear();
    onSessionExpired?.call();
  }
}
