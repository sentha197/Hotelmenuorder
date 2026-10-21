import 'dart:math' as math;

/// The restaurant's time zone, as a fixed offset from UTC. Every date shown
/// or grouped (bills, reports, kitchen timers) goes through here so all
/// screens agree on what "today" means.
abstract final class RestaurantTime {
  static Duration _offset = DateTime.now().timeZoneOffset;

  static Duration get offset => _offset;

  static void configure(int utcOffsetMinutes) =>
      _offset = Duration(minutes: utcOffsetMinutes);

  /// Device offset, used as the default for a fresh install.
  static int get deviceOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  /// [instant] as wall-clock fields in restaurant time. The result is a UTC
  /// `DateTime` used only for its fields (year, hour, …) when formatting.
  static DateTime wall(DateTime instant) => instant.toUtc().add(_offset);

  /// The instant at which the restaurant day containing [instant] starts.
  static DateTime startOfDay(DateTime instant) {
    final w = wall(instant);
    return dayStart(w.year, w.month, w.day);
  }

  /// Instant of midnight (restaurant time) on the given calendar day.
  static DateTime dayStart(int year, int month, int day) =>
      DateTime.utc(year, month, day).subtract(_offset);
}

enum RangePreset {
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 days'),
  last30('Last 30 days'),
  custom('Custom');

  const RangePreset(this.label);

  final String label;
}

/// A half-open time range `[start, end)` aligned to restaurant days.
class DateRange {
  const DateRange(this.start, this.end, {this.preset = RangePreset.custom});

  /// Range for a preset, relative to [now].
  factory DateRange.preset(RangePreset preset, DateTime now) {
    final today = RestaurantTime.startOfDay(now);
    const day = Duration(days: 1);
    return switch (preset) {
      RangePreset.today => DateRange(today, today.add(day), preset: preset),
      RangePreset.yesterday => DateRange(
        today.subtract(day),
        today,
        preset: preset,
      ),
      RangePreset.last7 => DateRange(
        today.subtract(const Duration(days: 6)),
        today.add(day),
        preset: preset,
      ),
      RangePreset.last30 => DateRange(
        today.subtract(const Duration(days: 29)),
        today.add(day),
        preset: preset,
      ),
      RangePreset.custom => DateRange(today, today.add(day), preset: preset),
    };
  }

  /// Whole restaurant days from [first] to [last] (inclusive). Only the
  /// calendar date of each argument is used, as returned by date pickers.
  factory DateRange.days(DateTime first, DateTime last) {
    final a = RestaurantTime.dayStart(first.year, first.month, first.day);
    final b = RestaurantTime.dayStart(last.year, last.month, last.day);
    final start = a.isAfter(b) ? b : a;
    final end = (a.isAfter(b) ? a : b).add(const Duration(days: 1));
    return DateRange(start, end);
  }

  final DateTime start;
  final DateTime end;
  final RangePreset preset;

  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(end);

  int get dayCount => math.max(1, (end.difference(start).inHours / 24).round());

  /// Start instant of each restaurant day in the range.
  List<DateTime> get dayStarts => [
    for (var i = 0; i < dayCount; i++) start.add(Duration(days: i)),
  ];

  /// The range of the same length immediately before this one.
  DateRange get previous =>
      DateRange(start.subtract(end.difference(start)), start);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Human-friendly and sequential identifiers.
abstract final class Ids {
  static final math.Random _random = math.Random.secure();
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Next id after the highest numbered one in [existing], e.g. `PAY000042`.
  static String sequential(
    String prefix,
    Iterable<String> existing, {
    int width = 6,
    int first = 1,
  }) {
    var highest = first - 1;
    for (final id in existing) {
      if (!id.startsWith(prefix)) continue;
      final number = int.tryParse(id.substring(prefix.length));
      if (number != null) highest = math.max(highest, number);
    }
    return '$prefix${(highest + 1).toString().padLeft(width, '0')}';
  }

  /// Random, unambiguous token (idempotency keys, simulated references).
  static String random([int length = 16]) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);
}
