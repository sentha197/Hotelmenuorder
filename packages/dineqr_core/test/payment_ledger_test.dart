import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 22, 21);
  final seed = DemoSeed.generate(now);

  group('payment ledger', () {
    test('totals match the sales report for every preset range', () {
      for (final preset in [
        RangePreset.today,
        RangePreset.yesterday,
        RangePreset.last7,
        RangePreset.last30,
      ]) {
        final range = DateRange.preset(preset, now);
        final ledger = PaymentLedger.build(
          invoices: seed.invoices,
          range: range,
        );
        final report = SalesReport.build(
          orders: seed.orders,
          invoices: seed.invoices,
          range: range,
          now: now,
        );
        expect(ledger.collected, report.collected, reason: preset.name);
        expect(ledger.refunded, report.refunds, reason: preset.name);
        expect(ledger.netCollected, report.netCollected, reason: preset.name);
      }
    });

    test('the sample data exercises refunds and failed payments', () {
      final ledger = PaymentLedger.build(
        invoices: seed.invoices,
        range: DateRange.preset(RangePreset.last30, now),
      );
      expect(ledger.entries.where((e) => e.isRefund), isNotEmpty);
      expect(ledger.failedCount, greaterThan(0));
    });

    test('entries are newest first and inside the range', () {
      final range = DateRange.preset(RangePreset.last7, now);
      final ledger = PaymentLedger.build(invoices: seed.invoices, range: range);
      for (var i = 1; i < ledger.entries.length; i++) {
        expect(
          ledger.entries[i - 1].at.isBefore(ledger.entries[i].at),
          isFalse,
        );
      }
      expect(ledger.entries.every((e) => range.contains(e.at)), isTrue);
    });

    test('failed and pending attempts never count as collected', () {
      final range = DateRange.preset(RangePreset.last30, now);
      final failedOnly = PaymentLedger.build(
        invoices: seed.invoices,
        range: range,
        filter: LedgerFilter.failed,
      );
      expect(failedOnly.entries, isNotEmpty);
      expect(failedOnly.collected, Money.zero);
      expect(
        failedOnly.entries.every((e) => e.amount.paise > 0 && !e.isRefund),
        isTrue,
      );
    });

    test('filters by method and searches references and bills', () {
      final range = DateRange.preset(RangePreset.last30, now);
      final cash = PaymentLedger.build(
        invoices: seed.invoices,
        range: range,
        method: PaymentMethodType.cash,
      );
      expect(
        cash.entries.every((e) => e.method == PaymentMethodType.cash),
        isTrue,
      );

      final any = PaymentLedger.build(invoices: seed.invoices, range: range);
      final bill = any.entries.first.invoice.billNumber;
      final found = PaymentLedger.build(
        invoices: seed.invoices,
        range: range,
        query: bill.toLowerCase(),
      );
      expect(found.entries, isNotEmpty);
      expect(found.entries.every((e) => e.invoice.billNumber == bill), isTrue);
    });

    test('refunds are negative amounts in the ledger', () {
      final refunds = PaymentLedger.build(
        invoices: seed.invoices,
        range: DateRange.preset(RangePreset.last30, now),
        filter: LedgerFilter.refunds,
      );
      expect(refunds.entries, isNotEmpty);
      expect(refunds.entries.every((e) => e.amount.paise < 0), isTrue);
      expect(refunds.collected, Money.zero);
    });
  });
}
