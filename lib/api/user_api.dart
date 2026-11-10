import 'package:dio/dio.dart';

import 'dto.dart';

/// Profile management endpoints from the contract. All calls run on the
/// authenticated Dio instance (bearer attached, silent refresh wired).
class UserApi {
  UserApi(this._dio);

  final Dio _dio;

  /// PUT /users/me — updates name/email and optionally the IANA timezone
  /// (invalid ids are rejected with 400; an omitted timezone keeps the
  /// current one). Returns the updated user.
  Future<UserResponse> updateProfile({
    required String name,
    required String email,
    String? timezone,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/users/me',
        data: {
          'name': name,
          'email': email,
          if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        },
      );
      return UserResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /users/change-password — on success the backend invalidates ALL of
  /// the user's tokens and revokes every refresh token, so the client must
  /// drop its stored pair and return to the login screen.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post<void>(
        '/users/change-password',
        data: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /users/me — irreversible account deletion; requires the current
  /// password in the body (a bare token is not enough). A wrong password is a
  /// 400, audited, and counts toward the login lockout (locked → 429).
  /// Database-level cascades remove all of the user's owned rows.
  Future<void> deleteAccount({required String password}) async {
    try {
      await _dio.delete<void>(
        '/users/me',
        data: {'password': password},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
