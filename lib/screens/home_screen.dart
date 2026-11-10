import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';

/// Placeholder home for the auth increment: shows the signed-in profile and
/// logout. Dashboard/streaks/chat arrive in later increments.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RecoverTogether'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthController>().logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.spa_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              user == null ? 'Signed in' : 'Welcome, ${user.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (user != null) ...[
              const SizedBox(height: 8),
              Text(user.email),
              Text('Timezone: ${user.timezone}'),
            ],
            const SizedBox(height: 24),
            Text(
              'Dashboard, check-ins and chat are coming in the next increments.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
