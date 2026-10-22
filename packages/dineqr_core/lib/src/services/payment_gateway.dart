import '../models/billing.dart';
import '../utils/currency.dart';
import '../utils/restaurant_time.dart';

/// A request to collect [amount] against one bill.
class PaymentRequest {
  const PaymentRequest({
    required this.invoiceId,
    required this.orderId,
    required this.amount,
    required this.method,
    required this.idempotencyKey,
  });

  final String invoiceId;
  final String orderId;
  final Money amount;
  final PaymentMethodType method;

  /// The same key must never be charged twice.
  final String idempotencyKey;
}

/// A *verified* outcome. Gateways only return [PaymentStatus.succeeded]
/// after their backend has confirmed the payment with the provider.
class PaymentResult {
  const PaymentResult({
    required this.status,
    this.reference = '',
    this.failureReason = '',
  });

  final PaymentStatus status;

  /// Provider transaction id.
  final String reference;
  final String failureReason;
}

/// What the demo simulator should do for the next payment. Only used when
/// [PaymentGateway.isSimulated] is true.
enum SimulatedOutcome {
  success('Success'),
  failure('Failure'),
  cancel('Cancelled by guest');

  const SimulatedOutcome(this.label);

  final String label;
}

/// Payment provider integration.
///
/// A production implementation (e.g. for Razorpay) must:
/// 1. ask the restaurant backend to create a provider order for the bill;
///    the backend recalculates the amount from its own order records and
///    holds the secret keys,
/// 2. open the provider checkout with the public key and that order id,
/// 3. send the provider's response (payment id, order id, signature) back to
///    the backend, which verifies the signature before marking anything paid,
/// 4. return the verified status here.
///
/// See `docs/BACKEND_INTEGRATION.md` for the endpoint contract.
abstract interface class PaymentGateway {
  String get providerName;

  /// True for the demo simulator: no money is ever moved.
  bool get isSimulated;

  /// Online methods this provider can actually process.
  Set<PaymentMethodType> get supportedMethods;

  Future<PaymentResult> collect(
    PaymentRequest request, {
    SimulatedOutcome outcome = SimulatedOutcome.success,
  });

  /// Final status of a payment whose result never arrived (app closed,
  /// network lost). Real gateways ask the backend to query the provider.
  Future<PaymentResult> checkStatus(PaymentTransaction pending);

  Future<PaymentResult> refund(
    PaymentTransaction payment,
    Money amount, {
    required String reason,
    required String idempotencyKey,
  });
}

/// Offline demo provider. Clearly labelled everywhere it appears; it never
/// contacts a bank or charges a card.
class SimulatedPaymentGateway implements PaymentGateway {
  SimulatedPaymentGateway({
    this.processingTime = const Duration(milliseconds: 1400),
  });

  final Duration processingTime;

  /// Results by idempotency key: replaying a request returns the first
  /// result instead of charging again.
  final Map<String, PaymentResult> _results = {};

  @override
  String get providerName => 'Demo simulator';

  @override
  bool get isSimulated => true;

  @override
  Set<PaymentMethodType> get supportedMethods =>
      PaymentMethodType.online.toSet();

  @override
  Future<PaymentResult> collect(
    PaymentRequest request, {
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) async {
    final previous = _results[request.idempotencyKey];
    if (previous != null) return previous;
    if (processingTime > Duration.zero) {
      await Future<void>.delayed(processingTime);
    }
    final result = switch (outcome) {
      SimulatedOutcome.success => PaymentResult(
        status: PaymentStatus.succeeded,
        reference: 'SIM-${Ids.random(10)}',
      ),
      SimulatedOutcome.failure => const PaymentResult(
        status: PaymentStatus.failed,
        failureReason: 'Declined by the demo simulator. No money was taken.',
      ),
      SimulatedOutcome.cancel => const PaymentResult(
        status: PaymentStatus.cancelled,
        failureReason: 'Payment cancelled before completion.',
      ),
    };
    _results[request.idempotencyKey] = result;
    return result;
  }

  @override
  Future<PaymentResult> checkStatus(PaymentTransaction pending) async =>
      _results[pending.idempotencyKey] ??
      const PaymentResult(
        status: PaymentStatus.failed,
        failureReason:
            'No confirmation was received, so nothing was charged (demo).',
      );

  @override
  Future<PaymentResult> refund(
    PaymentTransaction payment,
    Money amount, {
    required String reason,
    required String idempotencyKey,
  }) async {
    final previous = _results[idempotencyKey];
    if (previous != null) return previous;
    final result = PaymentResult(
      status: PaymentStatus.succeeded,
      reference: 'SIMRF-${Ids.random(10)}',
    );
    _results[idempotencyKey] = result;
    return result;
  }
}

/// Used when no payment provider is configured: guests pay at the counter
/// and online payment is not offered.
class UnavailablePaymentGateway implements PaymentGateway {
  const UnavailablePaymentGateway();

  @override
  String get providerName => 'Not configured';

  @override
  bool get isSimulated => false;

  @override
  Set<PaymentMethodType> get supportedMethods => const {};

  static const _result = PaymentResult(
    status: PaymentStatus.failed,
    failureReason: 'Online payments are not configured for this restaurant.',
  );

  @override
  Future<PaymentResult> collect(
    PaymentRequest request, {
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) async => _result;

  @override
  Future<PaymentResult> checkStatus(PaymentTransaction pending) async =>
      _result;

  @override
  Future<PaymentResult> refund(
    PaymentTransaction payment,
    Money amount, {
    required String reason,
    required String idempotencyKey,
  }) async => _result;
}
