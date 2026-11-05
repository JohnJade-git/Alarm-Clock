import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/permission_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  Map<String, bool> _permissions = const {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissions());
    }
  }

  Future<void> _refreshPermissions() async {
    final statuses = await PermissionService.checkAll();
    if (mounted) setState(() => _permissions = statuses);
  }

  Future<void> _request(String key) async {
    setState(() => _loading = true);
    try {
      final granted = await PermissionService.requestPermission(key);
      await _refreshPermissions();
      if (!granted && key != 'fullScreenIntent' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Permission is still missing. Allow it in system settings.',
            ),
            action: SnackBarAction(
              label: 'Open settings',
              onPressed: () {
                unawaited(PermissionService.openSystemSettings());
              },
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update permission: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final permissions = [
      _PermissionRow(
        keyName: 'notifications',
        title: 'Notifications',
        description: 'Required to show alarms and notification controls.',
      ),
      if (Platform.isAndroid) ...[
        _PermissionRow(
          keyName: 'exactAlarm',
          title: 'Exact alarm access',
          description: 'Required for on-time alarm delivery.',
        ),
        _PermissionRow(
          keyName: 'fullScreenIntent',
          title: 'Full-screen alarm',
          description: 'Allows the alarm to appear over the lock screen.',
        ),
        _PermissionRow(
          keyName: 'batteryOptimization',
          title: 'Battery optimization exemption',
          description: 'Recommended for background reliability.',
        ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Display', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('24-hour clock'),
            value: settings.use24Hour,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .update(settings.copyWith(use24Hour: value)),
          ),
          DropdownButtonFormField<ThemeMode>(
            initialValue: settings.themeMode,
            decoration: const InputDecoration(labelText: 'Theme'),
            items: const [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('System default'),
              ),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                ref
                    .read(settingsProvider.notifier)
                    .update(settings.copyWith(themeMode: mode));
              }
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Permission check',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final item in permissions)
            Card(
              child: ListTile(
                leading: Icon(
                  _permissions[item.keyName] == true
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: _permissions[item.keyName] == true
                      ? Colors.green
                      : Colors.orange,
                ),
                title: Text(item.title),
                subtitle: Text(item.description),
                trailing: TextButton(
                  onPressed: _loading || _permissions[item.keyName] == true
                      ? null
                      : () => _request(item.keyName),
                  child: Text(
                    _permissions[item.keyName] == true ? 'Granted' : 'Fix',
                  ),
                ),
              ),
            ),
          if (Platform.isIOS)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Critical alerts are optional and require an Apple entitlement. iOS may not ring alarms after the app is force-closed or the phone restarts.',
              ),
            ),
          TextButton.icon(
            onPressed: () async {
              await PermissionService.openSystemSettings();
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open app system settings'),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow {
  const _PermissionRow({
    required this.keyName,
    required this.title,
    required this.description,
  });

  final String keyName;
  final String title;
  final String description;
}
