import '../utils/currency.dart';
import 'order_type.dart';
import 'pricing.dart';
import 'restaurant_order.dart';

/// How a guest paid. Which online methods are offered depends on the
/// restaurant settings and on what the payment provider supports.
enum PaymentMethodType {
  upi('UPI'),
  card('Card'),
  netBanking('Net banking'),
  wallet('Wallet'),
  cash('Cash');

  const PaymentMethodType(this.label);

  final String label;

  bool get isOnline => this != cash;

  static const online = [upi, card, netBanking, wallet];

  static PaymentMethodType? tryParse(String? name) {
    for (final method in values) {
      if (method.name == name) return method;
    }
    return null;
  }
}

/// How the restaurant takes payments. In [demo] mode online payments are
/// simulated and every payment (counter ones too) is a demo payment: no
/// money moves. [live] needs a verified payment gateway; until one is
/// configured it cannot be chosen.
enum PaymentMode {
  demo('Demo'),
  live('Live');

  const PaymentMode(this.label);

  final String label;

  static PaymentMode parse(String? name) =>
      name == live.name ? live : PaymentMode.demo;
}

/// How a guest said they will pay at the counter.
enum CounterRequestKind {
  cash('Cash at the counter'),
  counter('Pay at the counter');

  const CounterRequestKind(this.label);

  final String label;

  static CounterRequestKind parse(String? name) =>
      name == cash.name ? cash : counter;
}

/// The guest will pay [amount] at the counter. A notice for staff only:
/// nothing is paid until staff record the money.
class CounterRequest {
  const CounterRequest({
    required this.kind,
    required this.amount,
    required this.requestedAt,
  });

  factory CounterRequest.fromJson(Map<String, dynamic> json) => CounterRequest(
    kind: CounterRequestKind.parse(json['kind'] as String?),
    amount: Money(json['amount'] as int),
    requestedAt: DateTime.parse(json['at'] as String),
  );

  final CounterRequestKind kind;
  final Money amount;
  final DateTime requestedAt;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'amount': amount.paise,
    'at': requestedAt.toIso8601String(),
  };
}

enum PaymentStatus {
  pending('Pending'),
  succeeded('Successful'),
  failed('Failed'),
  cancelled('Cancelled');

  const PaymentStatus(this.label);

  final String label;

  bool get isFinal => this != pending;

  static PaymentStatus parse(String? name) => PaymentStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => PaymentStatus.failed,
  );
}

/// One attempt to collect money against a bill.
class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.invoiceId,
    required this.orderId,
    required this.amount,
    required this.method,
    required this.status,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
    required this.idempotencyKey,
    this.reference = '',
    this.failureReason = '',
    this.isSimulated = false,
    this.recordedBy = '',
    this.methodDetail = '',
    this.currency = 'INR',
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) =>
      PaymentTransaction(
        id: json['id'] as String,
        invoiceId: json['invoice'] as String,
        orderId: json['order'] as String,
        amount: Money(json['amount'] as int),
        method:
            PaymentMethodType.tryParse(json['method'] as String?) ??
            PaymentMethodType.cash,
        status: PaymentStatus.parse(json['status'] as String?),
        provider: json['provider'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        idempotencyKey: json['key'] as String? ?? '',
        reference: json['ref'] as String? ?? '',
        failureReason: json['failure'] as String? ?? '',
        isSimulated: json['simulated'] as bool? ?? false,
        recordedBy: json['by'] as String? ?? '',
        methodDetail: json['detail'] as String? ?? '',
        currency: json['currency'] as String? ?? 'INR',
      );

  final String id;
  final String invoiceId;
  final String orderId;
  final Money amount;
  final PaymentMethodType method;

  /// Display-only detail of the method, e.g. `Scan & Pay`, `Credit` or a
  /// bank name. Never a card number, CVV, PIN or password.
  final String methodDetail;

  /// ISO code of the currency it was paid in.
  final String currency;
  final PaymentStatus status;

  /// Who processed it, e.g. "Demo simulator" or "Counter".
  final String provider;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Unique per attempt so retries of the same request are not charged twice.
  final String idempotencyKey;

  /// Provider transaction id (or a staff-entered reference).
  final String reference;
  final String failureReason;

  /// True for demo payments: no money moved.
  final bool isSimulated;

  PaymentMode get mode => isSimulated ? PaymentMode.demo : PaymentMode.live;

  /// Staff member who recorded a counter payment.
  final String recordedBy;

  /// `UPI · Scan & Pay`, `Card · Credit` or just `Cash`.
  String get methodLabel =>
      methodDetail.isEmpty ? method.label : '${method.label} · $methodDetail';

  PaymentTransaction copyWith({
    PaymentStatus? status,
    String? reference,
    String? failureReason,
    DateTime? updatedAt,
  }) => PaymentTransaction(
    id: id,
    invoiceId: invoiceId,
    orderId: orderId,
    amount: amount,
    method: method,
    status: status ?? this.status,
    provider: provider,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    idempotencyKey: idempotencyKey,
    reference: reference ?? this.reference,
    failureReason: failureReason ?? this.failureReason,
    isSimulated: isSimulated,
    recordedBy: recordedBy,
    methodDetail: methodDetail,
    currency: currency,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice': invoiceId,
    'order': orderId,
    'amount': amount.paise,
    'currency': currency,
    'method': method.name,
    if (methodDetail.isNotEmpty) 'detail': methodDetail,
    'status': status.name,
    'provider': provider,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'key': idempotencyKey,
    if (reference.isNotEmpty) 'ref': reference,
    if (failureReason.isNotEmpty) 'failure': failureReason,
    if (isSimulated) 'simulated': true,
    if (recordedBy.isNotEmpty) 'by': recordedBy,
  };
}

