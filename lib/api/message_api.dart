import 'package:dio/dio.dart';

import 'dto.dart';

/// Chat endpoints from the contract. All calls run on the authenticated Dio
/// instance (bearer attached, silent refresh wired).
class MessageApi {
  MessageApi(this._dio);

  final Dio _dio;

  /// GET /messages/conversation/{partnerId} — one cursor page of the thread,
  /// chronological (oldest → newest). [beforeId] is exclusive: only messages
  /// with a strictly smaller id are returned; when paging backwards pass the
  /// smallest id of the previous page. [limit] defaults to 50 and the backend
  /// clamps it to 1..200.
  Future<List<ChatMessage>> conversation(
    int partnerId, {
    int limit = 50,
    int? beforeId,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/messages/conversation/$partnerId',
        queryParameters: {
          'limit': limit,
          'beforeId': ?beforeId,
        },
      );
      return res.data!
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /messages/send/{partnerId} — persists the message and notifies the
  /// partner via SSE/push. Partner-only (403 otherwise); content is trimmed
  /// and capped at 1000 characters. The response is a confirmation string
  /// only, so callers refresh the conversation to see the stored message.
  Future<void> send({
    required int partnerId,
    required String content,
  }) async {
    try {
      await _dio.post<void>(
        '/messages/send/$partnerId',
        data: {'content': content},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
