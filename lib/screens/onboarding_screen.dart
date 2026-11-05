import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/permission_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  Map<String, bool> _statuses = const {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final statuses = await PermissionService.checkAll();
    if (mounted) setState(() => _statuses = statuses);
  }

  Future<void> _request(String key) async {
    setState(() => _loading = true);
    try {
      final granted = await PermissionService.requestPermission(key);
      await _refresh();
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
          SnackBar(content: Text('Could not request permission: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continue() async {
    final missingCore = _statuses['notifications'] != true ||
        (Platform.isAndroid &&
            (_statuses['exactAlarm'] != true ||
                _statuses['fullScreenIntent'] != true));
    if (missingCore) {
      final continueAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some alarms may not work'),
          content: const Text(
            'Notifications, exact alarm access, and full-screen alarm access are needed for reliable ringing. You can continue, but WakeWise will block saving an enabled alarm until the required permissions are granted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Review permissions'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (continueAnyway != true) return;
    }
    await ref.read(settingsProvider.notifier).update(
      ref.read(settingsProvider).copyWith(onboardingComplete: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissionItems = [
      _PermissionInfo(
        key: 'notifications',
        label: 'Notifications',
        description: 'Shows alarms and gives you ringing controls.',
      ),
      if (Platform.isAndroid) ...[
        _PermissionInfo(
          key: 'exactAlarm',
          label: 'Exact alarms',
          description: 'Lets Android deliver alarms at their set time.',
        ),
        _PermissionInfo(
          key: 'fullScreenIntent',
          label: 'Full-screen alarm',
          description: 'Lets an alarm appear over the lock screen.',
        ),
        _PermissionInfo(
          key: 'batteryOptimization',
          label: 'Battery optimization',
          description:
              'Exemption helps some phone makers avoid delaying alarms.',
          optional: true,
        ),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.alarm_rounded, size: 64),
            const SizedBox(height: 18),
            Text(
              'Welcome to WakeWise',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            const Text(
              'Allow the permissions below so your alarms can ring on time. You can change them later in Settings.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            for (final item in permissionItems)
              Card(
                child: ListTile(
                  leading: Icon(
                    _statuses[item.key] == true
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: _statuses[item.key] == true
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: Text(item.label),
                  subtitle: Text(
                    '${item.description}${item.optional ? ' (recommended)' : ''}',
                  ),
                  trailing: TextButton(
                    onPressed: _loading || _statuses[item.key] == true
                        ? null
                        : () => _request(item.key),
                    child: Text(
                      _statuses[item.key] == true ? 'Allowed' : 'Allow',
                    ),
                  ),
                ),
              ),
            if (Platform.isIOS)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'iOS may restrict background ringing if the app is force-closed. Critical alerts require a special Apple entitlement and are not requested by this app.',
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _continue,
              child: const Text('Continue to WakeWise'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionInfo {
  const _PermissionInfo({
    required this.key,
    required this.label,
    required this.description,
    this.optional = false,
  });

  final String key;
  final String label;
  final String description;
  final bool optional;
}
