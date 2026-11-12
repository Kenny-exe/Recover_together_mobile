import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/dto.dart';
import '../api/user_api.dart';
import '../auth/auth_controller.dart';
import 'devices_screen.dart';

/// Profile management: edit name/email/timezone, change the password (which
/// signs the user out everywhere), and the irreversible account deletion.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _timezone = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _savingProfile = false;
  bool _changingPassword = false;
  String? _profileError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthController>().user;
    _name.text = user?.name ?? '';
    _email.text = user?.email ?? '';
    _timezone.text = user?.timezone ?? 'UTC';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _timezone.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || _savingProfile) return;
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      final updated = await context.read<UserApi>().updateProfile(
            name: _name.text.trim(),
            email: _email.text.trim(),
            timezone: _timezone.text.trim(),
          );
      if (!mounted) return;
      context.read<AuthController>().updateUser(updated);
      setState(() => _savingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingProfile = false;
        _profileError = e.message;
      });
    }
  }

  Future<void> _useDeviceTimezone() async {
    final zone = DateTime.now().timeZoneName;
    if (!zone.contains('/')) return; // not an IANA id on this platform
    setState(() => _timezone.text = zone);
  }

  Future<void> _changePassword() async {
    if (_changingPassword) return;
    final current = _currentPassword.text;
    final next = _newPassword.text;
    if (current.isEmpty || next.length < 8) return;
    if (next != _confirmPassword.text) {
      setState(() => _passwordError = 'Passwords do not match');
      return;
    }
    setState(() {
      _changingPassword = true;
      _passwordError = null;
    });
    final auth = context.read<AuthController>();
    final userApi = context.read<UserApi>();
    try {
      await userApi.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      // All tokens were invalidated server-side — drop the local pair and
      // land on the login screen.
      await auth.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password changed. Please log in again.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _changingPassword = false;
        _passwordError = e.message;
      });
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final auth = context.read<AuthController>();
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (deleted == true) {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Profile', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 2) return 'Name must be at least 2 characters';
                    if (t.length > 100) return 'Name must be at most 100 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Email is required';
                    final ok =
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
                    return ok ? null : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timezone,
                  decoration: InputDecoration(
                    labelText: 'Timezone (IANA id)',
                    helperText:
                        'Used for local-day check-ins, e.g. Europe/Berlin',
                    prefixIcon: const Icon(Icons.schedule_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Use device timezone',
                      icon: const Icon(Icons.my_location),
                      onPressed: _useDeviceTimezone,
                    ),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length > 64) {
                      return 'Timezone must be at most 64 characters';
                    }
                    return null;
                  },
                ),
                if (_profileError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _profileError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: _savingProfile
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save profile'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Change password', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Changing your password signs you out everywhere; you will need '
            'to log in again.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _currentPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Current password is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                validator: (v) {
                  final t = v ?? '';
                  if (t.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (t.length > 128) {
                    return 'Password must be at most 128 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_reset_outlined),
                ),
                onFieldSubmitted: (_) => _changePassword(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Confirm the new password' : null,
              ),
              if (_passwordError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _passwordError!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _changingPassword ? null : _changePassword,
                icon: _changingPassword
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.password_outlined),
                label: const Text('Change password'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Devices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: const Text('Push devices'),
              subtitle: const Text(
                  'Phones that receive push notifications for your account'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DevicesScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Danger zone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            onPressed: _confirmDeleteAccount,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete account'),
          ),
          const SizedBox(height: 8),
          Text(
            'Deletion is irreversible. All your data — check-ins, messages, '
            'devices — is removed.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Confirmation dialog for account deletion: requires the current password
/// (a bare token is not enough, per the contract) and surfaces server errors
/// inline (wrong password → 400, locked account → 429).
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<UserApi>()
          .deleteAccount(password: _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is irreversible. Confirm with your password:',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Current password',
            ),
            onSubmitted: (_) => _delete(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style:
                  TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _busy ? null : _delete,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Delete forever'),
        ),
      ],
    );
  }
}
