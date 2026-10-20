import 'package:intl/intl.dart';

/// An amount of Indian Rupees stored as integer paise, so totals never drift
/// because of floating point rounding.
class Money implements Comparable<Money> {
  const Money(this.paise);

  const Money.rupees(int rupees) : paise = rupees * 100;

  static const zero = Money(0);

  final int paise;

  bool get isZero => paise == 0;

  Money operator +(Money other) => Money(paise + other.paise);

  Money operator -(Money other) => Money(paise - other.paise);

  Money operator *(int factor) => Money(paise * factor);

  /// Applies a rate expressed in basis points (500 = 5%), rounding half-up to
  /// the nearest paisa.
  Money applyRate(int basisPoints) {
    final scaled = paise * basisPoints;
    final rounded = scaled >= 0
        ? (scaled + 5000) ~/ 10000
        : -((-scaled + 5000) ~/ 10000);
    return Money(rounded);
  }

  static Money sum(Iterable<Money> values) =>
      values.fold(Money.zero, (total, value) => total + value);

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => CurrencyFormatter.format(this);
}

/// The single place where amounts are turned into text.
abstract final class CurrencyFormatter {
  static final NumberFormat _whole = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final NumberFormat _fractional = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// `₹180`, `₹1,250` or `₹472.50` (decimals only when there are paise).
  static String format(Money amount) {
    if (amount.paise % 100 == 0) {
      return _whole.format(amount.paise ~/ 100);
    }
    return _fractional.format(amount.paise / 100);
  }

  /// `+₹40`, used for add-on and portion surcharges.
  static String formatExtra(Money amount) => '+${format(amount)}';
}
