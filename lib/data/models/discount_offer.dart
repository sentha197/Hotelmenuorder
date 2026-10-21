import '../../core/utils/currency.dart';

enum DiscountType {
  percent('Percentage'),
  flat('Flat amount');

  const DiscountType(this.label);

  final String label;
}

enum OfferError {
  unknownCode('That code is not valid.'),
  inactive('This offer is not active right now.'),
  belowMinimum('Add a little more to use this offer.');

  const OfferError(this.message);

  final String message;
}

/// A coupon configured by the restaurant, e.g. 10% off orders above ₹300,
/// capped at ₹100.
class DiscountOffer {
  const DiscountOffer({
    required this.code,
    required this.title,
    required this.type,
    required this.value,
    this.minSubtotal = Money.zero,
    this.maxDiscount,
    this.isActive = true,
  });

  factory DiscountOffer.fromJson(Map<String, dynamic> json) => DiscountOffer(
    code: json['code'] as String,
    title: json['title'] as String? ?? '',
    type: json['type'] == 'flat' ? DiscountType.flat : DiscountType.percent,
    value: json['value'] as int,
    minSubtotal: Money(json['min'] as int? ?? 0),
    maxDiscount: json['max'] == null ? null : Money(json['max'] as int),
    isActive: json['active'] as bool? ?? true,
  );

  /// Upper-case code the guest types, e.g. `WELCOME10`.
  final String code;
  final String title;
  final DiscountType type;

  /// Basis points for [DiscountType.percent], paise for [DiscountType.flat].
  final int value;
  final Money minSubtotal;
  final Money? maxDiscount;
  final bool isActive;

  static final RegExp _codePattern = RegExp(r'^[A-Z0-9]{3,16}$');

  static String normalize(String code) => code.trim().toUpperCase();

  static bool isValidCode(String code) =>
      _codePattern.hasMatch(normalize(code));

  /// `10% off` or `₹75 off`.
  String get benefit => type == DiscountType.percent
      ? '${_percent(value)} off'
      : '${CurrencyFormatter.format(Money(value))} off';

  /// Short description, e.g. `10% off · min ₹300 · up to ₹100`.
  String get summary {
    return [
      benefit,
      if (!minSubtotal.isZero) 'min ${CurrencyFormatter.format(minSubtotal)}',
      if (maxDiscount != null)
        'up to ${CurrencyFormatter.format(maxDiscount!)}',
    ].join(' · ');
  }

  static String _percent(int basisPoints) {
    final percent = basisPoints / 100;
    return percent == percent.roundToDouble()
        ? '${percent.toStringAsFixed(0)}%'
        : '${percent.toStringAsFixed(1)}%';
  }

  /// Returns null when the offer applies to [subtotal].
  OfferError? check(Money subtotal) {
    if (!isActive) return OfferError.inactive;
    if (subtotal.compareTo(minSubtotal) < 0) return OfferError.belowMinimum;
    return null;
  }

  /// The discount for [subtotal] (zero when the offer does not apply). Never
  /// more than the subtotal.
  Money discountFor(Money subtotal) {
    if (check(subtotal) != null) return Money.zero;
    var amount = type == DiscountType.percent
        ? subtotal.applyRate(value)
        : Money(value);
    final cap = maxDiscount;
    if (cap != null && amount.compareTo(cap) > 0) amount = cap;
    if (amount.compareTo(subtotal) > 0) amount = subtotal;
    return amount;
  }

  /// How much more the guest must add before the offer applies.
  Money shortfall(Money subtotal) {
    final missing = minSubtotal - subtotal;
    return missing.paise > 0 ? missing : Money.zero;
  }

  DiscountOffer copyWith({bool? isActive}) => DiscountOffer(
    code: code,
    title: title,
    type: type,
    value: value,
    minSubtotal: minSubtotal,
    maxDiscount: maxDiscount,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'title': title,
    'type': type.name,
    'value': value,
    if (!minSubtotal.isZero) 'min': minSubtotal.paise,
    if (maxDiscount != null) 'max': maxDiscount!.paise,
    'active': isActive,
  };
}
