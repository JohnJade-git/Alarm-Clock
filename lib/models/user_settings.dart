import 'package:flutter/material.dart';

class UserSettings {
  const UserSettings({
    this.themeMode = ThemeMode.system,
    this.use24Hour = false,
    this.onboardingComplete = false,
  });

  final ThemeMode themeMode;
  final bool use24Hour;
  final bool onboardingComplete;

  UserSettings copyWith({
    ThemeMode? themeMode,
    bool? use24Hour,
    bool? onboardingComplete,
  }) {
    return UserSettings(
      themeMode: themeMode ?? this.themeMode,
      use24Hour: use24Hour ?? this.use24Hour,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  Map<String, Object?> toMap() => {
    'themeMode': themeMode.name,
    'use24Hour': use24Hour,
    'onboardingComplete': onboardingComplete,
  };

  factory UserSettings.fromMap(Map<dynamic, dynamic> map) {
    final themeMode = switch (map['themeMode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return UserSettings(
      themeMode: themeMode,
      use24Hour: map['use24Hour'] as bool? ?? false,
      onboardingComplete: map['onboardingComplete'] as bool? ?? false,
    );
  }
}
