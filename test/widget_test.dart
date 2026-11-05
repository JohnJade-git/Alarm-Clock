import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:wakewise/models/alarm.dart';
import 'package:wakewise/providers/alarm_provider.dart';
import 'package:wakewise/services/hive_service.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('wakewise-test-');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('wakewise-test');
    final oldAlarmBox = await Hive.openBox<dynamic>('alarms');
    await oldAlarmBox.put('old-alarm', {
      'id': 'old-alarm',
      'label': 'Legacy alarm',
      'hour': 6,
      'minute': 30,
      'enabled': true,
      'repeatDays': [1, 3, 5],
      'sound': 'rain',
    });
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await box.close();
    await HiveService.close();
    await Hive.deleteFromDisk();
    await directory.delete(recursive: true);
  });

  test('alarm model round-trips to Hive', () async {
    final alarm = Alarm(
      id: 'test-alarm',
      label: 'Wake up',
      hour: 7,
      minute: 5,
      repeatDays: const [1, 2, 3, 4, 5],
      snoozeMinutes: 5,
      challenge: WakeChallenge.walk,
    );

    await box.put(alarm.id, alarm.toMap());
    final restored = Alarm.fromMap(
      Map<String, dynamic>.from(box.get(alarm.id)),
    );
    expect(restored.id, alarm.id);
    expect(restored.label, alarm.label);
    expect(restored.repeatDays, [1, 2, 3, 4, 5]);
    expect(restored.snoozeMinutes, 5);
    expect(restored.challenge, WakeChallenge.walk);
  });

  test('alarm provider persists alarms', () async {
    final notifier = AlarmNotifier();
    final alarm = Alarm(
      id: 'provider-alarm',
      label: 'Test alarm',
      hour: 8,
      minute: 15,
      enabled: true,
    );

    await notifier.saveAlarm(alarm);
    expect(notifier.state.any((item) => item.id == alarm.id), isTrue);

    await notifier.deleteAlarm(alarm.id);
    expect(notifier.state.any((item) => item.id == alarm.id), isFalse);
    notifier.dispose();
  });

  test('legacy alarm records are migrated to WakeWise storage', () {
    final saved = HiveService.readObject('alarms') as List;
    final legacy = Alarm.fromMap(saved.single as Map);
    expect(legacy.id, 'old-alarm');
    expect(legacy.label, 'Legacy alarm');
    expect(legacy.repeatDays, [1, 3, 5]);
    expect(legacy.challenge, WakeChallenge.none);
  });
}