enum RefundStatus {
  processed('Refunded'),
  pending('Refund pending'),
  failed('Refund failed');

  const RefundStatus(this.label);

  final String label;

  static RefundStatus parse(String? name) => RefundStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => RefundStatus.failed,
  );
}

/// Money returned to the guest against one payment.
class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.invoiceId,
    required this.paymentId,
    required this.amount,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.processedBy,
    this.reference = '',
    this.isSimulated = false,
  });

  factory RefundRecord.fromJson(Map<String, dynamic> json) => RefundRecord(
    id: json['id'] as String,
    invoiceId: json['invoice'] as String,
    paymentId: json['payment'] as String,
    amount: Money(json['amount'] as int),
    reason: json['reason'] as String? ?? '',
    status: RefundStatus.parse(json['status'] as String?),
    createdAt: DateTime.parse(json['createdAt'] as String),
    processedBy: json['by'] as String? ?? '',
    reference: json['ref'] as String? ?? '',
    isSimulated: json['simulated'] as bool? ?? false,
  );

  final String id;
  final String invoiceId;
  final String paymentId;
  final Money amount;
  final String reason;
  final RefundStatus status;
  final DateTime createdAt;
  final String processedBy;
  final String reference;

  /// True for demo refunds: no money moved.
  final bool isSimulated;

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice': invoiceId,
    'payment': paymentId,
    'amount': amount.paise,
    'reason': reason,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'by': processedBy,
    if (reference.isNotEmpty) 'ref': reference,
    if (isSimulated) 'simulated': true,
  };
}

/// Restaurant details printed on a bill, frozen when the bill is created.
class RestaurantSnapshot {
  const RestaurantSnapshot({
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.taxRegistration = '',
    this.footer = '',
  });

  factory RestaurantSnapshot.fromJson(Map<String, dynamic> json) =>
      RestaurantSnapshot(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        address: json['address'] as String? ?? '',
        taxRegistration: json['taxReg'] as String? ?? '',
        footer: json['footer'] as String? ?? '',
      );

  final String name;
  final String phone;
  final String email;
  final String address;
  final String taxRegistration;
  final String footer;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (phone.isNotEmpty) 'phone': phone,
    if (email.isNotEmpty) 'email': email,
    if (address.isNotEmpty) 'address': address,
    if (taxRegistration.isNotEmpty) 'taxReg': taxRegistration,
    if (footer.isNotEmpty) 'footer': footer,
  };
}

enum InvoiceStatus {
  unpaid('Unpaid'),
  pending('Payment pending'),
  partiallyPaid('Partially paid'),
  paid('Paid'),
  failed('Payment failed'),
  partiallyRefunded('Partly refunded'),
  refunded('Refunded'),
  voided('Void');

  const InvoiceStatus(this.label);

  final String label;
}

