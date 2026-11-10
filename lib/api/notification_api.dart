import 'package:dio/dio.dart';

import 'dto.dart';

/// Notification endpoints from the contract. All calls run on the
/// authenticated Dio instance (bearer attached, silent refresh wired).
class NotificationApi {
  NotificationApi(this._dio);

  final Dio _dio;

  /// GET /notifications — newest-first cursor page. [beforeId] is exclusive
  /// (strictly smaller ids only); [limit] defaults to 20.
  Future<List<AppNotification>> list({int limit = 20, int? beforeId}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/notifications',
        queryParameters: {
          'limit': limit,
          'beforeId': ?beforeId,
        },
      );
      return res.data!
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /notifications/unread-count.
  Future<int> unreadCount() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/notifications/unread-count');
      return res.data?['unreadCount'] as int? ?? 0;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PUT /notifications/read/{notificationId} — marks one notification read.
  Future<void> markRead(int notificationId) async {
    try {
      await _dio.put<void>('/notifications/read/$notificationId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PUT /notifications/read-all — marks everything read, including items
  /// beyond the currently loaded page.
  Future<void> markAllRead() async {
    try {
      await _dio.put<void>('/notifications/read-all');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /notifications/{id} — removes one notification.
  Future<void> remove(int notificationId) async {
    try {
      await _dio.delete<void>('/notifications/$notificationId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /notifications/all — clears the whole inbox.
  Future<void> removeAll() async {
    try {
      await _dio.delete<void>('/notifications/all');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// GET /notifications/preferences.
  Future<NotificationPreferences> preferences() async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>('/notifications/preferences');
      return NotificationPreferences.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// PUT /notifications/preferences — patch-style: only non-null fields of
  /// [patch] are sent, the server keeps the rest. Enabling quiet hours with
  /// missing or equal times is a 400; SOS_ALERT can never be disabled.
  Future<NotificationPreferences> updatePreferences(
    NotificationPreferences patch,
  ) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
        '/notifications/preferences',
        data: patch.toJson(),
      );
      return NotificationPreferences.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
