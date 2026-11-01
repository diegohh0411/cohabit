enum DayState {
  done('done'),
  notDone('notDone'),
  skipped('skipped'),
  unknown('unknown');

  const DayState(this.wireName);
  final String wireName;

  /// Whether the state counts in analysis (`done` and `notDone` only).
  bool get usedInAnalysis => this == done || this == notDone;

  static DayState parse(String name) => DayState.values.firstWhere(
    (s) => s.wireName == name,
    orElse: () => throw FormatException('Unknown day state', name),
  );
}

enum HabitPolarity {
  positive('positive'),
  negative('negative');

  const HabitPolarity(this.wireName);
  final String wireName;

  static HabitPolarity parse(String name) => HabitPolarity.values.firstWhere(
    (p) => p.wireName == name,
    orElse: () => throw FormatException('Unknown polarity', name),
  );
}

enum EventSource {
  manual('manual'),
  import('import'),
  healthConnect('healthConnect');

  const EventSource(this.wireName);
  final String wireName;

  bool get isAutomatic => this != manual;

  static EventSource parse(String name) => EventSource.values.firstWhere(
    (s) => s.wireName == name,
    orElse: () => throw FormatException('Unknown source', name),
  );
}
