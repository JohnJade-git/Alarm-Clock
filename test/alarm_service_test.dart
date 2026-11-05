import 'package:flutter_test/flutter_test.dart';
import 'package:wakewise/models/alarm.dart';
import 'package:wakewise/services/alarm_service.dart';

void main() {
  test('one-time alarm selects its next local occurrence', () {
    final alarm = Alarm(id: 'one-time', label: 'One time', hour: 7, minute: 5);
    final after = DateTime(2026, 11, 5, 7, 5);

    expect(
      AlarmService.nextOccurrence(alarm, after: after),
      DateTime(2026, 11, 6, 7, 5),
    );
  });

  test('repeating alarm selects the next enabled weekday', () {
    final alarm = Alarm(
      id: 'weekday',
      label: 'Weekday',
      hour: 7,
      minute: 0,
      repeatDays: const [1, 2, 3, 4, 5],
    );
    final after = DateTime(2026, 11, 6, 7, 0); // Friday, after the alarm.

    expect(
      AlarmService.nextOccurrence(alarm, after: after),
      DateTime(2026, 11, 9, 7, 0),
    );
  });

  test('alarm identifiers remain stable across app launches', () {
    expect(
      AlarmService.stableIdFor('wake:2026-11-05T07:00:00.000'),
      AlarmService.stableIdFor('wake:2026-11-05T07:00:00.000'),
    );
    expect(
      AlarmService.stableIdFor('wake:2026-11-05T07:00:00.000'),
      isNot(AlarmService.stableIdFor('wake:2026-11-06T07:00:00.000')),
    );
  });

  test(
    'challenge alarms do not expose notification dismiss or snooze actions',
    () {
      final alarm = Alarm(
        id: 'challenge-alarm',
        label: 'Wake up',
        hour: 7,
        minute: 0,
        challenge: WakeChallenge.shake,
      );
      final settings = AlarmService.settingsForOccurrence(
        alarm,
        1,
        DateTime(2026, 11, 6, 7),
      );

      expect(settings.notificationSettings.stopButton, isNull);
      expect(settings.notificationSettings.androidSnoozeButton, isNull);
      expect(settings.notificationSettings.androidStopAlarmOnDismiss, isFalse);
    },
  );
}
