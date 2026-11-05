import 'dart:async';

import 'package:alarm/alarm.dart' as native_alarm;
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/alarm.dart';
import '../providers/alarm_provider.dart';
import '../providers/settings_provider.dart';
import '../services/alarm_service.dart';
import '../services/hive_service.dart';
import '../services/permission_service.dart';
import 'ringing_screen.dart';
import 'settings_screen.dart';

class WakeWiseHomeScreen extends ConsumerStatefulWidget {
  const WakeWiseHomeScreen({super.key});

  @override
  ConsumerState<WakeWiseHomeScreen> createState() => _WakeWiseHomeScreenState();
}

class _WakeWiseHomeScreenState extends ConsumerState<WakeWiseHomeScreen>
    with WidgetsBindingObserver {
  StreamSubscription<AlarmSet>? _ringSubscription;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  final Set<int> _visibleRingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _ringSubscription = native_alarm.Alarm.ringing.listen(_onRingingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreAlarms());
      _onRingingChanged(native_alarm.Alarm.ringing.value);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _ringSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_restoreAlarms());
      _onRingingChanged(native_alarm.Alarm.ringing.value);
    }
  }

  Future<void> _restoreAlarms() async {
    if (native_alarm.Alarm.ringing.value.alarms.isNotEmpty) return;
    final permissions = await PermissionService.checkAll();
    if (permissions['notifications'] != true ||
        (native_alarm.Alarm.android &&
            (permissions['exactAlarm'] != true ||
                permissions['fullScreenIntent'] != true))) {
      return;
    }
    final storedAlarms = ref.read(alarmProvider);
    final timezoneStamp =
        '${DateTime.now().timeZoneName}:${DateTime.now().timeZoneOffset.inMinutes}';
    final timezoneChanged =
        HiveService.readObject('alarmTimezone') != timezoneStamp;
    final enabledIds = storedAlarms
        .where((alarm) => alarm.enabled)
        .map((alarm) => alarm.id)
        .toSet();
    final scheduled = await native_alarm.Alarm.getAlarms();
    for (final pending in scheduled) {
      if (pending.payload != null && !enabledIds.contains(pending.payload)) {
        await native_alarm.Alarm.stop(pending.id);
      }
    }

    var schedulingSucceeded = true;
    for (final alarm in storedAlarms.where((item) => item.enabled)) {
      try {
        if (timezoneChanged) {
          await AlarmService.schedule(alarm);
        } else if (alarm.repeatDays.isNotEmpty) {
          await AlarmService.schedule(alarm);
        } else {
          final exists = scheduled.any((item) => item.payload == alarm.id);
          if (!exists) {
            await AlarmService.schedule(alarm);
          }
        }
      } catch (error) {
        schedulingSucceeded = false;
        if (mounted) _showMessage('Could not restore ${alarm.label}: $error');
      }
    }
    if (schedulingSucceeded) {
      await HiveService.saveObject('alarmTimezone', timezoneStamp);
    }
  }

  void _onRingingChanged(AlarmSet ringing) {
    for (final nativeAlarm in ringing.alarms) {
      if (!_visibleRingIds.add(nativeAlarm.id)) continue;
      final alarmId = nativeAlarm.payload;
      if (alarmId == null) {
        _visibleRingIds.remove(nativeAlarm.id);
        continue;
      }

      Alarm? alarm;
      for (final item in ref.read(alarmProvider)) {
        if (item.id == alarmId) {
          alarm = item;
          break;
        }
      }
      if (alarm == null) {
        _visibleRingIds.remove(nativeAlarm.id);
        unawaited(AlarmService.stop(nativeAlarm.id));
        continue;
      }

      if (alarm.repeatDays.isNotEmpty) {
        unawaited(_replenishRepeating(alarm));
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true)
            .push<void>(
              MaterialPageRoute(
                builder: (_) => AlarmRingScreen(
                  alarm: alarm!,
                  occurrenceId: nativeAlarm.id,
                  onDismiss: () => _dismiss(nativeAlarm.id, alarm!),
                  onSnooze: () => _snooze(nativeAlarm.id, alarm!),
                ),
              ),
            )
            .whenComplete(() => _visibleRingIds.remove(nativeAlarm.id));
      });
    }

    final activeIds = ringing.alarms.map((item) => item.id).toSet();
    _visibleRingIds.removeWhere(
      (id) =>
          !activeIds.contains(id) &&
          !native_alarm.Alarm.scheduled.value.containsId(id),
    );
  }

  Future<void> _replenishRepeating(Alarm alarm) async {
    try {
      await AlarmService.replenishRepeatingSchedule(alarm);
    } catch (error) {
      if (mounted) _showMessage('Could not extend ${alarm.label}: $error');
    }
  }

  Future<void> _dismiss(int nativeId, Alarm alarm) async {
    await AlarmService.stop(nativeId);
    if (alarm.repeatDays.isNotEmpty && alarm.enabled) {
      await AlarmService.replenishRepeatingSchedule(alarm);
    } else if (alarm.enabled) {
      await ref
          .read(alarmProvider.notifier)
          .saveAlarm(alarm.copyWith(enabled: false));
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _snooze(int nativeId, Alarm alarm) async {
    await AlarmService.scheduleSnooze(alarm);
    await AlarmService.stop(nativeId);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final alarms = ref.watch(alarmProvider);
    final nextAlarm = _nextAlarm(alarms);
    final use24Hour = ref.watch(settingsProvider).use24Hour;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WakeWise'),
        actions: [
          IconButton(
            tooltip: 'Permissions and settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              child: Column(
                children: [
                  Text(
                    DateFormat('EEEE, MMMM d').format(_now),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat(use24Hour ? 'HH:mm:ss' : 'h:mm:ss a')
                        .format(_now),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w300,
                      letterSpacing: -2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (nextAlarm != null)
              Card(
                margin: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: ListTile(
                  leading: const Icon(Icons.alarm),
                  title: Text('Rings in ${_countdown(nextAlarm)}'),
                  subtitle: Text(
                    '${nextAlarm.label} · ${_formatTime(nextAlarm, use24Hour)}',
                  ),
                ),
              ),
            Expanded(
              child: alarms.isEmpty
                  ? _emptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: alarms.length,
                      itemBuilder: (context, index) {
                        final alarm = alarms[index];
                        return _AlarmTile(
                          alarm: alarm,
                          use24Hour: use24Hour,
                          onChanged: (enabled) => _toggle(alarm, enabled),
                          onTap: () => _editAlarm(alarm),
                          onDelete: () => _deleteAlarm(alarm),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editAlarm(null),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add alarm'),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.alarm_add_rounded, size: 52),
          const SizedBox(height: 12),
          Text('No alarms yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          const Text('Add an alarm to start your morning on time.'),
        ],
      ),
    ),
  );

  Alarm? _nextAlarm(List<Alarm> alarms) {
    Alarm? next;
    DateTime? nextTime;
    for (final alarm in alarms.where((item) => item.enabled)) {
      final time = AlarmService.nextOccurrence(alarm);
      if (nextTime == null || time.isBefore(nextTime)) {
        next = alarm;
        nextTime = time;
      }
    }
    return next;
  }

  String _countdown(Alarm alarm) {
    final delta = AlarmService.nextOccurrence(alarm).difference(_now);
    final hours = delta.inHours;
    final minutes = delta.inMinutes.remainder(60);
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }

  String _formatTime(Alarm alarm, bool use24Hour) =>
      DateFormat(use24Hour ? 'HH:mm' : 'h:mm a')
          .format(DateTime(2000, 1, 1, alarm.hour, alarm.minute));

  Future<void> _toggle(Alarm alarm, bool enabled) async {
    HapticFeedback.selectionClick();
    try {
      final updated = alarm.copyWith(enabled: enabled);
      if (enabled) {
        await _checkPermissionsForAlarm();
        await AlarmService.schedule(updated);
      } else {
        await AlarmService.cancel(alarm.id);
      }
      await ref.read(alarmProvider.notifier).saveAlarm(updated);
    } catch (error) {
      if (mounted) _showMessage('Alarm was not changed: $error');
    }
  }

  Future<void> _editAlarm(Alarm? existing) async {
    final result = await showDialog<Alarm>(
      context: context,
      builder: (context) => _AlarmEditorDialog(existing: existing),
    );
    if (result == null || !mounted) return;

    try {
      if (result.enabled) {
        await _checkPermissionsForAlarm();
        await AlarmService.schedule(result);
      } else {
        await AlarmService.cancel(result.id);
      }
      await ref.read(alarmProvider.notifier).saveAlarm(result);
      if (mounted) _showMessage('Alarm saved.');
    } catch (error) {
      if (mounted) _showMessage('Alarm was not saved: $error');
    }
  }

  Future<void> _checkPermissionsForAlarm() async {
    final notificationsAllowed =
        await PermissionService.ensureNotificationPermission();
    final exactAllowed = await PermissionService.ensureExactAlarmPermission();
    final fullScreenAllowed = await PermissionService.fullScreenIntentGranted();
    if (!notificationsAllowed || !exactAllowed || !fullScreenAllowed) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Alarm permission required'),
            content: const Text(
              'WakeWise did not save this alarm. Allow notifications, exact alarms, and full-screen alarms so it can ring reliably.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Navigator.of(this.context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                child: const Text('Review permissions'),
              ),
            ],
          ),
        );
      }
      throw StateError('Required alarm permissions were not granted.');
    }
  }

  Future<void> _deleteAlarm(Alarm alarm) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete alarm?'),
        content: Text('Delete “${alarm.label}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await AlarmService.cancel(alarm.id);
    await ref.read(alarmProvider.notifier).deleteAlarm(alarm.id);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.alarm,
    required this.use24Hour,
    required this.onChanged,
    required this.onTap,
    required this.onDelete,
  });

  final Alarm alarm;
  final bool use24Hour;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textColor = alarm.enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          Icons.alarm_rounded,
          color: alarm.enabled ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          DateFormat(use24Hour ? 'HH:mm' : 'h:mm a')
              .format(DateTime(2000, 1, 1, alarm.hour, alarm.minute)),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        subtitle: Text(
          '${alarm.label}  ·  ${_repeatLabel(alarm.repeatDays)}'
          '${alarm.challenge == WakeChallenge.none ? '' : '  ·  ${_challengeLabel(alarm.challenge)}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: alarm.enabled, onChanged: onChanged),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') onTap();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _repeatLabel(List<int> days) {
    if (days.isEmpty) return 'Once';
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (days.length == 7) return 'Every day';
    if (days.length == 5 && days.toSet().containsAll([1, 2, 3, 4, 5])) {
      return 'Weekdays';
    }
    return days.map((day) => labels[day - 1]).join(', ');
  }

  static String _challengeLabel(WakeChallenge challenge) => switch (challenge) {
    WakeChallenge.none => 'No challenge',
    WakeChallenge.shake => 'Shake challenge',
    WakeChallenge.walk => 'Walk challenge',
  };
}

