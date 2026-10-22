import '../utils/currency.dart';

/// Pricing rules configured by the restaurant.
class PricingConfig {
  const PricingConfig({
    this.taxRateBasisPoints = 500,
    this.taxName = 'Taxes',
    this.serviceChargeBasisPoints = 0,
  });

  /// Tax rate in basis points (500 = 5%).
  final int taxRateBasisPoints;

  /// What the tax is called on bills (e.g. "GST").
  final String taxName;

  /// Optional service charge in basis points (0 = none).
  final int serviceChargeBasisPoints;

  String get taxLabel => '$taxName (${formatRate(taxRateBasisPoints)})';

  String get serviceChargeLabel =>
      'Service charge (${formatRate(serviceChargeBasisPoints)})';

  /// `5%`, `2.5%`
  static String formatRate(int basisPoints) {
    final percent = basisPoints / 100;
    final text = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '$text%';
  }
}

/// The amounts of one bill, computed with one shared formula everywhere
/// (cart, order summary, stored orders, invoices, reports):
///
/// ```
/// discount      = min(discount, subtotal)
/// service       = (subtotal − discount) × service rate
/// taxable       = subtotal − discount + service
/// tax           = taxable × tax rate      (each rounded half-up to the paisa)
/// total         = taxable + tax
/// ```
class BillBreakdown {
  const BillBreakdown({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.taxRateBasisPoints,
    this.discount = Money.zero,
    this.discountLabel,
    this.serviceCharge = Money.zero,
    this.serviceChargeBasisPoints = 0,
    this.taxName = 'Taxes',
  });

  factory BillBreakdown.fromSubtotal(
    Money subtotal,
    PricingConfig config, {
    Money discount = Money.zero,
    String? discountLabel,
  }) {
    final applied = discount.paise <= 0
        ? Money.zero
        : (discount.paise > subtotal.paise ? subtotal : discount);
    final afterDiscount = subtotal - applied;
    final service = afterDiscount.applyRate(config.serviceChargeBasisPoints);
    final taxable = afterDiscount + service;
    final tax = taxable.applyRate(config.taxRateBasisPoints);
    return BillBreakdown(
      subtotal: subtotal,
      discount: applied,
      discountLabel: applied.isZero ? null : discountLabel,
      serviceCharge: service,
      serviceChargeBasisPoints: config.serviceChargeBasisPoints,
      tax: tax,
      total: taxable + tax,
      taxRateBasisPoints: config.taxRateBasisPoints,
      taxName: config.taxName,
    );
  }

  factory BillBreakdown.fromJson(Map<String, dynamic> json) => BillBreakdown(
    subtotal: Money(json['subtotal'] as int),
    discount: Money(json['discount'] as int? ?? 0),
    discountLabel: json['discountLabel'] as String?,
    serviceCharge: Money(json['service'] as int? ?? 0),
    serviceChargeBasisPoints: json['serviceRate'] as int? ?? 0,
    tax: Money(json['tax'] as int),
    total: Money(json['total'] as int),
    taxRateBasisPoints: json['taxRate'] as int,
    taxName: json['taxName'] as String? ?? 'Taxes',
  );

  static const empty = BillBreakdown(
    subtotal: Money.zero,
    tax: Money.zero,
    total: Money.zero,
    taxRateBasisPoints: 0,
  );

  final Money subtotal;
  final Money discount;
  final String? discountLabel;
  final Money serviceCharge;
  final int serviceChargeBasisPoints;
  final Money tax;
  final Money total;
  final int taxRateBasisPoints;
  final String taxName;

  /// Amount the tax was calculated on.
  Money get taxableAmount => subtotal - discount + serviceCharge;

  bool get hasDiscount => !discount.isZero;

  bool get hasServiceCharge => !serviceCharge.isZero;

  String get taxLabel => PricingConfig(
    taxRateBasisPoints: taxRateBasisPoints,
    taxName: taxName,
  ).taxLabel;

  String get serviceChargeLabel => PricingConfig(
    serviceChargeBasisPoints: serviceChargeBasisPoints,
  ).serviceChargeLabel;

  /// Keys match the fields stored on orders before discounts existed, so old
  /// data still reads correctly.
  Map<String, dynamic> toJson() => {
    'subtotal': subtotal.paise,
    if (hasDiscount) 'discount': discount.paise,
    if (discountLabel != null) 'discountLabel': discountLabel,
    if (hasServiceCharge) 'service': serviceCharge.paise,
    if (serviceChargeBasisPoints != 0) 'serviceRate': serviceChargeBasisPoints,
    'tax': tax.paise,
    'total': total.paise,
    'taxRate': taxRateBasisPoints,
    if (taxName != 'Taxes') 'taxName': taxName,
  };
}
