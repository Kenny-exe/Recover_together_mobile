import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/checkin_api.dart';
import 'auth/auth_controller.dart';
import 'auth/token_storage.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = SecureTokenStorage();
  final client = ApiClient(storage: storage);
  final authController = AuthController(client: client, storage: storage);
  unawaited(authController.bootstrap());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authController),
        Provider<CheckInApi>(create: (_) => CheckInApi(client.api)),
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