/// The bill for one order. Its amounts are the order's pricing snapshot;
/// what has been paid comes only from its payment and refund records.
class Invoice {
  Invoice({
    required this.id,
    required this.billNumber,
    required this.orderId,
    required this.tableNumber,
    required this.createdAt,
    required Iterable<OrderLine> lines,
    required this.amounts,
    required this.restaurant,
    Iterable<PaymentTransaction> payments = const [],
    Iterable<RefundRecord> refunds = const [],
    this.isVoid = false,
    this.voidReason = '',
    this.isDemoSample = false,
    this.counterRequest,
  }) : lines = List.unmodifiable(lines),
       payments = List.unmodifiable(payments),
       refunds = List.unmodifiable(refunds);

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: json['id'] as String,
    billNumber: json['number'] as String,
    orderId: json['order'] as String,
    tableNumber: json['table'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lines: [
      for (final line in json['lines'] as List)
        OrderLine.fromJson(line as Map<String, dynamic>),
    ],
    amounts: BillBreakdown.fromJson(json['amounts'] as Map<String, dynamic>),
    restaurant: RestaurantSnapshot.fromJson(
      json['restaurant'] as Map<String, dynamic>? ?? const {},
    ),
    payments: [
      for (final p in json['payments'] as List? ?? const [])
        PaymentTransaction.fromJson(p as Map<String, dynamic>),
    ],
    refunds: [
      for (final r in json['refunds'] as List? ?? const [])
        RefundRecord.fromJson(r as Map<String, dynamic>),
    ],
    isVoid: json['void'] as bool? ?? false,
    voidReason: json['voidReason'] as String? ?? '',
    isDemoSample: json['demo'] as bool? ?? false,
    counterRequest: switch (json['counterRequest']) {
      final Map<String, dynamic> request => CounterRequest.fromJson(request),
      _ => null,
    },
  );

  final String id;

  /// Printed bill number, e.g. `DQ-2026-00012`.
  final String billNumber;
  final String orderId;

  /// The order's table, or [OrderTables.takeaway].
  final int tableNumber;
  final DateTime createdAt;
  final List<OrderLine> lines;
  final BillBreakdown amounts;

  bool get isTakeaway => OrderTables.isTakeaway(tableNumber);

  /// "Table 07" or "Takeaway".
  String get tableLabel => OrderTables.label(tableNumber);
  final RestaurantSnapshot restaurant;
  final List<PaymentTransaction> payments;
  final List<RefundRecord> refunds;

  /// Set when the order was cancelled; a void bill has nothing outstanding.
  final bool isVoid;
  final String voidReason;
  final bool isDemoSample;

  /// Set when the guest said they will pay at the counter. It moves no
  /// money and never changes [status]; see [openCounterRequest].
  final CounterRequest? counterRequest;

  /// The counter request while there is still something to collect, with
  /// its amount capped at what is payable now.
  CounterRequest? get openCounterRequest {
    final request = counterRequest;
    if (request == null || payableNow.isZero) return null;
    if (request.amount.compareTo(payableNow) <= 0) return request;
    return CounterRequest(
      kind: request.kind,
      amount: payableNow,
      requestedAt: request.requestedAt,
    );
  }

  Money get total => amounts.total;

  Money get amountPaid => Money.sum(
    payments
        .where((p) => p.status == PaymentStatus.succeeded)
        .map((p) => p.amount),
  );

  Money get amountRefunded => Money.sum(
    refunds
        .where((r) => r.status == RefundStatus.processed)
        .map((r) => r.amount),
  );

  /// Paid minus refunded.
  Money get netPaid => amountPaid - amountRefunded;

  Money get pendingAmount => Money.sum(
    payments
        .where((p) => p.status == PaymentStatus.pending)
        .map((p) => p.amount),
  );

  bool get hasPendingPayment =>
      payments.any((p) => p.status == PaymentStatus.pending);

  /// Still owed by the guest. Refunds never re-open a balance.
  Money get outstanding {
    if (isVoid) return Money.zero;
    final remaining = total - amountPaid;
    return remaining.paise > 0 ? remaining : Money.zero;
  }

  /// What may be charged now without risking an overpayment.
  Money get payableNow {
    final value = outstanding - pendingAmount;
    return value.paise > 0 ? value : Money.zero;
  }

  /// What may still be refunded.
  Money get refundable {
    final pendingRefunds = Money.sum(
      refunds
          .where((r) => r.status == RefundStatus.pending)
          .map((r) => r.amount),
    );
    final value = netPaid - pendingRefunds;
    return value.paise > 0 ? value : Money.zero;
  }

  /// Refundable amount left on one payment.
  Money refundableOn(String paymentId) {
    final payment = payments.where((p) => p.id == paymentId).firstOrNull;
    if (payment == null || payment.status != PaymentStatus.succeeded) {
      return Money.zero;
    }
    final already = Money.sum(
      refunds
          .where(
            (r) => r.paymentId == paymentId && r.status != RefundStatus.failed,
          )
          .map((r) => r.amount),
    );
    final value = payment.amount - already;
    return value.paise > 0 ? value : Money.zero;
  }

  /// A cancelled order whose payment has not been returned yet.
  bool get refundDue => isVoid && netPaid.paise > 0;

