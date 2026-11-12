import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/device_api.dart';
import '../api/dto.dart';

IconData _iconForPlatform(DevicePlatform? platform) => switch (platform) {
      DevicePlatform.ios => Icons.phone_iphone_outlined,
      DevicePlatform.android => Icons.phone_android_outlined,
      null => Icons.devices_other_outlined,
    };

/// Registered push devices (GET /users/me/devices): masked token previews,
/// active state, and removal. Push registration itself is automatic on login
/// when an FCM token source is available for this build.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Device> _devices = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _removing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await context.read<DeviceApi>().list();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _remove(Device device) async {
    final id = device.id;
    if (id == null) return;
    setState(() => _removing.add(id));
    try {
      await context.read<DeviceApi>().remove(id);
      if (!mounted) return;
      setState(() {
        _removing.remove(id);
        _devices = _devices.where((d) => d.id != id).toList();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _removing.remove(id));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Push devices',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Devices that receive push notifications for your '
                    'account. Removing a device stops its pushes.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_devices.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(Icons.phonelink_off_outlined,
                                size: 40, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            const Text('No devices registered.'),
                            const SizedBox(height: 4),
                            Text(
                              'This build does not have push configured — '
                              'device registration starts automatically '
                              'once FCM is available.',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final device in _devices)
                            ListTile(
                              leading: Icon(
                                _iconForPlatform(device.platform),
                              ),
                              title: Text(
                                device.deviceName.isEmpty
                                    ? 'Unnamed device'
                                    : device.deviceName,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((device.tokenPreview ?? '')
                                      .isNotEmpty)
                                    Text(device.tokenPreview!),
                                  Text(
                                    device.active == false
                                        ? 'Inactive'
                                        : 'Active',
                                    style: TextStyle(
                                      color: device.active == false
                                          ? theme.colorScheme.error
                                          : Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: _removing.contains(device.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : IconButton(
                                      tooltip: 'Remove device',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _remove(device),
                                    ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
