import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/checkin_api.dart';
import 'api/device_api.dart';
import 'api/message_api.dart';
import 'api/notification_api.dart';
import 'api/partner_api.dart';
import 'api/user_api.dart';
import 'auth/auth_controller.dart';
import 'auth/token_storage.dart';
import 'push/device_registrar.dart';
import 'realtime/realtime_lifecycle.dart';
import 'realtime/realtime_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = SecureTokenStorage();
  final client = ApiClient(storage: storage);
  final authController = AuthController(client: client, storage: storage);
  final realtime = RealtimeService(storage: storage);
  final deviceRegistrar = DeviceRegistrar(
    api: DeviceApi(client.api),
    tokenSource: NoopPushTokenSource(),
  );

  // SSE stream follows the session state: connected while authenticated,
  // closed (and kept closed) whenever the user logs out or is dropped.
  // Logging in also (re-)registers this device for FCM push.
  authController.addListener(() {
    switch (authController.status) {
      case AuthStatus.authenticated:
        realtime.connect();
        deviceRegistrar.registerIfNeeded();
      case AuthStatus.anonymous:
      case AuthStatus.unknown:
        realtime.disconnect();
        deviceRegistrar.reset();
    }
  });

  // Foreground/background: the contract keeps /events open only while the
  // app is foregrounded — FCM push covers background delivery.
  RealtimeLifecycle(realtime: realtime, auth: authController).attach();

  unawaited(authController.bootstrap());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authController),
        Provider<CheckInApi>(create: (_) => CheckInApi(client.api)),
        Provider<PartnerApi>(create: (_) => PartnerApi(client.api)),
        Provider<MessageApi>(create: (_) => MessageApi(client.api)),
        Provider<UserApi>(create: (_) => UserApi(client.api)),
        Provider<NotificationApi>(create: (_) => NotificationApi(client.api)),
        Provider<DeviceApi>(create: (_) => DeviceApi(client.api)),
        Provider<RealtimeService>.value(value: realtime),
        Provider<DeviceRegistrar>.value(value: deviceRegistrar),
      ],
      child: const RecoverTogetherApp(),
    ),
  );
}

class RecoverTogetherApp extends StatelessWidget {
  const RecoverTogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RecoverTogether',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Routes between the loading, login and home screens based on session state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return switch (auth.status) {
      AuthStatus.unknown => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthStatus.anonymous => const LoginScreen(),
      AuthStatus.authenticated => const HomeScreen(),
    };
  }
}
