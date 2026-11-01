/// Default day boundary: 03:00 local time.
const int defaultDayBoundaryMinutes = 180;
const int maxDayBoundaryMinutes = 12 * 60;

/// A local calendar date as seen through the habit-day boundary.
///
/// Stored on events as `yyyy-MM-dd`; it never changes when the time zone does.
class HabitDay implements Comparable<HabitDay> {
  HabitDay(int year, int month, int day)
    : this._(DateTime.utc(year, month, day));

  const HabitDay._(this._date);

  /// Midnight UTC of the calendar date; used only for calendar arithmetic.
  final DateTime _date;

  factory HabitDay.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw FormatException('Invalid habit day', value);
    final day = HabitDay(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (day.toString() != value) {
      throw FormatException('Invalid habit day', value);
    }
    return day;
  }

  /// The calendar date of [date], ignoring its time of day.
  factory HabitDay.fromDate(DateTime date) =>
      HabitDay(date.year, date.month, date.day);

  int get year => _date.year;
  int get month => _date.month;
  int get day => _date.day;

  /// [DateTime.monday] (1) to [DateTime.sunday] (7).
  int get weekday => _date.weekday;

  HabitDay addDays(int days) =>
      HabitDay._(DateTime.utc(_date.year, _date.month, _date.day + days));

  /// Local midnight of this date.
  DateTime toLocalDate() => DateTime(year, month, day);

  @override
  int compareTo(HabitDay other) => _date.compareTo(other._date);

  bool operator <(HabitDay other) => compareTo(other) < 0;
  bool operator >(HabitDay other) => compareTo(other) > 0;
  bool operator <=(HabitDay other) => compareTo(other) <= 0;
  bool operator >=(HabitDay other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is HabitDay && other._date == _date;

  @override
  int get hashCode => _date.hashCode;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// The habit day that [instant] falls in.
///
/// The wall-clock reading at [utcOffset] (default: the device's current local
/// offset for that instant) is shifted back by [boundaryMinutes], so with the
/// default 03:00 boundary 02:59 still belongs to the previous day. The shift is
/// done on the wall-clock reading, so DST changes cannot skip or repeat a day.
HabitDay habitDayFor(
  DateTime instant, {
  int boundaryMinutes = defaultDayBoundaryMinutes,
  Duration? utcOffset,
}) {
  if (boundaryMinutes < 0 || boundaryMinutes > maxDayBoundaryMinutes) {
    throw RangeError.range(
      boundaryMinutes,
      0,
      maxDayBoundaryMinutes,
      'boundaryMinutes',
    );
  }
  final utc = instant.toUtc();
  final offset = utcOffset ?? instant.toLocal().timeZoneOffset;
  final wallClock = utc
      .add(offset)
      .subtract(Duration(minutes: boundaryMinutes));
  return HabitDay(wallClock.year, wallClock.month, wallClock.day);
}
