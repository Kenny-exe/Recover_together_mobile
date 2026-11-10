import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/partner_api.dart';
import 'package:app/screens/partner_screen.dart';

import 'support/mock_adapter.dart';

void main() {
  testWidgets('partner screen searches by email and sends a request',
      (tester) async {
    var requestSent = false;
    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' && path.endsWith('/partner/current')) {
        return jsonBody(const {
          'timestamp': '',
          'status': 404,
          'message': 'No partner found',
        }, 404);
      }
      if (options.method == 'GET' && path.endsWith('/partner/requests')) {
        return jsonBody(const [], 200);
      }
      if (options.method == 'GET' && path.endsWith('/partner/sent')) {
        if (!requestSent) return jsonBody(const [], 200);
        return jsonBody(const [
          {'requestId': 9, 'receiverName': 'Sam'},
        ], 200);
      }
      if (options.method == 'GET' && path.endsWith('/users/search')) {
        return jsonBody(const {
          'id': 5,
          'name': 'Sam',
          'email': 'sam@example.com',
          'timezone': 'UTC',
        }, 200);
      }
      if (options.method == 'POST' && path.endsWith('/partner/request/5')) {
        requestSent = true;
        return jsonBody({'message': 'Partner request sent'}, 200);
      }
      return jsonBody(const {'timestamp': '', 'status': 404, 'message': 'nf'},
          404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      Provider<PartnerApi>.value(
        value: PartnerApi(dio),
        child: const MaterialApp(home: PartnerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No-partner state shows the search card.
    expect(find.text('Connect with a partner'), findsOneWidget);

    // Search finds the user by exact email.
    await tester.enterText(find.byType(TextFormField), 'sam@example.com');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('sam@example.com'), findsNWidgets(2),
        reason: 'typed in the search field + shown as the result subtitle');

    // Sending the request refreshes into the pending state.
    await tester.tap(find.text('Send partner request'));
    await tester.pumpAndSettle();
    expect(find.text('Send partner request'), findsNothing,
        reason: 'found panel clears after sending');
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);

    final search = adapter.requests
        .where((r) => r.path.endsWith('/users/search'))
        .single;
    expect(search.uri, contains('email=sam%40example.com'));
    final post = adapter.requests
        .where((r) => r.method == 'POST')
        .single;
    expect(post.path.endsWith('/partner/request/5'), isTrue);
  });

  testWidgets('partner screen shows incoming requests with actions',
      (tester) async {
    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' && path.endsWith('/partner/current')) {
        return jsonBody(const {
          'timestamp': '',
          'status': 404,
          'message': 'No partner found',
        }, 404);
      }
      if (options.method == 'GET' && path.endsWith('/partner/requests')) {
        return jsonBody(const [
          {
            'id': 11,
            'senderName': 'Sam',
            'receiverName': 'Kenny',
            'status': 'PENDING',
            'createdAt': '2026-11-10T09:00:00',
          },
        ], 200);
      }
      if (options.method == 'GET' && path.endsWith('/partner/sent')) {
        return jsonBody(const [], 200);
      }
      if (options.method == 'POST' && path.endsWith('/partner/accept/11')) {
        return jsonBody({'message': 'Partner request accepted'}, 200);
      }
      return jsonBody(const {'timestamp': '', 'status': 404, 'message': 'nf'},
          404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      Provider<PartnerApi>.value(
        value: PartnerApi(dio),
        child: const MaterialApp(home: PartnerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Incoming requests'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    final post = adapter.requests
        .where((r) => r.method == 'POST')
        .single;
    expect(post.path.endsWith('/partner/accept/11'), isTrue);
  });
}
