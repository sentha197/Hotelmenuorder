import '../models/billing.dart';
import '../models/inventory.dart';
import '../models/menu_item.dart';
import '../models/order_feedback.dart';
import '../models/order_status.dart';
import '../models/restaurant_order.dart';
import '../models/restaurant_settings.dart';
import '../models/staff.dart';
import '../repositories/billing_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/menu_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/staff_repository.dart';
import '../services/payment_gateway.dart';
import '../state/access.dart';
import '../state/billing_controller.dart';
import '../state/order_controller.dart';
import '../state/settings_controller.dart';
import '../utils/currency.dart';
import 'api_auth.dart';
import 'api_client.dart';

/// Turns API failures into the exceptions the controllers and screens
/// already handle, keeping the server's message.
Never rethrowAsAppError(ApiException error) {
  if (error.isUnauthorized) throw const SessionExpiredException();
  throw ValidationException(error.message);
}

Future<T> _guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (error) {
    rethrowAsAppError(error);
  }
}

List<Map<String, dynamic>> _list(Object? json) => [
  for (final item in json! as List) item as Map<String, dynamic>,
];

/// Staff data the signed-in role may not see (or anything before signing
/// in) loads as [fallback] instead of failing the whole screen.
Future<T> _visible<T>(Future<T> Function() call, T fallback) async {
  try {
    return await call();
  } on ApiException catch (error) {
    if (error.isUnauthorized || error.isForbidden) return fallback;
    rethrow;
  }
}

/// A staff endpoint, or its public counterpart before anyone has signed in.
/// [signedIn] (staff apps) skips the staff call, which can only be refused,
/// while there is no session.
Future<Object?> _staffOrPublic(
  ApiClient api,
  bool staff,
  String staffPath,
  String publicPath, {
  bool Function()? signedIn,
}) async {
  if (!staff || !(signedIn?.call() ?? true)) return api.get(publicPath);
  try {
    return await api.get(staffPath);
  } on ApiException catch (error) {
    if (error.isUnauthorized) return api.get(publicPath);
    rethrow;
  }
}

const _demoOnly = 'Resetting data is only available in the offline demo.';

/// Menu from the API: guests get the public menu, staff the full one
/// (archived dishes and inactive categories included).
class HttpMenuRepository implements MenuRepository, DishImageUploader {
  HttpMenuRepository(this._api, {required this.staff, this.signedIn});

  final ApiClient _api;
  final bool staff;

  /// Staff apps: whether a staff session exists.
  final bool Function()? signedIn;
  Map<String, dynamic>? _pending;

  Future<Map<String, dynamic>> _menu() async =>
      (await _staffOrPublic(
            _api,
            staff,
            '/admin/menu',
            '/menu',
            signedIn: signedIn,
          ))!
          as Map<String, dynamic>;

  // fetchCategories and fetchMenu are called in turn; one request serves
  // both.
  @override
  Future<List<MenuCategory>> fetchCategories() async {
    final json = _pending = await _menu();
    return [
      for (final c in _list(json['categories'])) MenuCategory.fromJson(c),
    ];
  }

  @override
  Future<List<MenuItem>> fetchMenu() async {
    final json = _pending ?? await _menu();
    _pending = null;
    final categories = {
      for (final c in _list(json['categories']))
        c['id'] as String: MenuCategory.fromJson(c),
    };
    return [
      for (final item in _list(json['items']))
        MenuItem.fromJson(item, categories: categories),
    ];
  }

  @override
  Future<void> saveItem(MenuItem item) => _guarded(
    () => _api.put(
      '/admin/menu/items/${Uri.encodeComponent(item.id)}',
      item.toJson(),
    ),
  );

  @override
  Future<void> saveCategories(List<MenuCategory> categories) => _guarded(
    () => _api.put('/admin/menu/categories', [
      for (final c in categories) c.toJson(),
    ]),
  );

