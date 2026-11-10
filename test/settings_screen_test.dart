import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/api_client.dart';
import 'package:app/api/dto.dart';
import 'package:app/api/user_api.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/screens/login_screen.dart';
import 'package:app/screens/settings_screen.dart';

import 'support/mock_adapter.dart';

AuthController _auth() {
  final auth = AuthController(
    client: ApiClient(storage: InMemoryTokenStorage(), baseUrl: 'http://test'),
    storage: InMemoryTokenStorage(),
  );
  auth.user = UserResponse(
    id: 7,
    name: 'Kenny',
    email: 'kenny@example.com',
    timezone: 'UTC',
  );
  return auth;
}

Future<void> _pump(WidgetTester tester, AuthController auth, UserApi api) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider<UserApi>.value(value: api),
      ],
      // Mirrors the production AuthGate: once the session drops (password
      // change, account deletion) the login screen replaces settings, which
      // also unmounts any in-flight spinners.
      child: MaterialApp(
        home: Consumer<AuthController>(
          builder: (_, value, _) => value.status == AuthStatus.anonymous
              ? const LoginScreen()
              : const SettingsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saves the profile and updates the cached user', (tester) async {
    final adapter = MockAdapter((options) async {
      if (options.method == 'PUT' && options.path.endsWith('/users/me')) {
        final body = options.data as Map<String, dynamic>;
        return jsonBody({
          'id': 7,
          'name': body['name'],
          'email': body['email'],
          'timezone': body['timezone'] ?? 'UTC',
          'createdAt': '2026-11-10T10:00:00',
        }, 200);
      }
      return jsonBody(const {'timestamp': '', 'status': 404, 'message': 'nf'},
          404);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = _auth();

    await _pump(tester, auth, UserApi(dio));

    // Prefilled from the cached user.
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Kenneth');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();

    final put = adapter.requests.where((r) => r.method == 'PUT').single;
    final body = put.data as Map<String, dynamic>;
    expect(body['name'], 'Kenneth');
    expect(body['email'], 'kenny@example.com');
    expect(body['timezone'], 'UTC');
    expect(auth.user!.name, 'Kenneth',
        reason: 'the cached profile updates immediately');
    expect(find.text('Profile saved'), findsOneWidget);
  });

  testWidgets('changing the password drops the session for re-login',
      (tester) async {
    final adapter = MockAdapter((options) async {
      if (options.method == 'POST' &&
          options.path.endsWith('/users/change-password')) {
        return jsonBody({'message': 'Password changed successfully'}, 200);
      }
      // The post-change logout attempts server-side revocation with the now
      // invalid token — answered with 401 like the real backend would.
      return jsonBody(const {
        'timestamp': '',
        'status': 401,
        'message': 'Invalid or expired token',
      }, 401);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = _auth();

    await _pump(tester, auth, UserApi(dio));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'), 'OldPass1!');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), 'NewPass2!');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'), 'NewPass2!');
    final changeButton = find.widgetWithText(FilledButton, 'Change password');
    await tester.ensureVisible(changeButton);
    await tester.pumpAndSettle();
    await tester.tap(changeButton);
    await tester.pumpAndSettle();

    final post = adapter.requests
        .where((r) => r.method == 'POST' && r.path.contains('change-password'))
        .single;
    final body = post.data as Map<String, dynamic>;
    expect(body['currentPassword'], 'OldPass1!');
    expect(body['newPassword'], 'NewPass2!');
    expect(auth.status, AuthStatus.anonymous,
        reason: 'all tokens were invalidated; the user must log in again');
    expect(find.text('RecoverTogether'), findsOneWidget,
        reason: 'the gate swapped to the login screen');
  });

  testWidgets('mismatched password confirmation never sends a request',
      (tester) async {
    final adapter = MockAdapter((options) async {
      return jsonBody(const {'timestamp': '', 'status': 404, 'message': 'nf'},
          404);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = _auth();

    await _pump(tester, auth, UserApi(dio));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'), 'OldPass1!');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), 'NewPass2!');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'), 'Other3!');
    final changeButton = find.widgetWithText(FilledButton, 'Change password');
    await tester.ensureVisible(changeButton);
    await tester.pumpAndSettle();
    await tester.tap(changeButton);
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(adapter.requests, isEmpty, reason: 'no request before validation');
  });

  testWidgets('account deletion requires the password and drops the session',
      (tester) async {
    final adapter = MockAdapter((options) async {
      if (options.method == 'DELETE' && options.path.endsWith('/users/me')) {
        final body = options.data as Map<String, dynamic>;
        if (body['password'] == 'Secret1!') {
          return jsonBody({'message': 'Account deleted'}, 200);
        }
        return jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'Incorrect password',
        }, 400);
      }
      return jsonBody(const {
        'timestamp': '',
        'status': 401,
        'message': 'Invalid or expired token',
      }, 401);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = _auth();

    await _pump(tester, auth, UserApi(dio));

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete account?'), findsOneWidget,
        reason: 'confirmation dialog is open');

    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Secret1!');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    final delete = adapter.requests.where((r) => r.method == 'DELETE').single;
    expect(delete.path.endsWith('/users/me'), isTrue);
    expect((delete.data as Map<String, dynamic>)['password'], 'Secret1!');
    expect(auth.status, AuthStatus.anonymous);
    expect(find.text('RecoverTogether'), findsOneWidget,
        reason: 'the gate swapped to the login screen');
  });

  testWidgets('wrong deletion password keeps the dialog open with the error',
      (tester) async {
    final adapter = MockAdapter((options) async {
      if (options.method == 'DELETE' && options.path.endsWith('/users/me')) {
        return jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'Incorrect password',
        }, 400);
      }
      return jsonBody(const {
        'timestamp': '',
        'status': 401,
        'message': 'Invalid or expired token',
      }, 401);
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final auth = _auth();

    await _pump(tester, auth, UserApi(dio));

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'wrong');
    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect password'), findsOneWidget);
    expect(find.text('Delete account?'), findsOneWidget,
        reason: 'the dialog stays open');
    expect(auth.status, isNot(AuthStatus.anonymous),
        reason: 'a failed deletion must not end the session');
  });
}
