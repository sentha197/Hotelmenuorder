import '../../core/utils/currency.dart';

/// Pricing rules for the demo restaurant.
class PricingConfig {
  const PricingConfig({this.taxRateBasisPoints = 500});

  /// Demo GST rate in basis points (500 = 5%).
  final int taxRateBasisPoints;

  String get taxLabel {
    final percent = taxRateBasisPoints / 100;
    final text = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(2);
    return 'Taxes ($text%)';
  }
}

/// Subtotal, tax and total computed with one shared formula everywhere
/// (cart, order summary, stored orders).
class BillBreakdown {
  const BillBreakdown({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.taxRateBasisPoints,
  });

  factory BillBreakdown.fromSubtotal(Money subtotal, PricingConfig config) {
    final tax = subtotal.applyRate(config.taxRateBasisPoints);
    return BillBreakdown(
      subtotal: subtotal,
      tax: tax,
      total: subtotal + tax,
      taxRateBasisPoints: config.taxRateBasisPoints,
    );
  }

  static const empty = BillBreakdown(
    subtotal: Money.zero,
    tax: Money.zero,
    total: Money.zero,
    taxRateBasisPoints: 0,
  );

  final Money subtotal;
  final Money tax;
  final Money total;
  final int taxRateBasisPoints;

  String get taxLabel =>
      PricingConfig(taxRateBasisPoints: taxRateBasisPoints).taxLabel;
}
