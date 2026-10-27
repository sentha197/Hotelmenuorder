import 'package:intl/intl.dart';

/// An amount in the restaurant's currency stored as integer minor units
/// ("paise"), so totals never drift because of floating point rounding.
/// Every supported currency has two decimal places.
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

/// A currency a restaurant can bill in.
class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name, this.locale);

  /// ISO 4217 code, e.g. `INR`.
  final String code;
  final String symbol;
  final String name;

  /// Digit grouping: `en_IN` writes 1,00,000; `en_US` writes 100,000.
  final String locale;

  /// `Indian Rupee (₹ INR)`
  String get label => '$name (${symbol.trim()} $code)';
}

/// The single place where amounts are turned into text, in the currency the
/// restaurant configured (set from its settings, like the time zone).
abstract final class CurrencyFormatter {
  static const supported = [
    CurrencyInfo('INR', '₹', 'Indian Rupee', 'en_IN'),
    CurrencyInfo('USD', r'$', 'US Dollar', 'en_US'),
    CurrencyInfo('EUR', '€', 'Euro', 'en_US'),
    CurrencyInfo('GBP', '£', 'British Pound', 'en_GB'),
    CurrencyInfo('AED', 'AED ', 'UAE Dirham', 'en_US'),
    CurrencyInfo('SGD', r'S$', 'Singapore Dollar', 'en_US'),
  ];

  static CurrencyInfo _currency = supported.first;
  static late NumberFormat _whole;
  static late NumberFormat _fractional;
  static bool _ready = false;

  static CurrencyInfo? lookup(String code) =>
      supported.where((c) => c.code == code).firstOrNull;

  /// Switches every amount shown to [code]. Unknown codes are ignored.
  static void configure(String code) {
    final currency = lookup(code);
    if (currency == null || (_ready && currency == _currency)) return;
    _currency = currency;
    _whole = NumberFormat.currency(
      locale: currency.locale,
      symbol: currency.symbol,
      decimalDigits: 0,
    );
    _fractional = NumberFormat.currency(
      locale: currency.locale,
      symbol: currency.symbol,
      decimalDigits: 2,
    );
    _ready = true;
  }

  static CurrencyInfo get currency {
    if (!_ready) configure(_currency.code);
    return _currency;
  }

  /// ISO code of the configured currency, e.g. `INR`.
  static String get code => currency.code;

  /// `₹`, for amount fields (`prefixText`).
  static String get symbol => currency.symbol.trim();

  /// `₹180`, `₹1,250` or `₹472.50` (decimals only when there are paise).
  static String format(Money amount) {
    if (!_ready) configure(_currency.code);
    if (amount.paise % 100 == 0) {
      return _whole.format(amount.paise ~/ 100);
    }
    return _fractional.format(amount.paise / 100);
  }

  /// `+₹40`, used for add-on and portion surcharges.
  static String formatExtra(Money amount) => '+${format(amount)}';

  /// `472.50` or `180`: an amount as typed into a field, without symbol.
  static String plain(Money amount) => amount.paise % 100 == 0
      ? '${amount.paise ~/ 100}'
      : (amount.paise / 100).toStringAsFixed(2);
}
