import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/api_client.dart';
import 'package:app/api/checkin_api.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/screens/home_screen.dart';

import 'support/mock_adapter.dart';

void main() {
  testWidgets('home shows dashboard stats and posts a check-in', (tester) async {
    var checkedIn = false;
    var submittedNote = '';
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final adapter = MockAdapter((options) async {
      if (options.method == 'GET' && options.path.endsWith('/dashboard')) {
        return jsonBody(const {
          'currentStreak': 3,
          'bestStreak': 9,
          'totalCheckIns': 10,
          'successCount': 8,
          'relapseCount': 2,
          'successRate': 80.0,
          'unreadMessages': 1,
          'achievementCount': 2,
        }, 200);
      }
      if (options.method == 'GET' && options.path.endsWith('/checkin/latest')) {
        if (!checkedIn) {
          // The backend answers 404 when the user has never checked in.
          return jsonBody(const {
            'timestamp': '',
            'status': 404,
            'message': 'No check-ins found',
          }, 404);
        }
        return jsonBody({
          'id': 1,
          'date': today,
          'status': 'SUCCESS',
          'note': submittedNote,
          'createdAt': '${today}T08:00:00',
        }, 200);
      }
      if (options.method == 'POST' && options.path.endsWith('/checkin')) {
        checkedIn = true;
        final body = options.data as Map<String, dynamic>;
        submittedNote = (body['note'] as String?) ?? '';
        return jsonBody({'message': 'Check-in submitted successfully'}, 200);
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
          Provider<CheckInApi>.value(value: CheckInApi(dio)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Dashboard renders.
    expect(find.text('Check in for today'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'current streak');
    expect(find.text('9'), findsOneWidget, reason: 'best streak');
    expect(find.text('80%'), findsOneWidget);
    expect(find.textContaining('No partner connected'), findsOneWidget);

    // Open the check-in sheet and submit.
    await tester.tap(find.text('Check in for today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stayed clean'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'felt good');
    await tester.tap(find.text('Submit check-in'));
    await tester.pumpAndSettle();

    // Sheet closed, home refreshed into the checked-in state.
    expect(find.text('Check in for today'), findsNothing);
    expect(find.text('Checked in today'), findsOneWidget);
    expect(find.text('Stayed clean'), findsOneWidget);
    expect(find.text('felt good'), findsOneWidget);

    // Exactly one POST with the contract wire fields.
    final posts =
        adapter.requests.where((r) => r.method == 'POST').toList();
    expect(posts, hasLength(1));
    final body = posts.single.data as Map<String, dynamic>;
    expect(body['status'], 'SUCCESS');
    expect(body['note'], 'felt good');
  });

  testWidgets('home surfaces API errors with a retry button', (tester) async {
    final adapter = MockAdapter((options) async => jsonBody(const {
          'timestamp': '',
          'status': 500,
          'message': 'Internal error',
        }, 500));

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
          Provider<CheckInApi>.value(value: CheckInApi(dio)),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Internal error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
