import 'package:flutter/foundation.dart';

import '../models/billing.dart';
import '../models/restaurant_order.dart';
import '../models/restaurant_settings.dart';
import '../models/staff.dart';
import '../repositories/billing_repository.dart';
import '../services/payment_gateway.dart';
import '../utils/currency.dart';
import '../utils/formatters.dart';
import '../utils/restaurant_time.dart';
import 'access.dart';

/// A payment that cannot go ahead, with a message for the guest or staff.
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

  Future<(PaymentTransaction, Invoice)> payOnline({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String idempotencyKey,
    SimulatedOutcome outcome,
  });

  /// The current status of a payment (pending ones are re-checked).
  Future<(PaymentTransaction, Invoice)> refreshPayment(String paymentId);

  Future<(PaymentTransaction, Invoice)> recordCounterPayment({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String reference,
    required String idempotencyKey,
  });

  Future<(RefundRecord, Invoice)> refund({
    required String paymentId,
    required Money amount,
    required String reason,
    required String idempotencyKey,
  });

  Future<(int, Invoice)> reconcile(String invoiceId);
}

/// Bills, payments and refunds. Amounts paid and outstanding always come
/// from the recorded transactions, never from the order status.
///
/// With a [backend], the server creates bills and records every payment
/// and refund; this controller shows what the server returns.
class BillingController extends ChangeNotifier {
  BillingController(
    this._repository,
    this._gateway, {
    this._guard,
    this._audit,
    this._backend,
    RestaurantSettings Function()? settings,
    DateTime Function()? clock,
  }) : _settings = settings ?? (() => const RestaurantSettings()),
       _clock = clock ?? DateTime.now;

  final BillingRepository _repository;
  final PaymentGateway _gateway;
  final AccessGuard? _guard;
  final AuditLog? _audit;
  final BillingBackend? _backend;
  final RestaurantSettings Function() _settings;
  final DateTime Function() _clock;

  List<Invoice> _invoices = const [];
  final Set<String> _inFlight = {};

  PaymentGateway get gateway => _gateway;

  /// True when online payments are simulations (the demo, or the server's
  /// development simulator).
  bool get isSimulated => _gateway.isSimulated;

  /// Puts the server's version of a bill in the list.
  void _accept(Invoice invoice) {
    final exists = _invoices.any((i) => i.id == invoice.id);
    _setInvoices(
      exists
          ? [for (final i in _invoices) i.id == invoice.id ? invoice : i]
          : [invoice, ..._invoices],
    );
  }

  /// Online methods both enabled by the restaurant and supported by the
  /// connected provider (in display order).
  List<PaymentMethodType> get onlineMethods => [
    for (final method in PaymentMethodType.online)
      if (_settings().onlineMethods.contains(method) &&
          _gateway.supportedMethods.contains(method))
        method,
  ];

  bool get onlinePaymentsAvailable => onlineMethods.isNotEmpty;

  bool get allowPartialPayments => _settings().allowPartialPayments;

  /// Newest first.
  List<Invoice> get invoices => _invoices;

  Invoice? byId(String id) => _invoices.where((i) => i.id == id).firstOrNull;

  Invoice? forOrder(String orderId) =>
      _invoices.where((i) => i.orderId == orderId).firstOrNull;

  bool isProcessing(String invoiceId) => _inFlight.contains(invoiceId);

