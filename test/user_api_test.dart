import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/dto.dart';
import 'package:app/api/user_api.dart';

import 'support/mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late UserApi api;

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
    api = UserApi(dio);
  });

  test('updateProfile posts the contract fields and parses UserResponse',
      () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 7,
          'name': 'Kenneth',
          'email': 'kenny@example.com',
          'timezone': 'Europe/Berlin',
          'createdAt': '2026-11-10T10:00:00',
        }, 200);

    final user = await api.updateProfile(
      name: 'Kenneth',
      email: 'kenny@example.com',
      timezone: 'Europe/Berlin',
    );

    expect(user.name, 'Kenneth');
    expect(user.timezone, 'Europe/Berlin');

    final request = adapter.requests.single;
    expect(request.method, 'PUT');
    expect(request.path.endsWith('/users/me'), isTrue);
    final body = request.data as Map<String, dynamic>;
    expect(body['name'], 'Kenneth');
    expect(body['email'], 'kenny@example.com');
    expect(body['timezone'], 'Europe/Berlin');
  });

  test('updateProfile omits an empty timezone (keeps the stored one)',
      () async {
    adapter.handler = (options) async => jsonBody(const {
          'id': 7,
          'name': 'Kenny',
          'email': 'kenny@example.com',
          'timezone': 'UTC',
        }, 200);

    await api.updateProfile(name: 'Kenny', email: 'kenny@example.com');

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body.containsKey('timezone'), isFalse);
  });

  test('invalid timezone surfaces the 400 envelope message', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'Invalid timezone',
        }, 400);

    ApiException? ex;
    try {
      await api.updateProfile(
        name: 'Kenny',
        email: 'k@example.com',
        timezone: 'Mars/Olympus',
      );
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.message, 'Invalid timezone');
  });

  test('changePassword posts both fields to /users/change-password', () async {
    adapter.handler = (options) async => jsonBody({
          'message': 'Password changed successfully',
        }, 200);

    await api.changePassword(
      currentPassword: 'OldPass1!',
      newPassword: 'NewPass2!',
    );

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path.endsWith('/users/change-password'), isTrue);
    final body = request.data as Map<String, dynamic>;
    expect(body['currentPassword'], 'OldPass1!');
    expect(body['newPassword'], 'NewPass2!');
  });

  test('deleteAccount sends DELETE /users/me with the password body',
      () async {
    adapter.handler = (options) async => jsonBody({
          'message': 'Account deleted',
        }, 200);

    await api.deleteAccount(password: 'Secret1!');

    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path.endsWith('/users/me'), isTrue);
    final body = request.data as Map<String, dynamic>;
    expect(body['password'], 'Secret1!');
  });

  test('wrong deletion password surfaces the 400 envelope message', () async {
    adapter.handler = (options) async => jsonBody(const {
          'timestamp': '',
          'status': 400,
          'message': 'Incorrect password',
        }, 400);

    ApiException? ex;
    try {
      await api.deleteAccount(password: 'wrong');
    } on ApiException catch (e) {
      ex = e;
    }

    expect(ex, isNotNull);
    expect(ex!.status, 400);
    expect(ex.message, 'Incorrect password');
  });
}
