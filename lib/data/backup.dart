import 'dart:convert';

import '../domain/day_state.dart';
import '../domain/event.dart';
import '../domain/habit_day.dart';
import '../domain/hlc.dart';

const backupFormat = 'cohabit-backup';
const backupVersion = 1;

class BackupDocument {
  const BackupDocument({
    required this.exportedAt,
    required this.dayBoundaryMinutes,
    required this.events,
  });
  final DateTime exportedAt;
  final int dayBoundaryMinutes;
  final List<Event> events;

  Map<String, Object?> toJson() => {
    'format': backupFormat,
    'version': backupVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'dayBoundaryMinutes': dayBoundaryMinutes,
    'events': events.map((e) => e.toJson()).toList(),
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static BackupDocument decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic> ||
        root['format'] != backupFormat ||
        root['version'] != backupVersion) {
      throw const FormatException('Unsupported backup format or version');
    }
    final timestamp = root['exportedAt'];
    final boundary = root['dayBoundaryMinutes'];
    final rawEvents = root['events'];
    if (timestamp is! String ||
        boundary is! int ||
        boundary < 0 ||
        boundary > maxDayBoundaryMinutes ||
        rawEvents is! List) {
      throw const FormatException('Invalid backup envelope');
    }
    _validTimestamp(timestamp);
    final exportedAt = DateTime.tryParse(timestamp);
    if (exportedAt == null) throw const FormatException('Invalid exportedAt');
    final events = rawEvents.map((raw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid event');
      }
      return _decodeEvent(raw);
    }).toList();

    return BackupDocument(
      exportedAt: exportedAt,
      dayBoundaryMinutes: boundary,
      events: events,
    );
  }
}

Event _decodeEvent(Map<String, dynamic> raw) {
  if (raw.keys.any(
    (k) => !const {
      'id',
      'deviceId',
      'hlc',
      'schemaVersion',
      'type',
      'payload',
    }.contains(k),
  )) {
    throw const FormatException('Unknown event field');
  }
  final id = raw['id'], device = raw['deviceId'], encodedHlc = raw['hlc'];
  final version = raw['schemaVersion'],
      type = raw['type'],
      payload = raw['payload'];
  if (id is! String ||
      id.isEmpty ||
      device is! String ||
      device.isEmpty ||
      encodedHlc is! String ||
      version is! int ||
      type is! String ||
      payload is! Map<String, dynamic>) {
    throw const FormatException('Invalid event fields');
  }
  final match = RegExp(r'^([0-9a-f]{12})-([0-9a-f]{4})$')
      .firstMatch(encodedHlc);
  if (match == null) throw FormatException('Invalid HLC: $encodedHlc');
  final hlc = Hlc.parse(encodedHlc);
  return Event(
    id: id,
    deviceId: device,
    hlc: hlc,
    schemaVersion: version,
    type: type,
    payload: Map<String, Object?>.from(payload),
  );
}

void validateEvents(
  List<Event> events, {
  Set<String> existingHabitIds = const {},
}) {
  final ids = <String, Event>{};
  final creates = <String>{...existingHabitIds};
  for (final event in events) {
    final old = ids[event.id];
    if (old != null) {
      if (canonicalJson(old.toJson()) != canonicalJson(event.toJson())) {
        throw FormatException('Conflicting duplicate event id ${event.id}');
      }
      continue;
    }
    ids[event.id] = event;
    if (event.schemaVersion != currentSchemaVersion) {
      throw FormatException('Unsupported event version ${event.schemaVersion}');
    }
    if (!EventTypes.habitTypes.contains(event.type) &&
        event.type != EventTypes.dayStateSet) {
      throw FormatException('Unsupported event type ${event.type}');
    }
    final p = event.payload;
    final hid = p['habitId'];
    if (hid is! String || hid.isEmpty) {
      throw FormatException('Invalid habitId in ${event.id}');
    }
    if (event.type == EventTypes.habitCreated) creates.add(hid);
    if (event.type == EventTypes.habitCreated) {
      if (p['name'] is! String ||
          (p['name'] as String).trim().isEmpty ||
          p['createdDay'] is! String ||
          p['createdAt'] is! String) {
        throw FormatException('Invalid habit creation');
      }
      if (p['polarity'] is! String) {
        throw const FormatException('Invalid polarity');
      }
      HabitPolarity.parse(p['polarity'] as String);
      _validDay(p['createdDay'] as String);
      _validTimestamp(p['createdAt'] as String);
      _validSchedule(p['schedule']);
    } else if (event.type == EventTypes.habitEdited) {
      if (p.containsKey('name') &&
          (p['name'] is! String || (p['name'] as String).trim().isEmpty)) {
        throw const FormatException('Invalid habit name');
      }
      if (p.containsKey('schedule')) _validSchedule(p['schedule']);
      if (p.containsKey('effectiveFrom')) {
        if (p['effectiveFrom'] is! String) {
          throw const FormatException('Invalid effectiveFrom');
        }
        _validDay(p['effectiveFrom'] as String);
      }
      if (!p.containsKey('name') && !p.containsKey('schedule')) {
        throw const FormatException('Empty habit edit');
      }
    } else if (event.type == EventTypes.habitArchived) {
      if (p['archivedAt'] is! String) {
        throw const FormatException('Invalid archivedAt');
      }
      _validTimestamp(p['archivedAt'] as String);
    } else {
      if (p['habitDay'] is! String ||
          p['state'] is! String ||
          p['loggedAt'] is! String) {
        throw const FormatException('Invalid day state');
      }
      _validDay(p['habitDay'] as String);
      _validTimestamp(p['loggedAt'] as String);
      DayState.parse(p['state'] as String);
      if (p.containsKey('source')) {
        if (p['source'] is! String) {
          throw const FormatException('Invalid source');
        }
        EventSource.parse(p['source'] as String);
      }
    }
  }
  for (final event in events) {
    if (event.type != EventTypes.habitCreated &&
        !creates.contains(event.habitId)) {
      throw FormatException('Missing habit reference ${event.habitId}');
    }
  }
}

void _validDay(String value) {
  HabitDay.parse(value);
}

void _validTimestamp(String value) {
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (m == null) throw FormatException('Invalid timestamp $value');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  final d = DateTime.utc(parts[0], parts[1], parts[2]);
  final zone = m[7]!;
  if (d.year != parts[0] ||
      d.month != parts[1] ||
      d.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59 ||
      (zone != 'Z' &&
          (int.parse(zone.substring(1, 3)) > 23 ||
              int.parse(zone.substring(4)) > 59))) {
    throw FormatException('Invalid timestamp $value');
  }
}

void _validSchedule(Object? value) {
  if (value is! List ||
      value.isEmpty ||
      value.any((d) => d is! int || d < 1 || d > 7) ||
      value.toSet().length != value.length) {
    throw const FormatException('Invalid weekday schedule');
  }
}

String _csv(String value, {required bool formulaSafe}) {
  if (formulaSafe && RegExp(r'^\s*[=+\-@]').hasMatch(value)) value = "'$value";
  return '"${value.replaceAll('"', '""')}"';
}

String csvCell(String value) => _csv(value, formulaSafe: true);
String canonicalJson(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return v.map(canonical).toList();
    return v;
  }

  return jsonEncode(canonical(value));
}