  Future<void> load() async {
    _setInvoices(await _repository.fetchInvoices());
    // Payments interrupted before confirmation (e.g. the app was closed).
    for (final invoice in _invoices.where((i) => i.hasPendingPayment)) {
      await _resolvePending(invoice.id);
    }
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

  // --------------------------------------------------------------- payments

  /// Returns a message when [amount] cannot be paid on [invoice] now.
  String? validateAmount(
    Invoice invoice,
    Money amount, {
    bool allowPartial = true,
  }) {
    if (invoice.isVoid) return 'This bill was cancelled.';
    if (invoice.outstanding.isZero) return 'This bill is already paid.';
    if (invoice.hasPendingPayment) {
      return 'A payment for this bill is still being confirmed.';
    }
    if (amount.paise <= 0) return 'Enter an amount to pay.';
    final max = invoice.payableNow;
    if (amount.compareTo(max) > 0) {
      return 'You can pay at most ${CurrencyFormatter.format(max)}.';
    }
    if (!allowPartial && amount != max) {
      return 'Please pay the full ${CurrencyFormatter.format(max)}.';
    }
    return null;
  }

  /// Guest payment through the configured provider. Only a verified result
  /// marks money as paid.
  Future<PaymentTransaction> payOnline({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) async {
    final invoice = byId(invoiceId);
    if (invoice == null) throw const PaymentException('Bill not found.');
    if (!onlineMethods.contains(method)) {
      throw PaymentException('${method.label} is not available right now.');
    }
    final problem = validateAmount(
      invoice,
      amount,
      allowPartial: allowPartialPayments,
    );
    if (problem != null) throw PaymentException(problem);
    if (!_inFlight.add(invoiceId)) {
      throw const PaymentException('A payment for this bill is in progress.');
    }
    notifyListeners();
    final backend = _backend;
    if (backend != null) {
      try {
        final (payment, updated) = await backend.payOnline(
          invoiceId: invoiceId,
          amount: amount,
          method: method,
          idempotencyKey: Ids.random(),
          outcome: outcome,
        );
        _accept(updated);
        return payment;
      } finally {
        _inFlight.remove(invoiceId);
        notifyListeners();
      }
    }
    final now = _clock();
    var transaction = PaymentTransaction(
      id: Ids.sequential('PAY', _allPaymentIds()),
      invoiceId: invoice.id,
      orderId: invoice.orderId,
      amount: amount,
      method: method,
      status: PaymentStatus.pending,
      provider: _gateway.providerName,
      createdAt: now,
      updatedAt: now,
      idempotencyKey: Ids.random(),
      isSimulated: _gateway.isSimulated,
    );
    try {
      // Record the attempt first so an interrupted payment can be resolved.
      await _save(invoice.withPayment(transaction));
      final result = await _gateway.collect(
        PaymentRequest(
          invoiceId: invoice.id,
          orderId: invoice.orderId,
          amount: amount,
          method: method,
          idempotencyKey: transaction.idempotencyKey,
        ),
        outcome: outcome,
      );
      transaction = transaction.copyWith(
        status: result.status,
        reference: result.reference,
        failureReason: result.failureReason,
        updatedAt: _clock(),
      );
      await _save(byId(invoiceId)!.withPayment(transaction));
      return transaction;
    } on PaymentException {
      rethrow;
    } on Object {
      // Outcome unknown: keep it pending until the provider confirms.
      throw const PaymentException(
        'We could not confirm this payment yet. Check its status in a moment; '
        'you will not be charged twice.',
      );
    } finally {
      _inFlight.remove(invoiceId);
      notifyListeners();
    }
  }

  Iterable<String> _allPaymentIds() =>
      _invoices.expand((i) => i.payments.map((p) => p.id));

  /// Asks the provider for the final status of pending payments on a bill.
  Future<void> checkPending(String invoiceId) => _resolvePending(invoiceId);

  /// Admin reconciliation of pending payments.
  Future<int> reconcile(String invoiceId) async {
    _requireGuard().require(Permission.reconcilePayments);
    final backend = _backend;
    if (backend != null) {
      final (resolved, updated) = await backend.reconcile(invoiceId);
      _accept(updated);
      return resolved;
    }
    final resolved = await _resolvePending(invoiceId);
    if (resolved > 0) {
      await _audit?.record(
        'payment.reconcile',
        'Reconciled $resolved pending payment(s) on bill '
            '${byId(invoiceId)?.billNumber ?? invoiceId}',
        targetId: invoiceId,
      );
    }
    return resolved;
  }

  Future<int> _resolvePending(String invoiceId) async {
    var resolved = 0;
    final invoice = byId(invoiceId);
    if (invoice == null || _inFlight.contains(invoiceId)) return 0;
    final backend = _backend;
    if (backend != null) {
      for (final pending in invoice.payments.where(
        (p) => p.status == PaymentStatus.pending,
      )) {
        final (payment, updated) = await backend.refreshPayment(pending.id);
        _accept(updated);
        if (payment.status != PaymentStatus.pending) resolved++;
      }
      return resolved;
    }
    for (final pending in invoice.payments.where(
      (p) => p.status == PaymentStatus.pending,
    )) {
      final result = await _gateway.checkStatus(pending);
      if (result.status == PaymentStatus.pending) continue;
      await _save(
        byId(invoiceId)!.withPayment(
          pending.copyWith(
            status: result.status,
            reference: result.reference.isEmpty ? null : result.reference,
            failureReason: result.failureReason,
            updatedAt: _clock(),
          ),
        ),
      );
      resolved++;
    }
    return resolved;
  }

  /// Staff record of money taken at the counter (cash, card terminal, UPI
  /// at the counter). Partial amounts are allowed for split payments, but
  /// never more than the balance.
  Future<PaymentTransaction> recordCounterPayment({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    String reference = '',
  }) async {
    final guard = _requireGuard()..require(Permission.collectPayments);
    final invoice = byId(invoiceId);
    if (invoice == null) throw const PaymentException('Bill not found.');
    final problem = validateAmount(invoice, amount);
    if (problem != null) throw PaymentException(problem);
    final backend = _backend;
    if (backend != null) {
      // The server records it (and its audit entry) for the signed-in staff.
      final (payment, updated) = await backend.recordCounterPayment(
        invoiceId: invoiceId,
        amount: amount,
        method: method,
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
      method: method,
      status: PaymentStatus.succeeded,
      provider: 'Counter',
      createdAt: now,
      updatedAt: now,
      idempotencyKey: Ids.random(),
      reference: reference.trim(),
      recordedBy: guard.actor?.name ?? '',
    );
    await _save(invoice.withPayment(transaction));
    await _audit?.record(
      'payment.record',
      'Recorded ${CurrencyFormatter.format(amount)} ${method.label} on bill '
          '${invoice.billNumber}',
      targetId: invoice.id,
    );
    return transaction;
  }

  /// Refunds part or all of one successful payment.
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
      if (refund.status == RefundStatus.failed) {
        throw const PaymentException(
          'The payment provider declined the refund. Nothing was returned.',
        );
      }
      return refund;
    }
    final RefundStatus status;
    final String referenceText;
    final bool simulated;
    if (payment.method.isOnline && payment.provider != 'Counter') {
      final result = await _gateway.refund(
        payment,
        amount,
        reason: why,
        idempotencyKey: key,
      );
      status = result.status == PaymentStatus.succeeded
          ? RefundStatus.processed
          : (result.status == PaymentStatus.pending
                ? RefundStatus.pending
                : RefundStatus.failed);
      referenceText = result.reference;
      simulated = payment.isSimulated || _gateway.isSimulated;
    } else {
      // Counter payments are refunded at the counter; this records it.
      status = RefundStatus.processed;
      referenceText = 'Returned at counter';
      simulated = false;
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
      status: status,
      createdAt: _clock(),
      processedBy: guard.actor?.name ?? '',
      reference: referenceText,
      isSimulated: simulated,
    );
    await _save(invoice.withRefund(refund));
    await _audit?.record(
      'payment.refund',
      '${simulated ? 'Simulated refund' : 'Refund'} of '
          '${CurrencyFormatter.format(amount)} on bill ${invoice.billNumber} '
          '(${status.label}): $why',
      targetId: invoice.id,
    );
    if (status == RefundStatus.failed) {
      throw const PaymentException(
        'The payment provider declined the refund. Nothing was returned.',
      );
    }
    return refund;
  }

  /// Bills for the guest's orders, newest first.
  List<Invoice> forOrders(Iterable<RestaurantOrder> orders) {
    final ids = {for (final o in orders) o.id};
    return _invoices.where((i) => ids.contains(i.orderId)).toList();
  }

  /// Payment summary line for lists: `Paid · UPI` or `Due ₹120`.
  static String shortStatus(Invoice invoice) => switch (invoice.status) {
    InvoiceStatus.paid => 'Paid · ${invoice.methodsLabel}',
    InvoiceStatus.partiallyPaid =>
      'Due ${CurrencyFormatter.format(invoice.outstanding)}',
    InvoiceStatus.unpaid || InvoiceStatus.failed =>
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
