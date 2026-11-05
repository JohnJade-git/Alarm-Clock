import 'dart:io';

import 'package:alarm/alarm.dart' as native_alarm;
import 'package:flutter/foundation.dart';

import '../models/alarm.dart';
import 'permission_service.dart';

class AlarmService {
  AlarmService._();

  static const _repeatHorizonDays = 14;

  static Future<void> initialize() async {
    await native_alarm.Alarm.init();
  }

  static Future<void> schedule(Alarm alarm) async {
    if (!alarm.enabled) {
      await cancel(alarm.id);
      return;
    }

    await _requireSchedulingPermissions();
    await cancel(alarm.id);

    final occurrences = alarm.repeatDays.isEmpty
        ? [_nextOneTimeOccurrence(alarm)]
        : _repeatOccurrences(alarm, _repeatHorizonDays);
    for (final occurrence in occurrences) {
      final settings = _settingsFor(
        alarm,
        id: _stableId('${alarm.id}:${occurrence.toIso8601String()}'),
        dateTime: occurrence,
      );
      final success = await native_alarm.Alarm.set(alarmSettings: settings);
      if (!success) {
        await cancel(alarm.id);
        throw StateError('The phone could not schedule this alarm.');
      }
    }
  }

  static Future<void> replenishRepeatingSchedule(Alarm alarm) async {
    if (!alarm.enabled || alarm.repeatDays.isEmpty) return;
    await _requireSchedulingPermissions();

    final scheduled = await native_alarm.Alarm.getAlarms();
    final ringing = native_alarm.Alarm.ringing.value.alarms;
    final existingIds = <int>{
      for (final item in scheduled)
        if (item.payload == alarm.id) item.id,
      for (final item in ringing)
        if (item.payload == alarm.id) item.id,
    };

    for (final occurrence in _repeatOccurrences(alarm, _repeatHorizonDays)) {
      final id = _stableId('${alarm.id}:${occurrence.toIso8601String()}');
      if (existingIds.contains(id)) continue;
      final success = await native_alarm.Alarm.set(
        alarmSettings: _settingsFor(alarm, id: id, dateTime: occurrence),
      );
      if (!success) {
        throw StateError('The next repeating alarm could not be scheduled.');
      }
    }
  }

  static Future<void> scheduleSnooze(Alarm alarm) async {
    await _requireSchedulingPermissions();
    final now = DateTime.now();
    final snoozeAt = now.add(Duration(minutes: alarm.snoozeMinutes));
    final snoozeId = _stableId(
      '${alarm.id}:snooze:${now.microsecondsSinceEpoch}',
    );
    final success = await native_alarm.Alarm.set(
      alarmSettings: _settingsFor(alarm, id: snoozeId, dateTime: snoozeAt),
    );
    if (!success) {
      throw StateError('The phone could not schedule the snooze.');
    }
  }

  static Future<void> stop(int id) async {
    final stopped = await native_alarm.Alarm.stop(id);
    if (!stopped && kDebugMode) {
      debugPrint('Alarm $id was no longer active when stop was requested.');
    }
  }

  static Future<void> cancel(String alarmId) async {
    final scheduled = await native_alarm.Alarm.getAlarms();
    final ringing = native_alarm.Alarm.ringing.value.alarms;
    final matchingIds = <int>{
      for (final alarm in scheduled)
        if (alarm.payload == alarmId) alarm.id,
      for (final alarm in ringing)
        if (alarm.payload == alarmId) alarm.id,
    };
    for (final id in matchingIds) {
      await native_alarm.Alarm.stop(id);
    }
  }

  static DateTime nextOccurrence(Alarm alarm, {DateTime? after}) {
    final now = after ?? DateTime.now();
    for (var offset = 0; offset < 8; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      if (alarm.repeatDays.isNotEmpty &&
          !alarm.repeatDays.contains(date.weekday)) {
        continue;
      }
      final candidate = DateTime(
        date.year,
        date.month,
        date.day,
        alarm.hour,
        alarm.minute,
      );
      if (candidate.isAfter(now)) return candidate;
    }
    throw StateError('Could not calculate the next alarm occurrence.');
  }

  static native_alarm.AlarmSettings settingsForOccurrence(
    Alarm alarm,
    int occurrenceId,
    DateTime dateTime,
  ) => _settingsFor(alarm, id: occurrenceId, dateTime: dateTime);

  static int stableIdFor(String value) => _stableId(value);

  static Future<void> _requireSchedulingPermissions() async {
    final notificationsAllowed =
        await PermissionService.ensureNotificationPermission();
    if (!notificationsAllowed) {
      throw StateError('Notification permission is required for alarms.');
    }
    if (Platform.isAndroid) {
      final exactAllowed = await PermissionService.ensureExactAlarmPermission();
      if (!exactAllowed) {
        throw StateError('Exact alarm access is required to set an alarm.');
      }
      final fullScreenAllowed =
          await PermissionService.fullScreenIntentGranted();
      if (!fullScreenAllowed) {
        throw StateError('Allow full-screen alarms in system settings.');
      }
    }
  }

  static native_alarm.AlarmSettings _settingsFor(
    Alarm alarm, {
    required int id,
    required DateTime dateTime,
  }) {
    return native_alarm.AlarmSettings(
      id: id,
      dateTime: dateTime,
      payload: alarm.id,
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      androidAlarmClock: true,
      androidSnoozeDuration: Duration(minutes: alarm.snoozeMinutes),
      volumeSettings: native_alarm.VolumeSettings.fade(
        fadeDuration: Duration(seconds: 30),
        volume: 1.0,
      ),
      notificationSettings: native_alarm.NotificationSettings(
        title: 'WakeWise alarm',
        body: 'Your alarm is ringing',
        stopButton: alarm.challenge == WakeChallenge.none ? 'Dismiss' : null,
        androidSnoozeButton: alarm.challenge == WakeChallenge.none
            ? 'Snooze'
            : null,
        androidStopAlarmOnDismiss: false,
      ),
    );
  }

  static List<DateTime> _repeatOccurrences(Alarm alarm, int horizonDays) {
    final now = DateTime.now();
    final result = <DateTime>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      if (!alarm.repeatDays.contains(date.weekday)) continue;
      final occurrence = DateTime(
        date.year,
        date.month,
        date.day,
        alarm.hour,
        alarm.minute,
      );
      if (occurrence.isAfter(now)) result.add(occurrence);
    }
    return result;
  }

  static DateTime _nextOneTimeOccurrence(Alarm alarm) {
    final now = DateTime.now();
    var occurrence = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.hour,
      alarm.minute,
    );
    if (!occurrence.isAfter(now)) {
      occurrence = DateTime(
        now.year,
        now.month,
        now.day + 1,
        alarm.hour,
        alarm.minute,
      );
    }
    return occurrence;
  }

  static int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