  @override
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async {
    final json = await _api.postFile(
      '/admin/uploads/dish-images',
      field: 'file',
      bytes: bytes,
      filename: filename,
    );
    final url = (json as Map<String, dynamic>?)?['url'];
    if (url is! String || url.isEmpty) {
      throw const ApiException(
        502,
        'badUploadResponse',
        'The photo was uploaded but the server did not return its address.',
      );
    }
    return url;
  }

  @override
  Future<void> reset() => throw StateError(_demoOnly);
}

/// Restaurant settings and tables from the API.
class HttpSettingsRepository implements SettingsRepository {
  HttpSettingsRepository(this._api, {required this.staff, this.signedIn});

  final ApiClient _api;
  final bool staff;

  /// Staff apps: whether a staff session exists.
  final bool Function()? signedIn;

  @override
  Future<RestaurantSettings> fetchSettings() async =>
      RestaurantSettings.fromJson(
        (await _staffOrPublic(
              _api,
              staff,
              '/admin/settings',
              '/settings',
              signedIn: signedIn,
            ))!
            as Map<String, dynamic>,
      );

  @override
  Future<void> saveSettings(RestaurantSettings settings) =>
      _guarded(() => _api.put('/admin/settings', settings.toJson()));

  /// Guests get each table's number and whether it takes orders.
  @override
  Future<List<RestaurantTable>> fetchTables() async => [
    for (final t in _list(
      await _staffOrPublic(
        _api,
        staff,
        '/admin/tables',
        '/tables',
        signedIn: signedIn,
      ),
    ))
      RestaurantTable.fromJson(t),
  ];

  @override
  Future<void> saveTables(List<RestaurantTable> tables) => _guarded(
    () => _api.put('/admin/tables', [for (final t in tables) t.toJson()]),
  );

  @override
  Future<void> reset() => throw StateError(_demoOnly);
}

/// Orders from the API. Guests submit and read their own session's orders;
/// staff read every recent order and move them through the workflow. The
/// server prices every order from its own menu.
class HttpOrderRepository implements OrderRepository {
  HttpOrderRepository(this._api, {required this.staff, this.historyDays = 90});

  final ApiClient _api;
  final bool staff;

  /// How far back staff screens load orders (open orders always load).
  final int historyDays;

  @override
  Future<List<RestaurantOrder>> fetchOrders() => _visible(() async {
    final json = staff
        ? await _api.get(
            '/admin/orders',
            query: {
              'from': DateTime.now()
                  .toUtc()
                  .subtract(Duration(days: historyDays))
                  .toIso8601String(),
            },
          )
        : await _api.get('/orders');
    return [for (final o in _list(json)) RestaurantOrder.fromJson(o)];
  }, const <RestaurantOrder>[]);

  @override
  Future<RestaurantOrder> submitOrder(OrderDraft draft) async {
    final request = draft.request;
    if (request == null) {
      throw StateError('Backend orders need the cart lines, not prices.');
    }
    try {
      final json = await _api.post(staff ? '/admin/orders' : '/orders', {
        'lines': request.lines,
        'instructions': draft.specialInstructions,
        'offerCode': ?request.offerCode,
        'idempotencyKey': request.idempotencyKey,
        // The type the guest or staff member confirmed. For guests the
        // server checks it against their session.
        'orderType': draft.type.name,
        // Takeaway is table 0, which servers from before the order type was
        // sent also understand.
        if (staff) 'tableNumber': draft.tableNumber,
        // The total the guest saw; the server refuses if prices changed.
        'expectedTotal': draft.bill.total.paise,
      });
      return RestaurantOrder.fromJson(json! as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.isUnauthorized && staff) throw const SessionExpiredException();
      final reason = switch (error.code) {
        _ when error.isUnauthorized => CheckoutError.sessionExpired,
        'tableUnavailable' || 'tableInactive' => CheckoutError.tableUnavailable,
        // `parcelUnavailable` from servers before the rename.
        'takeawayUnavailable' ||
        'parcelUnavailable' => CheckoutError.takeawayUnavailable,
        'orderTypeMismatch' => CheckoutError.sessionExpired,
        'itemsUnavailable' ||
        'invalidOptions' => CheckoutError.itemsUnavailable,
        'emptyCart' => CheckoutError.emptyCart,
        'missingTable' => CheckoutError.missingTable,
        _ => CheckoutError.failed,
      };
      // Known reasons have their own wording; otherwise the server's (e.g.
      // prices changed), unless it was unreachable or failed.
      final known =
          reason != CheckoutError.failed &&
          reason != CheckoutError.itemsUnavailable;
      throw CheckoutException(
        reason,
        detail: known || error.isOffline || error.status >= 500
            ? null
            : error.message,
      );
    }
  }