class _AlarmEditorDialog extends StatefulWidget {
  const _AlarmEditorDialog({required this.existing});

  final Alarm? existing;

  @override
  State<_AlarmEditorDialog> createState() => _AlarmEditorDialogState();
}

class _AlarmEditorDialogState extends State<_AlarmEditorDialog> {
  late final TextEditingController _labelController;
  late TimeOfDay _time;
  late final Set<int> _repeatDays;
  late final int _snoozeMinutes;
  late WakeChallenge _challenge;

  @override
  void initState() {
    super.initState();
    final alarm = widget.existing;
    _labelController = TextEditingController(text: alarm?.label ?? 'Wake up');
    _time = TimeOfDay(hour: alarm?.hour ?? 7, minute: alarm?.minute ?? 0);
    _repeatDays = {...?alarm?.repeatDays};
    _snoozeMinutes = alarm?.snoozeMinutes ?? 5;
    _challenge = alarm?.challenge ?? WakeChallenge.none;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Add alarm' : 'Edit alarm'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: TextButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                _time.format(context),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          TextField(
            controller: _labelController,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 8),
          Text('Repeat', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: List.generate(7, (index) {
              final day = index + 1;
              const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
              return FilterChip(
                label: Text(labels[index]),
                selected: _repeatDays.contains(day),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _repeatDays.add(day);
                    } else {
                      _repeatDays.remove(day);
                    }
                  });
                },
              );
            }),
          ),
          if (_repeatDays.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('One-time alarm'),
            ),
          const SizedBox(height: 8),
          Text('Snooze: $_snoozeMinutes minutes'),
          const SizedBox(height: 12),
          Text(
            'Wake-up challenge',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _challengeChip(WakeChallenge.none, 'None'),
              _challengeChip(WakeChallenge.shake, 'Shake · 30 times'),
              _challengeChip(WakeChallenge.walk, 'Walk · 20 steps'),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  Future<void> _pickTime() async {
    final selected = await showTimePicker(context: context, initialTime: _time);
    if (selected != null) setState(() => _time = selected);
  }

  Widget _challengeChip(WakeChallenge challenge, String label) => ChoiceChip(
    label: Text(label),
    selected: _challenge == challenge,
    onSelected: (_) => setState(() => _challenge = challenge),
  );

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a label for this alarm.')),
      );
      return;
    }
    if (_challenge == WakeChallenge.walk &&
        !await PermissionService.ensureMotionPermission()) {
      if (!mounted) return;
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Activity permission needed'),
          content: const Text(
            'Allow physical activity access so WakeWise can count your 20 steps.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await PermissionService.openSystemSettings();
      }
      return;
    }
    if (!mounted) return;
    final existing = widget.existing;
    final alarm = Alarm(
      id: existing?.id ?? const Uuid().v4(),
      label: label,
      hour: _time.hour,
      minute: _time.minute,
      enabled: existing?.enabled ?? true,
      repeatDays: _repeatDays.toList()..sort(),
      snoozeMinutes: _snoozeMinutes,
      challenge: _challenge,
    );
    Navigator.pop(context, alarm);
  }
}
