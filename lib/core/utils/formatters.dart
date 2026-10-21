import 'package:intl/intl.dart';

import 'restaurant_time.dart';

/// The single place where dates, times and identifiers become text. Dates
/// are shown in restaurant time (see [RestaurantTime]).
abstract final class AppFormat {
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _shortDate = DateFormat('d MMM');
  static final DateFormat _weekday = DateFormat('EEE');
  static final DateFormat _fileStamp = DateFormat('yyyyMMdd');

  /// `12:30 PM`
  static String time(DateTime value) =>
      _time.format(RestaurantTime.wall(value));

  /// `17 Oct 2026, 12:30 PM`
  static String dateTime(DateTime value) =>
      _dateTime.format(RestaurantTime.wall(value));

  /// `17 Oct 2026`
  static String date(DateTime value) =>
      _date.format(RestaurantTime.wall(value));

  /// `17 Oct`
  static String shortDate(DateTime value) =>
      _shortDate.format(RestaurantTime.wall(value));

  /// `Sat`
  static String weekday(DateTime value) =>
      _weekday.format(RestaurantTime.wall(value));

  /// `20261017`, for export file names.
  static String fileStamp(DateTime value) =>
      _fileStamp.format(RestaurantTime.wall(value));

  /// `17 Oct – 23 Oct 2026` (end is exclusive).
  static String range(DateRange range) {
    final last = range.end.subtract(const Duration(milliseconds: 1));
    if (range.dayCount == 1) return date(range.start);
    return '${shortDate(range.start)} – ${date(last)}';
  }

  /// Table numbers are always shown with two digits: `05`.
  static String table(int number) => number.toString().padLeft(2, '0');

  /// `#OD12345`
  static String orderNumber(String id) => '#$id';

  /// `1 item`, `3 items`
  static String itemCount(int count) => count == 1 ? '1 item' : '$count items';

  /// `5 min`, `1 h 05 min`
  static String minutes(int value) {
    if (value < 60) return '$value min';
    return '${value ~/ 60} h ${(value % 60).toString().padLeft(2, '0')} min';
  }
}