  /// The kitchen simulator exists only in the offline demo.
  @override
  Future<RestaurantOrder> advanceStatus(String orderId) =>
      throw StateError('Order status is changed by restaurant staff.');

  @override
  Future<RestaurantOrder> updateStatus(
    String orderId,
    OrderStatus target, {
    String reason = '',
  }) => _guarded(() async {
    final json = await _api.post(
      '/admin/orders/${Uri.encodeComponent(orderId)}/status',
      {'target': target.name, if (reason.isNotEmpty) 'reason': reason},
    );
    return RestaurantOrder.fromJson(json! as Map<String, dynamic>);
  });

  @override
  Future<RestaurantOrder> submitFeedback(
    String orderId,
    OrderFeedback feedback,
  ) async {
    try {
      final json = await _api.post(
        '/orders/${Uri.encodeComponent(orderId)}/feedback',
        {'rating': feedback.rating, 'comment': feedback.comment},
      );
      return RestaurantOrder.fromJson(json! as Map<String, dynamic>);
    } on ApiException catch (error) {
      if (error.isUnauthorized) throw const SessionExpiredException();
      throw StateError(error.message);
    }
  }

  @override
  Future<void> reset() => throw StateError(_demoOnly);
}

/// Bills are read from the API; their payment state is never written by
/// the app (see [HttpBillingBackend]).
class HttpBillingRepository implements BillingRepository {
  HttpBillingRepository(
    this._api, {
    required this.staff,
    this.historyDays = 90,
  });

  final ApiClient _api;
  final bool staff;
  final int historyDays;

  @override
  Future<List<Invoice>> fetchInvoices() => _visible(() async {
    final json = staff
        ? await _api.get(
            '/admin/bills',
            query: {
              'from': DateTime.now()
                  .toUtc()
                  .subtract(Duration(days: historyDays))
                  .toIso8601String(),
            },
          )
        : await _api.get('/bills');
    return [for (final i in _list(json)) Invoice.fromJson(i)];
  }, const <Invoice>[]);

  @override
  Future<void> saveInvoice(Invoice invoice) =>
      throw StateError('Bills are recorded by the server.');

  @override
  Future<void> replaceAll(List<Invoice> invoices) =>
      throw StateError(_demoOnly);
}

/// Payments, refunds and reconciliation, decided and recorded by the
/// server. Online payments go through the server's payment provider; the
/// app only displays the verified result.
class HttpBillingBackend implements BillingBackend {
  HttpBillingBackend(this._api);

  final ApiClient _api;

