import 'package:intl/intl.dart';

abstract final class AppFormat {
  static final DateFormat _time = DateFormat('h:mm a');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final DateFormat _date = DateFormat('d MMM yyyy');

  /// `12:30 PM`
  static String time(DateTime value) => _time.format(value);

  /// `17 Oct 2026, 12:30 PM`
  static String dateTime(DateTime value) => _dateTime.format(value);

  /// `17 Oct 2026`
  static String date(DateTime value) => _date.format(value);

  /// Table numbers are always shown with two digits: `05`.
  static String table(int number) => number.toString().padLeft(2, '0');

  /// `#OD12345`
  static String orderNumber(String id) => '#$id';

  /// `1 item`, `3 items`
  static String itemCount(int count) => count == 1 ? '1 item' : '$count items';
}
