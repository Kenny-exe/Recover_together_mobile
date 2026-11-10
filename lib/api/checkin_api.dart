import 'package:dio/dio.dart';

import 'dto.dart';

/// Dashboard and daily check-in endpoints from the contract. All calls run on
/// the authenticated Dio instance (bearer attached, silent refresh wired).
class CheckInApi {
  CheckInApi(this._dio);

  final Dio _dio;

  /// GET /dashboard — streaks, aggregate stats, unread count, partner status.
  Future<Dashboard> dashboard() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/dashboard');
      return Dashboard.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /checkin/latest — the most recent check-in, or null when the user
  /// has never checked in (the backend answers 404 for that case).
  Future<CheckIn?> latest() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/checkin/latest');
      return CheckIn.fromJson(res.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDio(e);
    }
  }

  /// POST /checkin — one check-in per user-local day; a duplicate returns 400
  /// with the envelope message ("You have already checked in today").
  Future<void> submit({
    required CheckInStatus status,
    String? note,
  }) async {
    try {
      await _dio.post<void>(
        '/checkin',
        data: {
          'status': status.wire,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
