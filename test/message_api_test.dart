import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/dto.dart';
import 'package:app/api/message_api.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late MessageApi api;

  setUp(() {
    adapter = MockAdapter((options) async {
      return jsonBody(const {
        'timestamp': '',
        'status': 404,
        'message': 'Resource not found',
      }, 404);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = adapter;
    api = MessageApi(dio);
  });

  test('conversation parses the chronological page and passes the cursor',
      () async {
    adapter.handler = (options) async => jsonBody(const [
          {
            'id': 1,
            'senderName': 'Sam',
            'content': 'hey',
            'createdAt': '2026-11-10T09:00:00',
          },
          {
            'id': 2,
            'senderName': 'Kenny',
            'content': 'hi there',
            'createdAt': '2026-11-10T09:01:00',
          },
        ], 200);

    final messages = await api.conversation(5, limit: 50, beforeId: 10);

    expect(messages, hasLength(2));
    expect(messages[0].id, 1);
    expect(messages[0].content, 'hey');
    expect(messages[1].senderName, 'Kenny');

    final request = adapter.requests.single;
    expect(request.path.endsWith('/messages/conversation/5'), isTrue);
    expect(request.uri, contains('limit=50'));
    expect(request.uri, contains('beforeId=10'));
  });

  test('conversation omits beforeId when not paging', () async {
    adapter.handler = (options) async => jsonBody(const [], 200);

    final messages = await api.conversation(5);

    expect(messages, isEmpty);
    expect(adapter.requests.single.uri.contains('beforeId'), isFalse);
  });

  test('timeLabel slices HH:mm out of the server timestamp', () {
    final m = ChatMessage(
      id: 1,
      content: 'x',
      createdAt: '2026-11-10T21:34:00',
    );
    expect(m.timeLabel, '21:34');

    expect(ChatMessage(content: 'x').timeLabel, isEmpty);
  });

  test('send posts the content to the partner path', () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Message sent successfully'}, 200);

    await api.send(partnerId: 5, content: 'hello partner');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path.endsWith('/messages/send/5'), isTrue);
    final body = request.data as Map<String, dynamic>;
    expect(body['content'], 'hello partner');
  });

  test('non-partner sends surface the 403 envelope message', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 403,
          'message': 'Access denied',
        }, 403);

    ApiException? ex;
    try {
      await api.send(partnerId: 5, content: 'hello');
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.status, 403);
    expect(ex.message, 'Access denied');
  });
}
