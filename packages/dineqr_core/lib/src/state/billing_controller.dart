import 'package:flutter/foundation.dart';

import '../models/billing.dart';
import '../models/restaurant_order.dart';
import '../models/restaurant_settings.dart';
import '../models/staff.dart';
import '../repositories/billing_repository.dart';
import '../utils/currency.dart';
import '../utils/formatters.dart';
import '../utils/restaurant_time.dart';
import 'access.dart';

/// A payment or refund that cannot go ahead, with a message for staff.
class PaymentException implements Exception {
  const PaymentException(this.message);

  final String message;

  @override
  String toString() => 'PaymentException($message)';
}

/// Billing operations decided and recorded by the server (backend mode).
/// Each returns the server's updated bill; the app never writes payment
/// state itself.
abstract interface class BillingBackend {
  Future<Invoice> billForOrder(String orderId);

  Future<(PaymentTransaction, Invoice)> recordCounterPayment({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String reference,
    required String idempotencyKey,
    String methodDetail,
  });

  Future<(RefundRecord, Invoice)> refund({
    required String paymentId,
    required Money amount,
    required String reason,
    required String idempotencyKey,
  });
}

/// Bills, counter payments and refunds. Amounts paid and outstanding always
/// come from the recorded transactions, never from the order status.
///
/// DineQR takes no payments online: guests order in the app and pay at the
/// restaurant's billing counter, where staff record the payment on the bill
/// ([recordCounterPayment]). Payments recorded before online payment was
/// retired stay on their bills as history.
///
/// With a [backend], the server creates bills and records every payment
/// and refund; this controller shows what the server returns.
class BillingController extends ChangeNotifier {
  BillingController(
    this._repository, {
    this._guard,
    this._audit,
    this._backend,
    RestaurantSettings Function()? settings,
    DateTime Function()? clock,
  }) : _settings = settings ?? (() => const RestaurantSettings()),
       _clock = clock ?? DateTime.now;

  final BillingRepository _repository;
  final AccessGuard? _guard;
  final AuditLog? _audit;
  final BillingBackend? _backend;
  final RestaurantSettings Function() _settings;
  final DateTime Function() _clock;

  List<Invoice> _invoices = const [];
  final Set<String> _inFlight = {};

  /// The restaurant's settings changed (currency, receipt details): billing
  /// screens rebuild.
  void settingsChanged() => notifyListeners();

  /// Puts the server's version of a bill in the list.
  void _accept(Invoice invoice) {
    final exists = _invoices.any((i) => i.id == invoice.id);
    _setInvoices(
      exists
          ? [for (final i in _invoices) i.id == invoice.id ? invoice : i]
          : [invoice, ..._invoices],
    );
  }

  /// Puts the server's current version of one bill in the list (a live
  /// update named it), without re-reading every bill.
  void acceptFromServer(Invoice invoice) => _accept(invoice);

  /// Newest first.
  List<Invoice> get invoices => _invoices;

  Invoice? byId(String id) => _invoices.where((i) => i.id == id).firstOrNull;

  Invoice? forOrder(String orderId) =>
      _invoices.where((i) => i.orderId == orderId).firstOrNull;

  bool isProcessing(String invoiceId) => _inFlight.contains(invoiceId);

  Future<void> load() async {
    _setInvoices(await _repository.fetchInvoices());
  }

