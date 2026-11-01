/// Hybrid logical clock (Kulkarni et al.). A timestamp is a wall-clock
/// millisecond reading plus a counter that orders events sharing a reading.
///
/// The encoded form is fixed-width lowercase hex (`wwwwwwwwwwww-cccc`), so
/// timestamps also sort correctly as plain strings.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.wallMillis, this.counter);

  static const int maxCounter = 0xFFFF;
  static const Hlc zero = Hlc(0, 0);

  final int wallMillis;
  final int counter;

  factory Hlc.parse(String encoded) {
    final parts = encoded.split('-');
    if (parts.length != 2) {
      throw FormatException('Invalid HLC', encoded);
    }
    final wall = int.tryParse(parts[0], radix: 16);
    final counter = int.tryParse(parts[1], radix: 16);
    if (wall == null || counter == null || wall < 0 || counter < 0) {
      throw FormatException('Invalid HLC', encoded);
    }
    return Hlc(wall, counter);
  }

  String get encoded =>
      '${wallMillis.toRadixString(16).padLeft(12, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}';

  @override
  int compareTo(Hlc other) {
    final byWall = wallMillis.compareTo(other.wallMillis);
    return byWall != 0 ? byWall : counter.compareTo(other.counter);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMillis == wallMillis &&
      other.counter == counter;

  @override
  int get hashCode => Object.hash(wallMillis, counter);

  @override
  String toString() => encoded;
}

class ClockDriftException implements Exception {
  ClockDriftException(this.remote, this.localMillis);
  final Hlc remote;
  final int localMillis;

  @override
  String toString() =>
      'ClockDriftException: remote $remote is too far ahead of local '
      'time $localMillis';
}

/// Generates monotonically increasing [Hlc] values for one device.
class HlcClock {
  HlcClock({
    int Function()? nowMillis,
    Hlc? initial,
    this.maxDrift = const Duration(minutes: 5),
  }) : _nowMillis = nowMillis ?? _systemNow,
       _latest = initial ?? Hlc.zero;

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _nowMillis;
  final Duration maxDrift;
  Hlc _latest;

  Hlc get latest => _latest;

  /// Timestamp for a local event.
  Hlc send() {
    final now = _nowMillis();
    final wall = now > _latest.wallMillis ? now : _latest.wallMillis;
    final counter = wall == _latest.wallMillis ? _latest.counter + 1 : 0;
    return _latest = _normalise(wall, counter);
  }

  /// Merge a timestamp seen on another device, keeping the clock ahead of it.
  Hlc receive(Hlc remote) {
    final now = _nowMillis();
    if (remote.wallMillis - now > maxDrift.inMilliseconds) {
      throw ClockDriftException(remote, now);
    }
    var wall = now;
    if (_latest.wallMillis > wall) wall = _latest.wallMillis;
    if (remote.wallMillis > wall) wall = remote.wallMillis;

    final int counter;
    if (wall == _latest.wallMillis && wall == remote.wallMillis) {
      counter =
          (_latest.counter > remote.counter
              ? _latest.counter
              : remote.counter) +
          1;
    } else if (wall == _latest.wallMillis) {
      counter = _latest.counter + 1;
    } else if (wall == remote.wallMillis) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    return _latest = _normalise(wall, counter);
  }

  /// On counter overflow, borrow one millisecond from the future.
  Hlc _normalise(int wall, int counter) =>
      counter > Hlc.maxCounter ? Hlc(wall + 1, 0) : Hlc(wall, counter);
}