  Future<T> _payment<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (error) {
      if (error.isUnauthorized) throw const SessionExpiredException();
      throw PaymentException(error.message);
    }
  }

  static (PaymentTransaction, Invoice) _result(Object? json) {
    final map = json! as Map<String, dynamic>;
    return (
      PaymentTransaction.fromJson(map['payment'] as Map<String, dynamic>),
      Invoice.fromJson(map['invoice'] as Map<String, dynamic>),
    );
  }

  @override
  Future<Invoice> billForOrder(String orderId) => _payment(() async {
    final json = await _api.get('/orders/${Uri.encodeComponent(orderId)}/bill');
    return Invoice.fromJson(json! as Map<String, dynamic>);
  });

  @override
  Future<(PaymentTransaction, Invoice)> payOnline({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String idempotencyKey,
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) => _payment(() async {
    final intent =
        (await _api.post('/payments/intents', {
              'invoiceId': invoiceId,
              'amount': amount.paise,
              'method': method.name,
              'idempotencyKey': idempotencyKey,
            }))!
            as Map<String, dynamic>;
    final payment = intent['payment'] as Map<String, dynamic>;
    if (intent['simulated'] != true) {
      // A real provider opens its own checkout here and the app sends its
      // signed result to /confirm; none is integrated in this build.
      throw const PaymentException(
        'Online payment is not available in this app yet. Please pay at the '
        'counter.',
      );
    }
    return _result(
      await _api.post('/payments/${payment['id']}/confirm', {
        'simulatedOutcome': switch (outcome) {
          SimulatedOutcome.success => 'success',
          SimulatedOutcome.failure => 'failure',
          SimulatedOutcome.cancel => 'cancel',
        },
      }),
    );
  });

  @override
  Future<(PaymentTransaction, Invoice)> refreshPayment(String paymentId) =>
      _payment(() async => _result(await _api.get('/payments/$paymentId')));

  @override
  Future<(PaymentTransaction, Invoice)> recordCounterPayment({
    required String invoiceId,
    required Money amount,
    required PaymentMethodType method,
    required String reference,
    required String idempotencyKey,
  }) => _payment(
    () async => _result(
      await _api.post('/admin/bills/$invoiceId/payments', {
        'amount': amount.paise,
        'method': method.name,
        'reference': reference,
        'idempotencyKey': idempotencyKey,
      }),
    ),
  );

  @override
  Future<(RefundRecord, Invoice)> refund({
    required String paymentId,
    required Money amount,
    required String reason,
    required String idempotencyKey,
  }) => _payment(() async {
    final json =
        (await _api.post('/admin/payments/$paymentId/refunds', {
              'amount': amount.paise,
              'reason': reason,
              'idempotencyKey': idempotencyKey,
            }))!
            as Map<String, dynamic>;
    return (
      RefundRecord.fromJson(json['refund'] as Map<String, dynamic>),
      Invoice.fromJson(json['invoice'] as Map<String, dynamic>),
    );
  });

  @override
  Future<(int, Invoice)> reconcile(String invoiceId) => _payment(() async {
    final json =
        (await _api.post('/admin/bills/$invoiceId/reconcile'))!
            as Map<String, dynamic>;
    return (
      json['resolved'] as int,
      Invoice.fromJson(json['invoice'] as Map<String, dynamic>),
    );
  });
}

/// Staff accounts and the activity log from the API. Passwords are hashed
/// by the server; the server also writes every audit entry itself.
class HttpStaffRepository implements StaffRepository, StaffDirectory {
  HttpStaffRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<StaffAccount>> fetchStaff() => _visible(
    () async => [
      for (final s in _list(await _api.get('/admin/staff'))) staffFromApi(s),
    ],
    const <StaffAccount>[],
  );

  @override
  Future<void> saveStaff(StaffAccount account) =>
      throw StateError('Use StaffDirectory for server-side staff changes.');

  @override
  Future<List<AuditEvent>> fetchAudit() => _visible(
    () async => [
      for (final e in _list(
        await _api.get('/admin/audit', query: {'limit': '500'}),
      ))
        AuditEvent.fromJson(e),
    ],
    const <AuditEvent>[],
  );

  /// The server records audit entries for every privileged request.
  @override
  Future<void> appendAudit(AuditEvent event) async {}

  @override
  Future<void> reset() => throw StateError(_demoOnly);

