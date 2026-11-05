enum WakeChallenge { none, shake, walk }

class Alarm {
  const Alarm({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    this.enabled = true,
    this.repeatDays = const [],
    this.snoozeMinutes = 5,
    this.challenge = WakeChallenge.none,
  });

  final String id;
  final String label;
  final int hour;
  final int minute;
  final bool enabled;

  /// ISO weekdays: Monday is 1 and Sunday is 7. Empty means one-time.
  final List<int> repeatDays;
  final int snoozeMinutes;
  final WakeChallenge challenge;

  Alarm copyWith({
    String? label,
    int? hour,
    int? minute,
    bool? enabled,
    List<int>? repeatDays,
    int? snoozeMinutes,
    WakeChallenge? challenge,
  }) {
    return Alarm(
      id: id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      repeatDays: repeatDays ?? this.repeatDays,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      challenge: challenge ?? this.challenge,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
    'repeatDays': repeatDays,
    'snoozeMinutes': snoozeMinutes,
    'challenge': challenge.name,
  };

  factory Alarm.fromMap(Map<dynamic, dynamic> map) {
    // Older WakeWise releases saved string alarm IDs plus optional features.
    final oldId = map['id'];
    return Alarm(
      id: oldId?.toString() ?? '',
      label: map['label'] as String? ?? 'Wake up',
      hour: (map['hour'] as num?)?.toInt() ?? 7,
      minute: (map['minute'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] as bool? ?? true,
      repeatDays:
          (map['repeatDays'] as List? ?? const [])
              .whereType<num>()
              .map((day) => day.toInt())
              .where((day) => day >= 1 && day <= 7)
              .toSet()
              .toList()
            ..sort(),
      snoozeMinutes: (map['snoozeMinutes'] as num?)?.toInt() ?? 5,
      challenge: WakeChallenge.values.firstWhere(
        (challenge) => challenge.name == map['challenge'],
        orElse: () => WakeChallenge.none,
      ),
    );
  }
}
