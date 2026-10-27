/// Test helpers shared by the DineQR packages and apps (fakes for access
/// checks and quick ways to place orders). Not used by app code.
library;

import 'dart:async';

import 'dineqr_core.dart';

MenuItem dish(String id) => demoMenuItems.firstWhere((item) => item.id == id);

StaffAccount staffWith(StaffRole role, {String id = 'T1'}) => StaffAccount(
  id: id,
  name: 'Test ${role.label}',
  email: '${role.name}@test.local',
  role: role,
  passwordHash: '',
  salt: '',
  createdAt: DateTime.utc(2026),
);

/// Access guard for a fixed role, or signed out when [actor] is null.
class FakeGuard implements AccessGuard {
  FakeGuard([StaffRole? role]) : actor = role == null ? null : staffWith(role);

  @override
  StaffAccount? actor;

  @override
  bool can(Permission permission) => actor?.can(permission) ?? false;

  @override
  void require(Permission permission) {
    final who = actor;
    if (who == null) throw const SessionExpiredException();
    if (!who.can(permission)) throw PermissionDeniedException(permission);
  }
}

/// Places a guest order for [items] (dish id → quantity) at [table].
Future<RestaurantOrder> placeTestOrder(
  OrderController orders,
  Map<String, int> items, {
  int table = 5,
}) {
  final cart = CartController(MemoryStore());
  for (final MapEntry(:key, :value) in items.entries) {
    cart.add(dish(key), quantity: value);
  }
  return orders.placeOrder(cart: cart, tableNumber: table);
}

Future<OrderController> testOrders(
  MemoryStore store, {
  AccessGuard? guard,
  AuditLog? audit,
}) async {
  final orders = OrderController(
    LocalOrderRepository(store, latency: Duration.zero, seedDemoOrders: false),
    guard: guard,
    audit: audit,
  );
  await orders.load();
  return orders;
}

/// An in-memory stand-in for the server's UPI rules, enough to drive the
/// controllers and screens of both apps. It records every call and, like the
/// real server, never lets a guest's claim settle a bill: only
/// [verifyUpiPayment] does.
class FakeUpiBackend implements BillingBackend {
  FakeUpiBackend(
    this.invoice, {
    this.settings = const UpiSettings(
      enabled: true,
      upiId: 'cafe@okhdfcbank',
      payeeName: 'Test Cafe',
    ),
  });

  /// The server's copy of the bill.
  Invoice invoice;

  /// The payee guests are told about.
  UpiSettings settings;

  /// Every call made, e.g. `start:45000`, `claim:PAY000001:REF`.
  final calls = <String>[];

  /// When set, [startUpiPayment] waits for it (to test double taps).
  Completer<void>? holdStart;

  /// When true, reading the payee fails (the server cannot be reached).
  bool failSettings = false;

  /// When set, starting a payment fails with this message.
  String? failStart;

  /// When set, telling the restaurant "I paid" fails with this message.
  String? failClaim;

  /// The latest payment on the bill.
  PaymentTransaction get latest => invoice.payments.last;

  PaymentTransaction _only(String id) =>
      invoice.payments.firstWhere((p) => p.id == id);

  (PaymentTransaction, Invoice) _replace(PaymentTransaction payment) {
    invoice = invoice.withPayment(payment);
    return (payment, invoice);
  }

  PaymentTransaction _pending(
    String id,
    Money amount, {
    DateTime? claimedAt,
    String reference = '',
  }) => PaymentTransaction(
    id: id,
    invoiceId: invoice.id,
    orderId: invoice.orderId,
    amount: amount,
    method: PaymentMethodType.upi,
    status: PaymentStatus.pending,
    provider: PaymentTransaction.upiDirectProvider,
    createdAt: DateTime.utc(2026, 10, 25, 7, 1),
    updatedAt: DateTime.utc(2026, 10, 25, 7, 1),
    idempotencyKey: 'key-$id',
    reference: reference,
    claimedAt: claimedAt,
  );

  @override
  Future<UpiSettings> upiSettings() async {
    calls.add('upiSettings');
    if (failSettings) throw const PaymentException('offline');
    return settings;
  }

  @override
  Future<(PaymentTransaction, Invoice)> startUpiPayment({
    required String invoiceId,
    required Money amount,
    required String idempotencyKey,
  }) async {
    calls.add('start:${amount.paise}');
    await holdStart?.future;
    final message = failStart;
    if (message != null) throw PaymentException(message);
    return _replace(_pending('PAY00000${invoice.payments.length + 1}', amount));
  }