  @override
  Future<StaffAccount> create({
    required String name,
    required String email,
    required StaffRole role,
    required String password,
  }) => _guarded(() async {
    final json = await _api.post('/admin/staff', {
      'name': name,
      'email': email,
      'role': role.name,
      'password': password,
    });
    return staffFromApi(json! as Map<String, dynamic>);
  });

  @override
  Future<StaffAccount> update(
    String staffId, {
    String? name,
    StaffRole? role,
    bool? active,
  }) => _guarded(() async {
    final json = await _api.patch('/admin/staff/$staffId', {
      'name': ?name,
      if (role != null) 'role': role.name,
      'active': ?active,
    });
    return staffFromApi(json! as Map<String, dynamic>);
  });

  @override
  Future<void> resetPassword(String staffId, String password) => _guarded(
    () => _api.post('/admin/staff/$staffId/password', {'password': password}),
  );
}

/// Stock from the API. Quantities change only through recorded adjustments
/// that the server applies (and that may mark linked dishes sold out).
class HttpInventoryRepository implements InventoryRepository, StockLedger {
  HttpInventoryRepository(this._api);

  final ApiClient _api;
  Map<String, dynamic>? _pending;

  Future<Map<String, dynamic>> _load() => _visible(
    () async => (await _api.get('/admin/inventory'))! as Map<String, dynamic>,
    const {'items': <Object>[], 'movements': <Object>[]},
  );

  @override
  Future<List<InventoryItem>> fetchItems() async {
    final json = _pending = await _load();
    return [for (final i in _list(json['items'])) InventoryItem.fromJson(i)];
  }

  @override
  Future<List<StockMovement>> fetchMovements() async {
    final json = _pending ?? await _load();
    _pending = null;
    return [
      for (final m in _list(json['movements'])) StockMovement.fromJson(m),
    ];
  }

  @override
  Future<void> saveItem(InventoryItem item) =>
      throw StateError('Use StockLedger for server-side stock changes.');

  @override
  Future<void> addMovement(StockMovement movement) =>
      throw StateError('Use StockLedger for server-side stock changes.');

  @override
  Future<void> reset() => throw StateError(_demoOnly);

  Map<String, Object?> _body(InventoryItem item, {double? initial}) => {
    'name': item.name,
    'unit': item.unit,
    'reorder': item.reorderLevel,
    'supplier': item.supplier,
    'dishes': item.linkedDishIds,
    'initialQuantity': ?initial,
  };

  @override
  Future<InventoryItem> create(InventoryItem item) => _guarded(() async {
    final json = await _api.post(
      '/admin/inventory',
      _body(item, initial: item.quantity),
    );
    return InventoryItem.fromJson(json! as Map<String, dynamic>);
  });

  @override
  Future<InventoryItem> update(InventoryItem item) => _guarded(() async {
    final json = await _api.put('/admin/inventory/${item.id}', _body(item));
    return InventoryItem.fromJson(json! as Map<String, dynamic>);
  });

  @override
  Future<InventoryItem> adjust(String itemId, double change, String reason) =>
      _guarded(() async {
        final json = await _api.post('/admin/inventory/$itemId/adjustments', {
          'change': change,
          'reason': reason,
        });
        return InventoryItem.fromJson(json! as Map<String, dynamic>);
      });
}

/// Server-side staff account changes (backend mode).
abstract interface class StaffDirectory {
  Future<StaffAccount> create({
    required String name,
    required String email,
    required StaffRole role,
    required String password,
  });

  Future<StaffAccount> update(
    String staffId, {
    String? name,
    StaffRole? role,
    bool? active,
  });

  Future<void> resetPassword(String staffId, String password);
}

/// Server-side stock changes (backend mode).
abstract interface class StockLedger {
  Future<InventoryItem> create(InventoryItem item);

  Future<InventoryItem> update(InventoryItem item);

  Future<InventoryItem> adjust(String itemId, double change, String reason);
}
