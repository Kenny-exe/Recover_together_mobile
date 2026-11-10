import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/api_client.dart';
import 'package:app/api/dto.dart';
import 'package:app/api/notification_api.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/realtime/realtime_service.dart';
import 'package:app/screens/notifications_screen.dart';

import 'support/mock_adapter.dart';

void main() {
  testWidgets('inbox lists notifications, marks read, and dedupes SSE',
      (tester) async {
    final items = <Map<String, dynamic>>[
      const {
        'id': 9,
        'type': 'NEW_MESSAGE',
        'message': 'Sam sent you a message',
        'read': false,
        'createdAt': '2026-11-10T21:34:00',
      },
      const {
        'id': 4,
        'type': 'ACHIEVEMENT_UNLOCKED',
        'message': '3 day streak!',
        'read': true,
        'createdAt': '2026-11-09T10:00:00',
      },
    ];
    final markedRead = <int>[];

    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' && path.endsWith('/notifications')) {
        return jsonBody(items, 200);
      }
      if (options.method == 'GET' &&
          path.endsWith('/notifications/unread-count')) {
        return jsonBody({'unreadCount': 1}, 200);
      }
      if (options.method == 'PUT' && path.endsWith('/notifications/read/9')) {
        markedRead.add(9);
        items[0] = {
          ...items[0],
          'read': true,
        };
        return jsonBody({'message': 'Notification marked as read'}, 200);
      }
      if (options.method == 'PUT' &&
          path.endsWith('/notifications/read-all')) {
        for (var i = 0; i < items.length; i++) {
          items[i] = {...items[i], 'read': true};
        }
        return jsonBody({'message': 'All notifications marked as read'}, 200);
      }
      return jsonBody(const {'timestamp': '', 'status': 404, 'message': 'nf'},
          404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = AuthController(
      client: ApiClient(storage: InMemoryTokenStorage(), baseUrl: 'http://test'),
      storage: InMemoryTokenStorage(),
    );
    final realtime = RealtimeService(
      storage: InMemoryTokenStorage(),
      baseUrl: 'http://test',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          Provider<NotificationApi>.value(value: NotificationApi(dio)),
          Provider<RealtimeService>.value(value: realtime),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Items and unread counter render.
    expect(find.text('Sam sent you a message'), findsOneWidget);
    expect(find.text('3 day streak!'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);
    expect(find.byKey(const ValueKey('dot-9')), findsOneWidget,
        reason: 'unread dot on the unread item');
    expect(find.byKey(const ValueKey('dot-4')), findsNothing);

    // Tapping the unread item marks it read.
    await tester.tap(find.text('Sam sent you a message'));
    await tester.pumpAndSettle();
    expect(markedRead, [9]);
    expect(find.text('All caught up'), findsOneWidget);
    expect(find.byKey(const ValueKey('dot-9')), findsNothing);

    // A live SSE notification prepends itself (unread went 1 → 0 on the
    // tap above, so this unread arrival brings the counter back to 1).
    realtime.onNotification?.call(AppNotification(
      id: 12,
      type: 'MISSED_CHECKIN',
      message: 'Sam has not checked in today',
      read: false,
      createdAt: '2026-11-10T22:00:00',
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sam has not checked in today'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);

    // The same id arriving again (push + SSE) does not duplicate.
    realtime.onNotification?.call(AppNotification(
      id: 12,
      type: 'MISSED_CHECKIN',
      message: 'Sam has not checked in today',
      read: false,
      createdAt: '2026-11-10T22:00:00',
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sam has not checked in today'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);

    // Mark all read clears every dot.
    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();
    expect(find.text('All caught up'), findsOneWidget);
    expect(find.byKey(const ValueKey('dot-9')), findsNothing,
        reason: 'no unread dots remain');
    expect(find.byKey(const ValueKey('dot-12')), findsNothing,
        reason: 'the SSE-arrived item was marked read too');
  });

  testWidgets('inbox shows the empty state', (tester) async {
    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (path.endsWith('/notifications')) {
        return jsonBody(const [], 200);
      }
      if (path.endsWith('/notifications/unread-count')) {
        return jsonBody({'unreadCount': 0}, 200);
      }
      return jsonBody(const {'timestamp': '', 'status': 404, 'message': 'nf'},
          404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = AuthController(
      client: ApiClient(storage: InMemoryTokenStorage(), baseUrl: 'http://test'),
      storage: InMemoryTokenStorage(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          Provider<NotificationApi>.value(value: NotificationApi(dio)),
          Provider<RealtimeService>.value(
            value: RealtimeService(
              storage: InMemoryTokenStorage(),
              baseUrl: 'http://test',
            ),
          ),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(find.text('All caught up'), findsOneWidget);
  });
}
