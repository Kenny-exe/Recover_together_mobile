import 'package:dio/dio.dart';

/// Response of POST /auth/login and POST /auth/refresh (contract:
/// `LoginResponse`). `tokenType` is always "Bearer"; treat both tokens as
/// opaque strings.
class LoginResponse {
  LoginResponse({
    required this.token,
    required this.refreshToken,
    required this.tokenType,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String? ?? '',
        tokenType: json['tokenType'] as String? ?? 'Bearer',
      );

  final String token;
  final String refreshToken;
  final String tokenType;
}

/// GET /users/me, register and profile-update responses (contract:
/// `UserResponse`). Never carries secrets.
class UserResponse {
  UserResponse({
    required this.id,
    required this.name,
    required this.email,
    required this.timezone,
    this.createdAt,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) => UserResponse(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        timezone: json['timezone'] as String? ?? 'UTC',
        createdAt: json['createdAt'] as String?,
      );

  final int id;
  final String name;
  final String email;
  final String timezone;
  final String? createdAt;
}

/// The contract's error envelope: `{timestamp, status, message}`. Every error
/// body from the backend has this shape; [message] is safe to show to the user.
class ApiException implements Exception {
  ApiException({this.status, required this.message});

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return ApiException(
        status: e.response?.statusCode,
        message: data['message'] as String,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: 'Cannot reach the server. Check your connection.',
        );
      default:
        return ApiException(
          status: e.response?.statusCode,
          message: 'Something went wrong. Please try again.',
        );
    }
  }

  final int? status;
  final String message;

  @override
  String toString() => message;
}