  void _setInvoices(Iterable<Invoice> invoices) {
    _invoices = invoices.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> _save(Invoice invoice) async {
    await _repository.saveInvoice(invoice);
    final exists = _invoices.any((i) => i.id == invoice.id);
    _setInvoices(
      exists
          ? [for (final i in _invoices) i.id == invoice.id ? invoice : i]
          : [invoice, ..._invoices],
    );
  }

  // ---------------------------------------------------------------- bills

  /// `DQ-2026-00012`: year in restaurant time and a running number.
  String _nextBillNumber(DateTime at) {
    var highest = 0;
    for (final invoice in _invoices) {
      final number = int.tryParse(invoice.billNumber.split('-').last);
      if (number != null && number > highest) highest = number;
    }
    final year = RestaurantTime.wall(at).year;
    return 'DQ-$year-${(highest + 1).toString().padLeft(5, '0')}';
  }

  /// Creates the bill for [order] (once; repeated calls return it). With a
  /// backend the server created it with the order; it is fetched.
  Future<Invoice> createForOrder(RestaurantOrder order) async {
    final existing = forOrder(order.id);
    if (existing != null) return existing;
    final backend = _backend;
    if (backend != null) {
      final fetched = await backend.billForOrder(order.id);
      _accept(fetched);
      return fetched;
    }
    final invoice = Invoice(
      id: Ids.sequential('INV', _invoices.map((i) => i.id)),
      billNumber: _nextBillNumber(order.createdAt),
      orderId: order.id,
      tableNumber: order.tableNumber,
      createdAt: order.createdAt,
      lines: order.lines,
      amounts: order.bill,
      restaurant: _settings().snapshot,
      isDemoSample: order.isDemoSample,
    );
    await _save(invoice);
    return invoice;
  }

  /// Voids the bill of a cancelled order. Money already paid stays recorded
  /// and shows as a refund due.
  Future<void> voidForOrder(RestaurantOrder order) async {
    final backend = _backend;
    if (backend != null) {
      // The server voided it with the cancellation; show its version.
      _accept(await backend.billForOrder(order.id));
      return;
    }
    final invoice = forOrder(order.id) ?? await createForOrder(order);
    if (invoice.isVoid) return;
    await _save(
      invoice.voided(
        order.cancelReason.isEmpty ? 'Order cancelled' : order.cancelReason,
      ),
    );
  }

  // ------------------------------------------------------- counter payments

  /// Returns a message when [amount] cannot be recorded on [invoice] now.
  String? validateAmount(Invoice invoice, Money amount) {
    if (invoice.isVoid) return 'This bill was cancelled.';
    if (invoice.outstanding.isZero) return 'This bill is already paid.';
    if (amount.paise <= 0) return 'Enter an amount.';
    final max = invoice.payableNow;
    if (amount.compareTo(max) > 0) {
      return 'At most ${CurrencyFormatter.format(max)} is due.';
    }
    return null;
  }

  Iterable<String> _allPaymentIds() =>
      _invoices.expand((i) => i.payments.map((p) => p.id));

  /// Staff record of money taken at the billing counter (cash, card
  /// terminal, or the counter's UPI scanner). Part amounts are allowed (a
  /// bill paid part in cash, part by card), never more than the balance.
  Future<PaymentTransaction> recordCounterPayment({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    String reference = '',
    String methodDetail = '',
  }) async {
    final guard = _requireGuard()..require(Permission.collectPayments);
    final invoice = byId(invoiceId);
    if (invoice == null) throw const PaymentException('Bill not found.');
    if (!PaymentMethodType.counter.contains(method)) {
      throw const PaymentException('The counter takes cash, card or UPI.');
    }
    final problem = validateAmount(invoice, amount);
    if (problem != null) throw PaymentException(problem);
    if (!_inFlight.add(invoiceId)) {
      throw const PaymentException('A payment for this bill is in progress.');
    }
    notifyListeners();
    try {
      final backend = _backend;
      if (backend != null) {
        // The server records it (and its audit entry) for the signed-in staff.
        final (payment, updated) = await backend.recordCounterPayment(
          invoiceId: invoiceId,
          amount: amount,
          method: method,
          methodDetail: methodDetail,
          reference: reference.trim(),
          idempotencyKey: Ids.random(),
        );
        _accept(updated);
        return payment;
      }
      final now = _clock();
      final transaction = PaymentTransaction(
        id: Ids.sequential('PAY', _allPaymentIds()),
        invoiceId: invoice.id,
        orderId: invoice.orderId,
        amount: amount,
        currency: _settings().currencyCode,
        method: method,
        methodDetail: methodDetail,
        status: PaymentStatus.succeeded,
        provider: PaymentTransaction.counterProvider,
        createdAt: now,
        updatedAt: now,
        idempotencyKey: Ids.random(),
        reference: reference.trim(),
        recordedBy: guard.actor?.name ?? '',
      );
      await _save(invoice.withPayment(transaction));
      await _audit?.record(
        'payment.record',
        'Recorded ${CurrencyFormatter.format(amount)} '
            '${method.label} on bill ${invoice.billNumber}',
        targetId: invoice.id,
      );
      return transaction;
    } finally {
      _inFlight.remove(invoiceId);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- refunds

  /// Records a refund of part or all of one successful payment. The
  /// restaurant returns the money itself at the counter. A payment taken
  /// through the retired online gateway is refunded from that gateway's own
  /// dashboard instead (the server refuses it here).
  Future<RefundRecord> refund({
    required String invoiceId,
    required String paymentId,
    required Money amount,
    required String reason,
  }) async {
    final guard = _requireGuard()..require(Permission.issueRefunds);
    final invoice = byId(invoiceId);
    if (invoice == null) throw const PaymentException('Bill not found.');
    final payment = invoice.payments
        .where((p) => p.id == paymentId)
        .firstOrNull;
    if (payment == null || payment.status != PaymentStatus.succeeded) {
      throw const PaymentException('Choose a successful payment to refund.');
    }
    if (payment.isGateway) {
      throw PaymentException(
        'This payment was taken online through ${payment.provider}. '
        "Refund it from that provider's dashboard.",
      );
    }
    final why = reason.trim();
    if (why.length < 3) {
      throw const PaymentException('Enter a reason for the refund.');
    }
    final max = invoice.refundableOn(paymentId);
    if (amount.paise <= 0) throw const PaymentException('Enter an amount.');
    if (amount.compareTo(max) > 0) {
      throw PaymentException(
        'At most ${CurrencyFormatter.format(max)} can be refunded on this '
        'payment.',
      );
    }
    final key = Ids.random();
    final backend = _backend;
    if (backend != null) {
      final (refund, updated) = await backend.refund(
        paymentId: paymentId,
        amount: amount,
        reason: why,
        idempotencyKey: key,
      );
      _accept(updated);
      return refund;
    }
    final refund = RefundRecord(
      id: Ids.sequential(
        'RF',
        _invoices.expand((i) => i.refunds.map((r) => r.id)),
      ),
      invoiceId: invoice.id,
      paymentId: paymentId,
      amount: amount,
      reason: why,
      // Returned at the counter; this records it.
      status: RefundStatus.processed,
      createdAt: _clock(),
      processedBy: guard.actor?.name ?? '',
      reference: 'Returned at counter',
      isSimulated: payment.isSimulated,
    );
    await _save(invoice.withRefund(refund));
    await _audit?.record(
      'payment.refund',
      '${payment.isSimulated ? 'Test refund' : 'Refund'} of '
          '${CurrencyFormatter.format(amount)} on bill ${invoice.billNumber}: '
          '$why',
      targetId: invoice.id,
    );
    return refund;
  }

  /// Bills for the given orders, newest first.
  List<Invoice> forOrders(Iterable<RestaurantOrder> orders) {
    final ids = {for (final o in orders) o.id};
    return _invoices.where((i) => ids.contains(i.orderId)).toList();
  }

  /// Payment summary line for lists: `Paid · Cash` or `Due ₹120`.
  static String shortStatus(Invoice invoice) => switch (invoice.status) {
    InvoiceStatus.paid => 'Paid · ${invoice.methodsLabel}',
    InvoiceStatus.partiallyPaid ||
    InvoiceStatus.unpaid ||
    InvoiceStatus.failed =>
      'Due ${CurrencyFormatter.format(invoice.outstanding)}',
    _ => invoice.status.label,
  };

  /// Replaces all bills (demo reset).
  Future<void> resetDemo(List<Invoice> seed) async {
    await _repository.replaceAll(seed);
    _setInvoices(seed);
  }

  AccessGuard _requireGuard() {
    final guard = _guard;
    if (guard == null) throw StateError('Admin actions need an AccessGuard.');
    return guard;
  }

  /// `Paid ₹189 on 17 Oct 2026, 12:30 PM`
  static String paidOn(PaymentTransaction p) =>
      'Paid ${CurrencyFormatter.format(p.amount)} on ${AppFormat.dateTime(p.updatedAt)}';
}
