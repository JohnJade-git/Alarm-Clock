import 'package:hive_flutter/hive_flutter.dart';

import '../models/alarm.dart';

class HiveService {
  static Box<dynamic>? _box;
  static Box<dynamic>? _legacyAlarmsBox;

  static Future<void> initialize() async {
    if (_box?.isOpen == true) return;
    _box = await Hive.openBox<dynamic>('wakewise_data');
    _legacyAlarmsBox = await Hive.openBox<dynamic>('alarms');
    if (!_box!.containsKey('alarms') && _legacyAlarmsBox!.isNotEmpty) {
      final alarms = _legacyAlarmsBox!.values
          .whereType<Map>()
          .map(Alarm.fromMap)
          .where((alarm) => alarm.id.isNotEmpty)
          .toList();
      await _box!.put(
        'alarms',
        alarms.map((alarm) => alarm.toMap()).toList(),
      );
    }
  }

  static Box<dynamic> get box {
    if (_box == null) {
      throw StateError('HiveService has not been initialized.');
    }
    return _box!;
  }

  static Future<void> saveObject(String key, dynamic value) async {
    await box.put(key, value);
  }

  static dynamic readObject(String key) => box.get(key);

  static Future<void> deleteObject(String key) async {
    await box.delete(key);
  }

  static Future<void> close() async {
    await _box?.close();
    await _legacyAlarmsBox?.close();
    _box = null;
    _legacyAlarmsBox = null;
  }
}
