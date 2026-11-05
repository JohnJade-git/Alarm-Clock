import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_settings.dart';
import '../services/hive_service.dart';

class SettingsNotifier extends StateNotifier<UserSettings> {
  SettingsNotifier() : super(UserSettings()) {
    _load();
  }

  Future<void> _load() async {
    final data = HiveService.readObject('settings');
    if (data is Map) {
      state = UserSettings.fromMap(Map<String, dynamic>.from(data));
    }
  }

  Future<void> update(UserSettings settings) async {
    state = settings;
    await HiveService.saveObject('settings', settings.toMap());
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, UserSettings>(
  (_) => SettingsNotifier(),
);
