import 'package:flutter/widgets.dart';

import '../auth/auth_controller.dart';
import 'realtime_service.dart';

/// Ties the SSE stream to the app lifecycle, per the contract's realtime
/// conventions: keep `/events` open while the app is foregrounded and rely
/// on FCM push while backgrounded. Transitions through the app switcher
/// (`inactive`) keep the stream; `paused`/`hidden`/`detached` close it and
/// `resumed` reopens it — but only while a session exists. Closing the
/// stream on background is what makes the 30-minute server cap moot for
/// real usage.
class RealtimeLifecycle with WidgetsBindingObserver {
  RealtimeLifecycle({required this._realtime, required this._auth});

  final RealtimeService _realtime;
  final AuthController _auth;

  /// Registers with the widgets binding. Call once from `main`.
  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Detaches (used by tests).
  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_auth.status == AuthStatus.authenticated) {
          _realtime.connect();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // FCM push covers background delivery; the stream would hit the
        // 30-minute cap anyway.
        _realtime.disconnect();
      case AppLifecycleState.inactive:
        // Brief states (app switcher, permission dialogs) — keep the stream.
        break;
    }
  }
}
