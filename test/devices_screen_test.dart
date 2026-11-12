import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/api/device_api.dart';
import 'package:app/screens/devices_screen.dart';

import 'support/mock_adapter.dart';

void main() {
  testWidgets('lists devices with masked previews and removes one',
      (tester) async {
    final devices = <Map<String, dynamic>>[
      const {
        'id': 3,
        'platform': 'ANDROID',
        'deviceName': 'Pixel 8',
        'tokenPreview': 'abc…xyz',
        'active': true,
        'createdAt': '2026-11-10T21:00:00',
      },
      const {
        'id': 4,
        'platform': 'IOS',
        'deviceName': '',
        'tokenPreview': 'qrs…tuv',
        'active': false,
      },
    ];
    final removed = <int>[];

    final adapter = MockAdapter((options) async {
      final path = options.path;
      if (options.method == 'GET' && path.endsWith('/users/me/devices')) {
        return jsonBody(devices, 200);
      }
      if (options.method == 'DELETE' && path.endsWith('/users/me/devices/3')) {
        removed.add(3);
        devices.removeWhere((d) => d['id'] == 3);
        return jsonBody({'message': 'Device removed'}, 200);
      }
      return jsonBody(
          const {'timestamp': '', 'status': 404, 'message': 'nf'}, 404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      Provider<DeviceApi>.value(
        value: DeviceApi(dio),
        child: const MaterialApp(home: DevicesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Both devices render with masked previews (never a raw token).
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('abc…xyz'), findsOneWidget);
    expect(find.text('Unnamed device'), findsOneWidget,
        reason: 'an omitted deviceName falls back to a label');
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('fcm-token-123'), findsNothing,
        reason: 'raw tokens are never sent back by the contract');

    // Removing the first device calls the contract path and drops the row.
    final removeButton = find.byTooltip('Remove device').first;
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(removed, [3]);
    expect(find.text('Pixel 8'), findsNothing);
    expect(find.text('Unnamed device'), findsOneWidget);
  });

  testWidgets('shows the empty state when no device is registered',
      (tester) async {
    final adapter = MockAdapter((options) async {
      if (options.method == 'GET' && options.path.endsWith('/users/me/devices')) {
        return jsonBody(const [], 200);
      }
      return jsonBody(
          const {'timestamp': '', 'status': 404, 'message': 'nf'}, 404);
    });

    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(
      Provider<DeviceApi>.value(
        value: DeviceApi(dio),
        child: const MaterialApp(home: DevicesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No devices registered.'), findsOneWidget);
    expect(find.textContaining('push configured'), findsOneWidget);
  });
}
