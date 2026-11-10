import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/notification_api.dart';
import 'package:app/screens/notification_prefs_screen.dart';

import 'support/mock_adapter.dart';

/// The prefs list is a lazy ListView — off-screen tiles are not built, so
/// scroll down to the tile before reading or tapping it. Returns the tile
/// widget once visible.
Future<SwitchListTile> scrollToTile(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SwitchListTile, label);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return tester.widget<SwitchListTile>(finder);
}

void main() {
  testWidgets('loads preferences, reflects state, and saves patch-style',
      (tester) async {
    Map<String, dynamic>? putBody;

    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' &&
          path.endsWith('/notifications/preferences')) {
        return jsonBody(const {
          'pushNotificationsEnabled': true,
          'quietHoursEnabled': false,
          'typePreferences': {'NEW_MESSAGE': false, 'SOS_ALERT': true},
        }, 200);
      }
      if (options.method == 'PUT' &&
          path.endsWith('/notifications/preferences')) {
        putBody = options.data as Map<String, dynamic>;
        return jsonBody(const {
          'pushNotificationsEnabled': false,
          'quietHoursEnabled': false,
          'typePreferences': {'NEW_MESSAGE': false, 'SOS_ALERT': true},
        }, 200);
      }
      return jsonBody(
          const {'timestamp': '', 'status': 404, 'message': 'nf'}, 404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      Provider<NotificationApi>.value(
        value: NotificationApi(dio),
        child: const MaterialApp(home: NotificationPrefsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Loaded state: push on. Tapping the tile toggles it off.
    var pushTile = await scrollToTile(tester, 'Push notifications');
    expect(pushTile.value, isTrue);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Push notifications'));
    await tester.pumpAndSettle();
    pushTile = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Push notifications'));
    expect(pushTile.value, isFalse);

    // Per-type state from the server.
    final newMessageTile = await scrollToTile(tester, 'New messages');
    expect(newMessageTile.value, isFalse);

    // SOS alerts are always on and cannot be toggled.
    final sosTile = await scrollToTile(tester, 'SOS alerts');
    expect(sosTile.value, isTrue);
    expect(sosTile.onChanged, isNull, reason: 'SOS alerts cannot be disabled');

    // The toggle made the state dirty — save is enabled.
    final saveFinder = find.widgetWithText(FilledButton, 'Save preferences');
    await tester.scrollUntilVisible(
      saveFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(saveFinder).onPressed,
      isNotNull,
      reason: 'a toggle marks the state dirty and enables saving',
    );
    await tester.tap(saveFinder);
    await tester.pumpAndSettle();

    expect(putBody, isNotNull);
    expect(putBody!['pushNotificationsEnabled'], isFalse);
    expect(putBody!['quietHoursEnabled'], isFalse,
        reason: 'the untouched switch is still sent as part of the state');
    expect(putBody!['typePreferences'], {
      'NEW_MESSAGE': false,
      'SOS_ALERT': true,
    });
    expect(find.text('Preferences saved'), findsOneWidget);
  });

  testWidgets('enabling quiet hours without both times blocks the save',
      (tester) async {
    Map<String, dynamic>? putBody;

    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' &&
          path.endsWith('/notifications/preferences')) {
        return jsonBody(const {
          'pushNotificationsEnabled': true,
          'quietHoursEnabled': false,
        }, 200);
      }
      if (options.method == 'PUT' &&
          path.endsWith('/notifications/preferences')) {
        putBody = options.data as Map<String, dynamic>;
        return jsonBody(const {
          'pushNotificationsEnabled': true,
          'quietHoursEnabled': true,
          'quietHoursStart': '22:00',
          'quietHoursEnd': '07:00',
        }, 200);
      }
      return jsonBody(
          const {'timestamp': '', 'status': 404, 'message': 'nf'}, 404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      Provider<NotificationApi>.value(
        value: NotificationApi(dio),
        child: const MaterialApp(home: NotificationPrefsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Enabling quiet hours reveals the time pickers.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Quiet hours'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    // No times set — the save must be blocked client-side.
    final saveFinder = find.widgetWithText(FilledButton, 'Save preferences');
    await tester.scrollUntilVisible(
      saveFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(saveFinder);
    await tester.pumpAndSettle();

    expect(find.text('Set both quiet-hours times first'), findsOneWidget);
    expect(putBody, isNull, reason: 'no request before validation passes');
  });
}
