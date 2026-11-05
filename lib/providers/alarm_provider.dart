import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm.dart';
import '../services/hive_service.dart';

class AlarmNotifier extends StateNotifier<List<Alarm>> {
  AlarmNotifier() : super(_loadFromStorage());

  static List<Alarm> _loadFromStorage() {
    final data = HiveService.readObject('alarms');
    if (data is List) {
      return data
          .whereType<Map>()
          .map(Alarm.fromMap)
          .where((alarm) => alarm.id.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<void> saveAlarm(Alarm alarm) async {
    final existing = [...state];
    final index = existing.indexWhere((item) => item.id == alarm.id);
    if (index >= 0) {
      existing[index] = alarm;
    } else {
      existing.add(alarm);
    }
    await HiveService.saveObject(
      'alarms',
      existing.map((item) => item.toMap()).toList(),
    );
    state = existing;
  }

  Future<void> deleteAlarm(String id) async {
    final next = state.where((item) => item.id != id).toList();
    await HiveService.saveObject(
      'alarms',
      next.map((item) => item.toMap()).toList(),
    );
    state = next;
  }
}

final alarmProvider = StateNotifierProvider<AlarmNotifier, List<Alarm>>(
  (_) => AlarmNotifier(),
);
