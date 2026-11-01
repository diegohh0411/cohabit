import 'dart:convert';

import 'day_state.dart';
import 'habit_day.dart';
import 'hlc.dart';

abstract final class EventTypes {
  static const habitCreated = 'HabitCreated';
  static const habitEdited = 'HabitEdited';
  static const habitArchived = 'HabitArchived';
  static const dayStateSet = 'DayStateSet';

  static const habitTypes = {habitCreated, habitEdited, habitArchived};
}

/// Highest payload version this build understands.
const int currentSchemaVersion = 1;

/// An immutable entry in the append-only event log.
class Event {
  const Event({
    required this.id,
    required this.deviceId,
    required this.hlc,
    required this.type,
    required this.payload,
    this.schemaVersion = currentSchemaVersion,
  });

  final String id;
  final String deviceId;
  final Hlc hlc;
  final int schemaVersion;
  final String type;
  final Map<String, Object?> payload;

  /// `habitId` for every habit and day-state event.
  String? get habitId => payload['habitId'] as String?;

  /// `habitDay` for `DayStateSet`.
  HabitDay? get habitDay {
    final raw = payload['habitDay'] as String?;
    return raw == null ? null : HabitDay.parse(raw);
  }

  /// `source` for `DayStateSet`; events without one count as manual.
  EventSource get source => payload['source'] == null
      ? EventSource.manual
      : EventSource.parse(payload['source']! as String);

  DayState? get dayState => payload['state'] == null
      ? null
      : DayState.parse(payload['state']! as String);

  Map<String, Object?> toJson() => {
    'id': id,
    'deviceId': deviceId,
    'hlc': hlc.encoded,
    'schemaVersion': schemaVersion,
    'type': type,
    'payload': payload,
  };

  factory Event.fromJson(Map<String, Object?> json) => Event(
    id: json['id']! as String,
    deviceId: json['deviceId']! as String,
    hlc: Hlc.parse(json['hlc']! as String),
    schemaVersion: json['schemaVersion']! as int,
    type: json['type']! as String,
    payload: Map<String, Object?>.from(json['payload']! as Map),
  );

  String get payloadJson => jsonEncode(payload);

  @override
  String toString() => 'Event($type $id @$hlc by $deviceId)';
}
