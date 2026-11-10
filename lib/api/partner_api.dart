import 'package:dio/dio.dart';

import 'dto.dart';

/// Partner connection endpoints from the contract. All calls run on the
/// authenticated Dio instance (bearer attached, silent refresh wired).
class PartnerApi {
  PartnerApi(this._dio);

  final Dio _dio;

  /// GET /users/search?email= — exact-email lookup only (the contract has no
  /// directory dump). Returns null when no user matches (404).
  Future<UserResponse?> searchByEmail(String email) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/users/search',
        queryParameters: {'email': email},
      );
      return UserResponse.fromJson(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDio(e);
    }
  }

  /// POST /partner/request/{receiverId} — invites another user. The backend
  /// rejects self-invites, duplicates and existing pairs with 400; callers
  /// surface the envelope message.
  Future<void> sendRequest({required int receiverId}) async {
    try {
      await _dio.post<void>('/partner/request/$receiverId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /partner/current — the connected partner, or null when the user has
  /// none (404).
  Future<Partner?> current() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/partner/current');
      return Partner.fromJson(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDio(e);
    }
  }

  /// GET /partner/requests — requests other users sent to this user.
  Future<List<PartnerRequest>> incomingRequests() async {
    try {
      final res = await _dio.get<List<dynamic>>('/partner/requests');
      return res.data!
          .map((e) => PartnerRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /partner/sent — requests this user sent that are still pending.
  Future<List<SentRequest>> sentRequests() async {
    try {
      final res = await _dio.get<List<dynamic>>('/partner/sent');
      return res.data!
          .map((e) => SentRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /partner/accept/{requestId} — accepts an incoming request.
  Future<void> accept(int requestId) async {
    try {
      await _dio.post<void>('/partner/accept/$requestId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /partner/reject/{requestId} — declines an incoming request.
  Future<void> reject(int requestId) async {
    try {
      await _dio.post<void>('/partner/reject/$requestId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /partner/unpair — ends the current partnership.
  Future<void> unpair() async {
    try {
      await _dio.post<void>('/partner/unpair');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