  PaymentTransaction? get lastPayment => payments.isEmpty
      ? null
      : payments.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);

  PaymentTransaction? get latestSuccessfulPayment {
    final done = payments.where((p) => p.status == PaymentStatus.succeeded);
    if (done.isEmpty) return null;
    return done.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b);
  }

  InvoiceStatus get status {
    final paid = amountPaid;
    final refunded = amountRefunded;
    if (isVoid && paid.isZero) return InvoiceStatus.voided;
    if (paid.paise > 0 && refunded.paise >= paid.paise) {
      return InvoiceStatus.refunded;
    }
    if (refunded.paise > 0) return InvoiceStatus.partiallyRefunded;
    if (hasPendingPayment) return InvoiceStatus.pending;
    if (outstanding.isZero) return InvoiceStatus.paid;
    if (paid.paise > 0) return InvoiceStatus.partiallyPaid;
    if (lastPayment?.status == PaymentStatus.failed) {
      return InvoiceStatus.failed;
    }
    return InvoiceStatus.unpaid;
  }

  /// Methods used for successful payments, e.g. "UPI + Cash".
  String get methodsLabel {
    final methods = {
      for (final p in payments)
        if (p.status == PaymentStatus.succeeded) p.method.label,
    };
    return methods.isEmpty ? '—' : methods.join(' + ');
  }

  bool get isSimulated => payments.any((p) => p.isSimulated);

  /// Some of the money counted as paid came from demo payments.
  bool get hasDemoPayments =>
      payments.any((p) => p.isSimulated && p.status == PaymentStatus.succeeded);

  /// Notice printed on demo bills and receipts, or null for real ones.
  String? get demoNotice => switch ((isDemoSample, isSimulated)) {
    (true, true) =>
      'Sample bill included with the demo. Its payments are simulated: no '
          'money was charged or transferred.',
    (true, false) => 'Sample bill included with the demo, not a real sale.',
    (false, true) =>
      'Demo payment: simulated, not verified by any bank or payment '
          'provider. No money was charged or transferred.',
    (false, false) => null,
  };

  /// A recorded payment ends any counter request it settles.
  Invoice withPayment(PaymentTransaction payment, {bool atCounter = false}) {
    final exists = payments.any((p) => p.id == payment.id);
    final next = _copyWith(
      payments: exists
          ? [for (final p in payments) p.id == payment.id ? payment : p]
          : [...payments, payment],
    );
    return atCounter || next.payableNow.isZero && !next.hasPendingPayment
        ? next.withCounterRequest(null)
        : next;
  }

  Invoice withCounterRequest(CounterRequest? request) => Invoice(
    id: id,
    billNumber: billNumber,
    orderId: orderId,
    tableNumber: tableNumber,
    createdAt: createdAt,
    lines: lines,
    amounts: amounts,
    restaurant: restaurant,
    payments: payments,
    refunds: refunds,
    isVoid: isVoid,
    voidReason: voidReason,
    isDemoSample: isDemoSample,
    counterRequest: request,
  );

  Invoice withRefund(RefundRecord refund) =>
      _copyWith(refunds: [...refunds, refund]);

  Invoice voided(String reason) => _copyWith(isVoid: true, voidReason: reason);

  Invoice _copyWith({
    List<PaymentTransaction>? payments,
    List<RefundRecord>? refunds,
    bool? isVoid,
    String? voidReason,
  }) => Invoice(
    id: id,
    billNumber: billNumber,
    orderId: orderId,
    tableNumber: tableNumber,
    createdAt: createdAt,
    lines: lines,
    amounts: amounts,
    restaurant: restaurant,
    payments: payments ?? this.payments,
    refunds: refunds ?? this.refunds,
    isVoid: isVoid ?? this.isVoid,
    voidReason: voidReason ?? this.voidReason,
    isDemoSample: isDemoSample,
    counterRequest: counterRequest,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': billNumber,
    'order': orderId,
    'table': tableNumber,
    'createdAt': createdAt.toIso8601String(),
    'lines': [for (final line in lines) line.toJson()],
    'amounts': amounts.toJson(),
    'restaurant': restaurant.toJson(),
    if (payments.isNotEmpty) 'payments': [for (final p in payments) p.toJson()],
    if (refunds.isNotEmpty) 'refunds': [for (final r in refunds) r.toJson()],
    if (isVoid) 'void': true,
    if (voidReason.isNotEmpty) 'voidReason': voidReason,
    if (isDemoSample) 'demo': true,
    if (counterRequest case final request?) 'counterRequest': request.toJson(),
  };
}
