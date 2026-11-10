import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/api_client.dart';
import 'package:app/api/dto.dart';
import 'package:app/api/message_api.dart';
import 'package:app/api/partner_api.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/realtime/realtime_service.dart';
import 'package:app/screens/chat_screen.dart';

import 'support/mock_adapter.dart';

void main() {
  testWidgets('chat loads the thread, sends, and appends live SSE messages',
      (tester) async {
    final conversation = <Map<String, dynamic>>[
      const {
        'id': 1,
        'senderName': 'Sam',
        'content': 'hey, how are you holding up?',
        'createdAt': '2026-11-10T09:00:00',
      },
      const {
        'id': 2,
        'senderName': 'Kenny',
        'content': 'day three clean!',
        'createdAt': '2026-11-10T09:01:00',
      },
    ];
    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' && path.endsWith('/partner/current')) {
        return jsonBody(const {
          'id': 5,
          'name': 'Sam',
          'email': 'sam@example.com',
        }, 200);
      }
      if (options.method == 'GET' && path.contains('/messages/conversation/5')) {
        return jsonBody(conversation, 200);
      }
      if (options.method == 'POST' && path.endsWith('/messages/send/5')) {
        final body = options.data as Map<String, dynamic>;
        conversation.add({
          'id': 3,
          'senderName': 'Kenny',
          'content': body['content'],
          'createdAt': '2026-11-10T09:02:00',
        });
        return jsonBody({'message': 'Message sent successfully'}, 200);
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
    // ChatScreen aligns bubbles by comparing the sender name to this user.
    auth.user = UserResponse(
      id: 1,
      name: 'Kenny',
      email: 'kenny@example.com',
      timezone: 'UTC',
    );
    final realtime = RealtimeService(
      storage: InMemoryTokenStorage(),
      baseUrl: 'http://test',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          Provider<PartnerApi>.value(value: PartnerApi(dio)),
          Provider<MessageApi>.value(value: MessageApi(dio)),
          Provider<RealtimeService>.value(value: realtime),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Thread renders, titled by the partner's name.
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('hey, how are you holding up?'), findsOneWidget);
    expect(find.text('day three clean!'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget, reason: 'HH:mm label');
    expect(find.text('09:01'), findsOneWidget);

    // Send a message: POST then re-sync from the server.
    await tester.enterText(find.byType(TextField), 'thanks Sam');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('thanks Sam'), findsOneWidget);
    final post = adapter.requests.where((r) => r.method == 'POST').single;
    expect(post.path.endsWith('/messages/send/5'), isTrue);
    expect((post.data as Map<String, dynamic>)['content'], 'thanks Sam');

    // A live SSE `message` event appends to the open thread.
    realtime.onMessage?.call(ChatMessage(
      id: 4,
      senderName: 'Sam',
      content: 'proud of you',
      createdAt: '2026-11-10T09:03:00',
    ));
    await tester.pumpAndSettle();
    expect(find.text('proud of you'), findsOneWidget);

    // Deduping: the same id arriving twice must not duplicate the bubble.
    realtime.onMessage?.call(ChatMessage(
      id: 4,
      senderName: 'Sam',
      content: 'proud of you',
      createdAt: '2026-11-10T09:03:00',
    ));
    await tester.pumpAndSettle();
    expect(find.text('proud of you'), findsOneWidget);
  });

  testWidgets('chat shows the connect-first hint without a partner',
      (tester) async {
    final adapter = MockAdapter((options) async {
      if (options.path.endsWith('/partner/current')) {
        return jsonBody(const {
          'timestamp': '',
          'status': 404,
          'message': 'No partner found',
        }, 404);
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
          Provider<PartnerApi>.value(value: PartnerApi(dio)),
          Provider<MessageApi>.value(value: MessageApi(dio)),
          Provider<RealtimeService>.value(
            value: RealtimeService(
              storage: InMemoryTokenStorage(),
              baseUrl: 'http://test',
            ),
          ),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Connect with a partner first'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
