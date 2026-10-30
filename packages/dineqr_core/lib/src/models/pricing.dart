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

/// What kind of saving a [DiscountLine] is.
enum DiscountKind {
  /// A special offer on dishes (no code needed).
  special,

  /// A combo's saving over its dishes bought separately.
  combo,

  /// The coupon the guest entered.
  coupon;

  static DiscountKind parse(Object? name) => DiscountKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => DiscountKind.special,
  );
}

/// One saving on a bill, e.g. `Snack hour −₹55` or `Offer WELCOME10 −₹30`.
/// [ref] is the promotion id or the coupon code.
class DiscountLine {
  const DiscountLine({
    required this.kind,
    required this.label,
    required this.amount,
    this.ref,
  });

  factory DiscountLine.fromJson(Map<String, dynamic> json) => DiscountLine(
    kind: DiscountKind.parse(json['kind']),
    label: json['label'] as String? ?? '',
    amount: Money(json['amount'] as int? ?? 0),
    ref: json['ref'] as String?,
  );

  final DiscountKind kind;
  final String label;
  final Money amount;
  final String? ref;

  DiscountLine plus(Money more) =>
      DiscountLine(kind: kind, label: label, amount: amount + more, ref: ref);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'label': label,
    'amount': amount.paise,
    if (ref != null) 'ref': ref,
  };

  @override
  bool operator ==(Object other) =>
      other is DiscountLine &&
      other.kind == kind &&
      other.label == label &&
      other.amount == amount &&
      other.ref == ref;

  @override
  int get hashCode => Object.hash(kind, label, amount, ref);

  @override
  String toString() => 'DiscountLine(${kind.name}, $label, ${amount.paise})';
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
    this.discounts = const [],
    this.serviceCharge = Money.zero,
    this.serviceChargeBasisPoints = 0,
    this.taxName = 'Taxes',
  });

  factory BillBreakdown.fromSubtotal(
    Money subtotal,
    PricingConfig config, {
    Money discount = Money.zero,
    String? discountLabel,
    List<DiscountLine> discounts = const [],
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
      discounts: applied.isZero ? const [] : List.unmodifiable(discounts),
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
    discounts: List.unmodifiable([
      for (final line in json['discounts'] as List? ?? const [])
        DiscountLine.fromJson(line as Map<String, dynamic>),
    ]),
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

  /// What [discount] is made of (empty for bills from before itemised
  /// discounts: show [discountLabel] then).
  final List<DiscountLine> discounts;
  final Money serviceCharge;
  final int serviceChargeBasisPoints;
  final Money tax;
  final Money total;
  final int taxRateBasisPoints;
  final String taxName;

  /// Amount the tax was calculated on.
  Money get taxableAmount => subtotal - discount + serviceCharge;

  bool get hasDiscount => !discount.isZero;

  /// The discount lines to show: the itemised ones, or one line for a bill
  /// without them.
  List<DiscountLine> get discountLines => discounts.isNotEmpty
      ? discounts
      : [
          if (hasDiscount)
            DiscountLine(
              kind: DiscountKind.coupon,
              label: discountLabel ?? 'Discount',
              amount: discount,
            ),
        ];

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
    if (discounts.isNotEmpty)
      'discounts': [for (final line in discounts) line.toJson()],
    if (hasServiceCharge) 'service': serviceCharge.paise,
    if (serviceChargeBasisPoints != 0) 'serviceRate': serviceChargeBasisPoints,
    'tax': tax.paise,
    'total': total.paise,
    'taxRate': taxRateBasisPoints,
    if (taxName != 'Taxes') 'taxName': taxName,
  };
}
