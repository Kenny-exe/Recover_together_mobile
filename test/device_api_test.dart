import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/device_api.dart';
import 'package:app/api/dto.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late DeviceApi api;

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
    api = DeviceApi(dio);
  });

  test('register posts the contract fields and parses the response',
      () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 3,
          'platform': 'ANDROID',
          'deviceName': 'Pixel 8',
          'tokenPreview': 'abc…xyz',
          'active': true,
          'createdAt': '2026-11-10T21:00:00',
        }, 200);

    final device = await api.register(
      platform: DevicePlatform.android,
      token: 'fcm-token-123',
      deviceName: 'Pixel 8',
    );

    expect(device.id, 3);
    expect(device.platform, DevicePlatform.android);
    expect(device.tokenPreview, 'abc…xyz',
        reason: 'the raw token never comes back');
    expect(device.active, isTrue);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path.endsWith('/users/me/devices'), isTrue);
    final body = request.data as Map<String, dynamic>;
    expect(body['platform'], 'ANDROID');
    expect(body['token'], 'fcm-token-123');
    expect(body['deviceName'], 'Pixel 8');
  });

  test('register omits deviceName when not provided', () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 4,
          'platform': 'IOS',
          'tokenPreview': 'qrs…tuv',
        }, 200);

    await api.register(platform: DevicePlatform.ios, token: 'tok');

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body.containsKey('deviceName'), isFalse);
  });

  test('list parses the masked previews', () async {
    adapter.handler = (options) async => jsonBody(const [
          {
            'id': 3,
            'platform': 'ANDROID',
            'deviceName': 'Pixel 8',
            'tokenPreview': 'abc…xyz',
            'active': true,
          },
          {
            'id': 4,
            'platform': 'IOS',
            'deviceName': 'iPhone',
            'tokenPreview': 'qrs…tuv',
            'active': false,
          },
        ], 200);

    final devices = await api.list();

    expect(devices, hasLength(2));
    expect(devices[0].platform, DevicePlatform.android);
    expect(devices[0].active, isTrue);
    expect(devices[1].platform, DevicePlatform.ios);
    expect(devices[1].active, isFalse);
    expect(devices[1].tokenPreview, 'qrs…tuv');
  });

  test('remove hits DELETE /users/me/devices/{id}', () async {
    adapter.handler = (options) async =>
        jsonBody({'message': 'Device removed'}, 200);

    await api.remove(3);

    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path.endsWith('/users/me/devices/3'), isTrue);
  });

  test('registration errors surface the envelope message', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'Token too long',
        }, 400);

    ApiException? ex;
    try {
      await api.register(platform: DevicePlatform.android, token: 'x' * 4097);
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.message, 'Token too long');
  });
}