  @override
  Future<(PaymentTransaction, Invoice)> claimUpiPayment(
    String paymentId, {
    String reference = '',
  }) async {
    calls.add('claim:$paymentId:$reference');
    final message = failClaim;
    if (message != null) throw PaymentException(message);
    final current = _only(paymentId);
    if (current.status != PaymentStatus.pending) return (current, invoice);
    return _replace(
      _pending(
        paymentId,
        current.amount,
        claimedAt: DateTime.utc(2026, 10, 25, 7, 5),
        reference: reference,
      ),
    );
  }

  @override
  Future<(PaymentTransaction, Invoice)> cancelUpiPayment(
    String paymentId,
  ) async {
    calls.add('cancel:$paymentId');
    final current = _only(paymentId);
    if (current.status != PaymentStatus.pending) return (current, invoice);
    return _replace(current.copyWith(status: PaymentStatus.cancelled));
  }

  @override
  Future<(PaymentTransaction, Invoice)> verifyUpiPayment(
    String paymentId, {
    required String reference,
  }) async {
    calls.add('verify:$paymentId:$reference');
    return _replace(
      _only(
        paymentId,
      ).copyWith(status: PaymentStatus.succeeded, reference: reference),
    );
  }

  @override
  Future<(PaymentTransaction, Invoice)> rejectUpiPayment(
    String paymentId, {
    String reason = '',
  }) async {
    calls.add('reject:$paymentId:$reason');
    return _replace(
      _only(
        paymentId,
      ).copyWith(status: PaymentStatus.failed, failureReason: reason),
    );
  }

  @override
  Future<(PaymentTransaction, Invoice)> refreshPayment(String paymentId) async {
    calls.add('refresh:$paymentId');
    return (_only(paymentId), invoice);
  }

  @override
  Future<Invoice> billForOrder(String orderId) async => invoice;

  @override
  Future<(PaymentTransaction, Invoice)> payOnline({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String idempotencyKey,
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) => throw UnimplementedError('payOnline');

  @override
  Future<(PaymentTransaction, Invoice)> recordCounterPayment({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String reference,
    required String idempotencyKey,
  }) => throw UnimplementedError('recordCounterPayment');

  @override
  Future<(RefundRecord, Invoice)> refund({
    required String paymentId,
    required Money amount,
    required String reason,
    required String idempotencyKey,
  }) => throw UnimplementedError('refund');

  @override
  Future<(int, Invoice)> reconcile(String invoiceId) =>
      throw UnimplementedError('reconcile');
}

/// In-memory payment settings, for tests of the settings controller and the
/// admin screens. Behaves like the server for what the tests need: it keeps
/// what was saved and hands out a URL for an uploaded QR picture.
class FakePaymentSettingsRepository
    implements PaymentSettingsRepository, UpiQrUploader {
  FakePaymentSettingsRepository({
    this.stored = const UpiSettings(),
    this.automaticAvailable = false,
  });

  UpiSettings stored;

  /// Whether the "server" has a bank or payment-provider integration.
  bool automaticAvailable;

  /// Every settings object saved, in order.
  final saves = <UpiSettings>[];

  /// The file name of every picture uploaded, in order.
  final uploads = <String>[];

  /// The address returned for uploaded pictures.
  String uploadUrl = 'https://x.test/uploads/upi/new.png';

  /// When set, reading the settings fails with it.
  Object? fetchError;

  /// When set, the next save fails with it.
  Object? saveError;

  @override
  bool get isAvailable => true;

  PaymentSettingsSnapshot get _snapshot => PaymentSettingsSnapshot(
    upi: stored,
    automaticVerificationAvailable: automaticAvailable,
  );

  @override
  Future<PaymentSettingsSnapshot> fetch() async {
    final error = fetchError;
    if (error != null) throw error;
    return _snapshot;
  }

  @override
  Future<PaymentSettingsSnapshot> save(UpiSettings settings) async {
    final error = saveError;
    if (error != null) {
      saveError = null;
      throw error;
    }
    saves.add(settings);
    stored = settings;
    return _snapshot;
  }

  @override
  Future<String> uploadUpiQr({
    required List<int> bytes,
    required String filename,
  }) async {
    uploads.add(filename);
    return uploadUrl;
  }
}
