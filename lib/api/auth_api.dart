import 'package:dio/dio.dart';

import 'dto.dart';

/// Auth endpoints from the contract. All calls run on the bare public [Dio]
/// (no bearer header, no refresh interceptor) except [logout], which the
/// contract defines as JWT-authenticated.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  /// POST /auth/login — public, IP-rate-limited (30/min), returns the token
  /// pair. Lockout and wrong passwords both surface as 401 with the generic
  /// message.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return LoginResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /users/register — public. Returns the new user; it does NOT carry
  /// tokens, so callers follow up with [login]. Timezone is optional per the
  /// contract and omitted here for now (server default: UTC).
  Future<UserResponse> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/users/register',
        data: {'name': name, 'email': email, 'password': password},
      );
      return UserResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /auth/refresh — public. The presented refresh token is rotated
  /// (single use); store the returned pair immediately.
  Future<LoginResponse> refresh(String refreshToken) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return LoginResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /auth/logout — requires the bearer header AND the refresh token in
  /// the body; revokes that refresh token server-side.
  Future<void> logout({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
