import '../utils/currency.dart';
import 'billing.dart';

/// What a guest can choose on the payment screen.
///
/// Online options are paid through the payment provider (simulated in demo
/// mode). Counter options only tell staff how the guest will pay: the bill
/// changes when staff record the money. QR Payment is UPI paid by scanning
/// a QR code, so it is recorded as UPI with the detail "QR code".
enum PaymentOption {
  upi('UPI', PaymentMethodType.upi, detail: 'UPI ID'),
  scanAndPay('QR Payment', PaymentMethodType.upi, detail: 'QR code'),
  card('Card', PaymentMethodType.card),
  netBanking('Net Banking', PaymentMethodType.netBanking),
  wallet('Wallet', PaymentMethodType.wallet),
  cash('Cash', PaymentMethodType.cash, counter: CounterRequestKind.cash),
  payAtCounter('Pay at Counter', null, counter: CounterRequestKind.counter);

  const PaymentOption(
    this.label,
    this.method, {
    this.detail = '',
    this.counter,
  });

  final String label;

  /// The recorded method; null for "any method at the counter".
  final PaymentMethodType? method;

  /// Default method detail sent with the payment.
  final String detail;

  /// Set for the options paid at the counter.
  final CounterRequestKind? counter;

  bool get isOnline => counter == null;

  /// UPI moves Indian rupees only.
  bool get needsRupees => method == PaymentMethodType.upi;

  /// One line under the option's name.
  String get description => switch (this) {
    upi => 'Pay to the restaurant UPI ID',
    scanAndPay => 'Scan a QR code with any UPI app',
    card => 'Credit or debit card',
    netBanking => 'Pay from your bank account',
    wallet => 'Pay from a mobile wallet',
    cash => 'Pay cash to staff or at the counter',
    payAtCounter => 'Pay by any method at the counter',
  };
}

/// One part of a split payment.
class SplitPart {
  const SplitPart(this.option, this.amount);

  final PaymentOption option;
  final Money amount;
}

/// Splitting a bill across several options. Online parts are paid one by
/// one; at most one counter part (cash or any method at the counter) is
/// left for staff to record. Parts never add up to more than the balance.
abstract final class SplitPlan {
  static const maxParts = 4;

  /// Returns a message when [parts] cannot be used to pay [payable], or
  /// null. [available] are the options the guest may use now.
  static String? validate(
    List<SplitPart> parts, {
    required Money payable,
    required Set<PaymentOption> available,
    required bool allowPartial,
  }) {
    if (!allowPartial) {
      return 'This restaurant takes the full amount in one payment.';
    }
    if (parts.length < 2) return 'Add at least two parts to split the bill.';
    if (parts.length > maxParts) {
      return 'Split the bill into at most $maxParts parts.';
    }
    for (final part in parts) {
      if (!available.contains(part.option)) {
        return '${part.option.label} is not available right now.';
      }
      if (part.amount.paise <= 0) return 'Every part needs an amount.';
    }
    if (parts.where((p) => !p.option.isOnline).length > 1) {
      return 'Choose one way to pay at the counter.';
    }
    final total = Money.sum(parts.map((p) => p.amount));
    if (total.compareTo(payable) > 0) {
      return 'The parts add up to ${CurrencyFormatter.format(total)}, more '
          'than the ${CurrencyFormatter.format(payable)} due.';
    }
    if (total != payable) {
      return 'The parts add up to ${CurrencyFormatter.format(total)}; '
          '${CurrencyFormatter.format(payable - total)} is still unassigned.';
    }
    return null;
  }

  /// Online parts first (in the guest's order), the counter part last, so
  /// staff are only asked to collect once the online parts went through.
  static List<SplitPart> ordered(List<SplitPart> parts) => [
    ...parts.where((p) => p.option.isOnline),
    ...parts.where((p) => !p.option.isOnline),
  ];
}
