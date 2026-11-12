import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../api/device_api.dart';
import '../api/dto.dart';

/// Supplies the current FCM registration token for this install. The real
/// implementation arrives with `firebase_messaging` (and its Firebase project
/// configuration); until then [NoopPushTokenSource] keeps the flow wired but
/// inert — the backend stays log-only without FCM credentials anyway.
abstract class PushTokenSource {
  /// The current token, or null when push is unavailable on this device
  /// (no Firebase config, emulator without Play services, …).
  Future<String?> currentToken();
}

/// Default source before Firebase is wired: always null, logged once.
class NoopPushTokenSource implements PushTokenSource {
  bool _logged = false;

  @override
  Future<String?> currentToken() async {
    if (!_logged) {
      _logged = true;
      developer.log(
        'Push is not configured on this build (no FCM token source). '
        'Device registration will start once firebase_messaging is wired.',
        name: 'push',
      );
    }
    return null;
  }
}

/// Registers the device's push token with the backend on login. Idempotent:
/// the same token is registered once per session; a changed token (FCM
/// refresh, reinstall handoff) re-registers. Best-effort — failures are
/// logged and never break the login flow.
class DeviceRegistrar {
  DeviceRegistrar({
    required this._api,
    required this._tokenSource,
    String? deviceName,
  }) : deviceName = deviceName ?? '${defaultTargetPlatform.name} device';

  final DeviceApi _api;
  final PushTokenSource _tokenSource;

  /// Friendly name sent with the registration (optional per the contract).
  final String deviceName;

  String? _lastRegisteredToken;
  Future<void>? _inFlight;

  /// Registers the current token if it is new. Safe to call repeatedly (it
  /// is called from the auth-state listener on every login) — parallel calls
  /// share one registration.
  Future<void> registerIfNeeded() async {
    if (_inFlight != null) return _inFlight;
    final task = _register();
    _inFlight = task;
    try {
      await task;
    } finally {
      if (_inFlight == task) _inFlight = null;
    }
  }

  Future<void> _register() async {
    final token = await _tokenSource.currentToken();
    if (token == null || token.isEmpty) return;
    if (token == _lastRegisteredToken) return;

    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? DevicePlatform.ios
        : DevicePlatform.android;
    try {
      await _api.register(
        platform: platform,
        token: token,
        deviceName: deviceName,
      );
      _lastRegisteredToken = token;
    } on ApiException catch (e) {
      // Best-effort: the user is logged in either way; the next login or
      // token refresh retries.
      developer.log('Device registration failed: ${e.message}',
          name: 'push');
    }
  }

  /// Forgets the last-registered token so the next [registerIfNeeded] sends
  /// a fresh registration (used after logout; token → account binding is
  /// handled server-side on the next login).
  void reset() {
    _lastRegisteredToken = null;
  }
}
