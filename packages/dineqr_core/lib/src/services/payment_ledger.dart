import '../models/billing.dart';
import '../utils/currency.dart';
import '../utils/restaurant_time.dart';

/// One line of the payment ledger: a payment attempt or a refund.
class LedgerEntry {
  const LedgerEntry.payment(this.invoice, PaymentTransaction this.payment)
    : refund = null;

  const LedgerEntry.refund(this.invoice, RefundRecord this.refund)
    : payment = null;

  final Invoice invoice;
  final PaymentTransaction? payment;
  final RefundRecord? refund;

  bool get isRefund => refund != null;

  /// When it counts: a payment's confirmation (or last update), a refund's
  /// creation. The same times [SalesReport] uses.
  DateTime get at => payment?.updatedAt ?? refund!.createdAt;

  /// Money moved: positive for payments, negative for refunds.
  Money get amount => payment?.amount ?? Money.zero - refund!.amount;

  PaymentMethodType? get method => payment?.method;

  String get reference => payment?.reference ?? refund!.reference;

  bool get isSimulated => payment?.isSimulated ?? refund!.isSimulated;

  String get statusLabel => payment?.status.label ?? refund!.status.label;
}

/// Filter for [PaymentLedger] entries.
enum LedgerFilter {
  all('All'),
  succeeded('Successful'),
  pending('Pending'),
  failed('Failed'),
  cancelled('Cancelled'),
  refunds('Refunds');

  const LedgerFilter(this.label);

  final String label;

  bool matches(LedgerEntry entry) {
    final payment = entry.payment;
    return switch (this) {
      LedgerFilter.all => true,
      LedgerFilter.refunds => entry.isRefund,
      LedgerFilter.succeeded => payment?.status == PaymentStatus.succeeded,
      LedgerFilter.pending => payment?.status == PaymentStatus.pending,
      LedgerFilter.failed => payment?.status == PaymentStatus.failed,
      LedgerFilter.cancelled => payment?.status == PaymentStatus.cancelled,
    };
  }
}

/// Every payment attempt and refund in a date range, newest first, with
/// totals defined exactly as in [SalesReport]: collected counts successful
/// payments only (pending, failed and cancelled attempts move no money),
/// and refunds count processed refunds only.
class PaymentLedger {
  PaymentLedger._(this.range, this.entries);

  factory PaymentLedger.build({
    required Iterable<Invoice> invoices,
    required DateRange range,
    LedgerFilter filter = LedgerFilter.all,
    PaymentMethodType? method,
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    bool matchesQuery(LedgerEntry entry) {
      if (needle.isEmpty) return true;
      final invoice = entry.invoice;
      return [
        entry.reference,
        invoice.billNumber,
        invoice.orderId,
        'table ${invoice.tableNumber}',
      ].any((text) => text.toLowerCase().contains(needle));
    }

    final entries =
        <LedgerEntry>[
            for (final invoice in invoices) ...[
              for (final payment in invoice.payments)
                LedgerEntry.payment(invoice, payment),
              for (final refund in invoice.refunds)
                LedgerEntry.refund(invoice, refund),
            ],
          ].where((entry) {
            if (!range.contains(entry.at)) return false;
            if (!filter.matches(entry)) return false;
            // Refunds go back by the original method; the method filter applies to
            // payments only.
            if (method != null && entry.method != method) return false;
            return matchesQuery(entry);
          }).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return PaymentLedger._(range, entries);
  }

  final DateRange range;
  final List<LedgerEntry> entries;

  Iterable<PaymentTransaction> get _payments =>
      entries.map((e) => e.payment).whereType<PaymentTransaction>();

  Money get collected => Money.sum(
    _payments
        .where((p) => p.status == PaymentStatus.succeeded)
        .map((p) => p.amount),
  );

  Money get refunded => Money.sum(
    entries
        .map((e) => e.refund)
        .whereType<RefundRecord>()
        .where((r) => r.status == RefundStatus.processed)
        .map((r) => r.amount),
  );

  Money get netCollected => collected - refunded;

  Money get pendingAmount => Money.sum(
    _payments
        .where((p) => p.status == PaymentStatus.pending)
        .map((p) => p.amount),
  );

  int get failedCount =>
      _payments.where((p) => p.status == PaymentStatus.failed).length;

  bool get hasSimulated => entries.any((e) => e.isSimulated);
}
