import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/dto.dart';
import 'package:app/api/notification_api.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late NotificationApi api;

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
    api = NotificationApi(dio);
  });

  test('list parses the newest-first page and passes the cursor', () async {
    adapter.handler = (options) async => jsonBody(const [
          {
            'id': 9,
            'type': 'NEW_MESSAGE',
            'message': 'Sam sent you a message',
            'read': false,
            'createdAt': '2026-11-10T21:34:00',
          },
          {
            'id': 4,
            'type': 'ACHIEVEMENT_UNLOCKED',
            'message': '3 day streak!',
            'read': true,
            'createdAt': '2026-11-09T10:00:00',
          },
        ], 200);

    final items = await api.list(limit: 20, beforeId: 10);

    expect(items, hasLength(2));
    expect(items[0].id, 9);
    expect(items[0].type, 'NEW_MESSAGE');
    expect(items[0].read, isFalse);
    expect(items[1].message, '3 day streak!');

    final request = adapter.requests.single;
    expect(request.uri, contains('limit=20'));
    expect(request.uri, contains('beforeId=10'));
  });

  test('timestampLabel slices date + time', () {
    expect(
      AppNotification(
        id: 1,
        message: 'x',
        createdAt: '2026-11-10T21:34:00',
      ).timestampLabel,
      '2026-11-10 21:34',
    );
    expect(AppNotification(message: 'x').timestampLabel, isEmpty);
  });

  test('unreadCount parses the count', () async {
    adapter.handler = (options) async => jsonBody({'unreadCount': 3}, 200);
    expect(await api.unreadCount(), 3);
  });

  test('markRead, markAllRead, remove and removeAll hit their paths',
      () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Notifications updated'}, 200);

    await api.markRead(9);
    await api.markAllRead();
    await api.remove(9);
    await api.removeAll();

    final calls =
        adapter.requests.map((r) => '${r.method} ${r.path}').toList();
    expect(
      calls,
      containsAllInOrder([
        endsWith('/notifications/read/9'),
        endsWith('/notifications/read-all'),
        endsWith('/notifications/9'),
        endsWith('/notifications/all'),
      ]),
    );
    expect(
      calls.where((c) => c.startsWith('PUT ')).length,
      2,
      reason: 'mark actions are PUTs',
    );
    expect(
      calls.where((c) => c.startsWith('DELETE ')).length,
      2,
      reason: 'removals are DELETEs',
    );
  });

  test('preferences parses the full shape', () async {
    adapter.handler = (options) async => jsonBody(const {
          'pushNotificationsEnabled': true,
          'quietHoursEnabled': true,
          'quietHoursStart': '22:00',
          'quietHoursEnd': '07:00',
          'typePreferences': {'NEW_MESSAGE': false, 'SOS_ALERT': true},
        }, 200);

    final prefs = await api.preferences();

    expect(prefs.pushNotificationsEnabled, isTrue);
    expect(prefs.quietHoursEnabled, isTrue);
    expect(prefs.quietHoursStart, '22:00');
    expect(prefs.quietHoursEnd, '07:00');
    expect(prefs.typePreferences!['NEW_MESSAGE'], isFalse);
    expect(prefs.typePreferences!['SOS_ALERT'], isTrue);
  });

  test('updatePreferences sends only non-null fields (patch style)',
      () async {
    adapter.handler = (options) async => jsonBody(const {
          'pushNotificationsEnabled': false,
          'quietHoursEnabled': false,
        }, 200);

    final saved = await api.updatePreferences(
      NotificationPreferences(pushNotificationsEnabled: false),
    );

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body.keys, ['pushNotificationsEnabled'],
        reason: 'null fields are omitted; server keeps their values');
    expect(saved.pushNotificationsEnabled, isFalse);
  });

  test('empty patch sends an empty object', () async {
    adapter.handler = (options) async => jsonBody(const {}, 200);
    await api.updatePreferences(NotificationPreferences());
    expect(adapter.requests.single.data as Map<String, dynamic>, isEmpty);
  });

  test('invalid quiet hours surface the 400 envelope message', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'Quiet-hours start and end cannot be the same time',
        }, 400);

    ApiException? ex;
    try {
      await api.updatePreferences(NotificationPreferences(
        quietHoursEnabled: true,
        quietHoursStart: '22:00',
        quietHoursEnd: '22:00',
      ));
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.message, 'Quiet-hours start and end cannot be the same time');
  });
}
