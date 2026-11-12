import 'package:dio/dio.dart';

import 'dto.dart';

/// Push device registration endpoints from the contract. All calls run on the
/// authenticated Dio instance (bearer attached, silent refresh wired).
class DeviceApi {
  DeviceApi(this._dio);

  final Dio _dio;

  /// GET /users/me/devices — the user's registered push devices, with the
  /// FCM tokens masked as previews.
  Future<List<Device>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('/users/me/devices');
      return res.data!
          .map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// POST /users/me/devices — registers (or re-registers) the FCM token.
  /// Registering a token that belongs to another account transfers it to
  /// this one (app reinstall handoff).
  Future<Device> register({
    required DevicePlatform platform,
    required String token,
    String? deviceName,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/users/me/devices',
        data: {
          'platform': platform.wire,
          'token': token,
          'deviceName': ?deviceName,
        },
      );
      return Device.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// DELETE /users/me/devices/{deviceId} — forgets one device.
  Future<void> remove(int deviceId) async {
    try {
      await _dio.delete<void>('/users/me/devices/$deviceId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
