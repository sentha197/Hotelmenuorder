import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/admin/admin_modules.dart';
import 'package:menu_order/core/utils/currency.dart';
import 'package:menu_order/core/utils/restaurant_time.dart';
import 'package:menu_order/data/models/billing.dart';
import 'package:menu_order/data/models/menu_item.dart';
import 'package:menu_order/data/models/order_status.dart';
import 'package:menu_order/data/models/restaurant_order.dart';
import 'package:menu_order/data/models/restaurant_settings.dart';
import 'package:menu_order/data/models/staff.dart';
import 'package:menu_order/data/repositories/billing_repository.dart';
import 'package:menu_order/data/repositories/menu_repository.dart';
import 'package:menu_order/data/repositories/order_repository.dart';
import 'package:menu_order/data/repositories/staff_repository.dart';
import 'package:menu_order/data/services/auth_service.dart';
import 'package:menu_order/data/services/payment_gateway.dart';
import 'package:menu_order/data/services/report_export.dart';
import 'package:menu_order/data/services/report_service.dart';
import 'package:menu_order/data/storage/key_value_store.dart';
import 'package:menu_order/features/qr_scanner/table_qr_parser.dart';
import 'package:menu_order/state/admin_session_controller.dart';
import 'package:menu_order/state/billing_controller.dart';
import 'package:menu_order/state/catalog_controller.dart';
import 'package:menu_order/state/order_controller.dart';
import 'package:menu_order/state/settings_controller.dart';
import 'package:menu_order/state/staff_controller.dart';

import 'support/fakes.dart';

void main() {
  group('staff sign-in', () {
    late MemoryStore store;
    late LocalStaffRepository staff;
    late DateTime now;

    DemoAuthService auth() =>
        DemoAuthService(staff, store, clock: () => now, maxAttempts: 3);

    setUp(() {
      store = MemoryStore();
      now = DateTime.utc(2026, 10, 17, 6);
      staff = LocalStaffRepository(
        store,
        seed: () => DemoCredentials.seedAccounts(now),
      );
    });

    test('valid demo credentials start an 8-hour session', () async {
      final result = await auth().signIn(
        ' Owner@DineQR.demo ',
        DemoCredentials.password,
      );
      expect(result.staff.role, StaffRole.owner);
      expect(result.session.expiresAt, now.add(const Duration(hours: 8)));
      expect(store.read(StorageKeys.adminSession), isNotNull);
      final accounts = await staff.fetchStaff();
      expect(
        accounts.every((a) => a.passwordHash != DemoCredentials.password),
        isTrue,
      );
    });

    test('wrong passwords and unknown emails get the same error', () async {
      Future<AuthError> errorFor(String email, String password) async {
        try {
          await auth().signIn(email, password);
        } on AuthException catch (error) {
          return error.error;
        }
        fail('expected an AuthException');
      }

      expect(
        await errorFor('owner@dineqr.demo', 'wrong-pass1'),
        AuthError.invalidCredentials,
      );
      expect(
        await errorFor('nobody@dineqr.demo', DemoCredentials.password),
        AuthError.invalidCredentials,
      );
      expect(await errorFor('', ''), AuthError.invalidInput);
    });

    test('repeated failures lock sign-in for a while', () async {
      final service = auth();
      for (var i = 0; i < 2; i++) {
        await expectLater(
          service.signIn('cashier@dineqr.demo', 'nope-1234'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.error,
              'error',
              AuthError.invalidCredentials,
            ),
          ),
        );
      }
      await expectLater(
        service.signIn('cashier@dineqr.demo', 'nope-1234'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.error,
            'error',
            AuthError.lockedOut,
          ),
        ),
      );
      // Even the right password is refused during the lockout.
      await expectLater(
        service.signIn('cashier@dineqr.demo', DemoCredentials.password),
        throwsA(isA<AuthException>()),
      );
      now = now.add(const Duration(minutes: 2));
      final result = await service.signIn(
        'cashier@dineqr.demo',
        DemoCredentials.password,
      );
      expect(result.staff.role, StaffRole.cashier);
    });

    test('deactivated accounts cannot sign in', () async {
      final accounts = await staff.fetchStaff();
      final kitchen = accounts.firstWhere((a) => a.role == StaffRole.kitchen);
      await staff.saveStaff(kitchen.copyWith(isActive: false));
      await expectLater(
        auth().signIn('kitchen@dineqr.demo', DemoCredentials.password),
        throwsA(
          isA<AuthException>().having(
            (e) => e.error,
            'error',
            AuthError.inactive,
          ),
        ),
      );
    });

    test('sessions are restored until they expire', () async {
      await auth().signIn('manager@dineqr.demo', DemoCredentials.password);
      now = now.add(const Duration(hours: 7));
      final restored = await auth().restore();
      expect(restored?.staff.role, StaffRole.manager);
      now = now.add(const Duration(hours: 2));
      expect(await auth().restore(), isNull);
      expect(store.read(StorageKeys.adminSession), isNull);
    });

    test('new passwords need letters, numbers and 8 characters', () {
      expect(PasswordHasher.validateNew('short1'), isNotNull);
      expect(PasswordHasher.validateNew('lettersonly'), isNotNull);
      expect(PasswordHasher.validateNew('12345678'), isNotNull);
      expect(PasswordHasher.validateNew('Kitchen2026'), isNull);
      final salt = PasswordHasher.newSalt();
      final hash = PasswordHasher.hash('Kitchen2026', salt);
      expect(PasswordHasher.matches('Kitchen2026', salt, hash), isTrue);
      expect(PasswordHasher.matches('kitchen2026', salt, hash), isFalse);
    });

    test('the session controller enforces permissions and expiry', () async {
      final audit = AuditLog(staff, clock: () => now);
      final session = AdminSessionController(auth(), audit, clock: () => now);
      expect(
        () => session.require(Permission.viewDashboard),
        throwsA(isA<SessionExpiredException>()),
      );

      await session.signIn('kitchen@dineqr.demo', DemoCredentials.password);
      expect(session.can(Permission.manageKitchen), isTrue);
      expect(
        () => session.require(Permission.collectPayments),
        throwsA(isA<PermissionDeniedException>()),
      );
      final events = await audit.events();
      expect(events.first.action, 'auth.sign_in');
      expect(events.first.actorRole, StaffRole.kitchen.label);

      now = now.add(const Duration(hours: 9));
      expect(session.isSignedIn, isFalse);
      expect(session.can(Permission.manageKitchen), isFalse);
      await session.checkExpiry();
      expect(session.takeEndedReason(), contains('expired'));
      expect(
        () => session.require(Permission.manageKitchen),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('roles', () {
    test('each role gets only the access it needs', () {
      expect(StaffRole.owner.permissions, Permission.values.toSet());

      const manager = StaffRole.manager;
      expect(manager.can(Permission.manageMenu), isTrue);
      expect(manager.can(Permission.manageInventory), isTrue);
      for (final p in [
        Permission.viewFinancials,
        Permission.exportReports,
        Permission.issueRefunds,
        Permission.manageStaff,
        Permission.manageSettings,
      ]) {
        expect(manager.can(p), isFalse, reason: p.name);
      }

      expect(StaffRole.cashier.can(Permission.collectPayments), isTrue);
      expect(StaffRole.cashier.can(Permission.issueRefunds), isFalse);
      expect(StaffRole.cashier.can(Permission.manageMenu), isFalse);

      expect(StaffRole.kitchen.can(Permission.manageKitchen), isTrue);
      expect(StaffRole.kitchen.can(Permission.serveOrders), isFalse);
      expect(StaffRole.kitchen.can(Permission.viewBills), isFalse);

      expect(StaffRole.waiter.can(Permission.serveOrders), isTrue);
      expect(StaffRole.waiter.can(Permission.collectPayments), isFalse);

      expect(StaffRole.accountant.can(Permission.issueRefunds), isTrue);
      expect(StaffRole.accountant.can(Permission.exportReports), isTrue);
      expect(StaffRole.accountant.can(Permission.manageMenu), isFalse);
    });

    test('navigation lists only the modules a role can open', () {
      expect(AdminModule.forRole(StaffRole.kitchen), [
        AdminModule.orders,
        AdminModule.kitchen,
        AdminModule.menu,
      ]);
      expect(AdminModule.forRole(StaffRole.owner), AdminModule.values);
      expect(
        AdminModule.forRole(StaffRole.cashier),
        isNot(contains(AdminModule.reports)),
      );
    });
  });

  group('order status updates', () {
    late MemoryStore store;
    late FakeGuard guard;
    late BillingController billing;
    late OrderController orders;

    setUp(() async {
      store = MemoryStore();
      guard = FakeGuard(StaffRole.kitchen);
      billing = BillingController(
        LocalBillingRepository(store),
        SimulatedPaymentGateway(processingTime: Duration.zero),
        guard: guard,
      );
      orders = OrderController(
        LocalOrderRepository(
          store,
          latency: Duration.zero,
          seedDemoOrders: false,
        ),
        guard: guard,
        onPlaced: billing.createForOrder,
        onCancelled: billing.voidForOrder,
      );
      await orders.load();
    });

    test('kitchen staff prepare orders but cannot serve or cancel', () async {
      final order = await placeTestOrder(orders, {'masala_dosa': 1});
      for (final target in [
        OrderStatus.accepted,
        OrderStatus.preparing,
        OrderStatus.readyToServe,
      ]) {
        final updated = await orders.updateStatus(order.id, target);
        expect(updated.status, target);
      }
      await expectLater(
        orders.updateStatus(order.id, OrderStatus.served),
        throwsA(isA<PermissionDeniedException>()),
      );
      guard.actor = staffWith(StaffRole.waiter);
      final served = await orders.updateStatus(order.id, OrderStatus.served);
      expect(served.statusTimes.keys, OrderStatus.flow);
    });

    test('stages cannot be skipped and cancelling needs a reason', () async {
      guard.actor = staffWith(StaffRole.manager);
      final order = await placeTestOrder(orders, {'masala_dosa': 1});
      await expectLater(
        orders.updateStatus(order.id, OrderStatus.served),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        orders.updateStatus(order.id, OrderStatus.cancelled),
        throwsA(isA<ValidationException>()),
      );
      final cancelled = await orders.updateStatus(
        order.id,
        OrderStatus.cancelled,
        reason: 'Guest left',
      );
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.cancelReason, 'Guest left');
      expect(billing.forOrder(order.id)!.isVoid, isTrue);
      await expectLater(
        orders.updateStatus(order.id, OrderStatus.accepted),
        throwsA(isA<ValidationException>()),
      );
    });

    test('signed-out callers are refused', () async {
      final order = await placeTestOrder(orders, {'masala_dosa': 1});
      guard.actor = null;
      await expectLater(
        orders.updateStatus(order.id, OrderStatus.accepted),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  });

  group('menu management', () {
    late MemoryStore store;
    late FakeGuard guard;
    late CatalogController catalog;

    setUp(() async {
      store = MemoryStore();
      guard = FakeGuard(StaffRole.manager);
      catalog = CatalogController(
        DemoMenuRepository(latency: Duration.zero, store: store),
        store,
        guard: guard,
      );
      await catalog.load();
    });

    test('dish edits are validated and need permission', () async {
      final dosa = catalog.byId('masala_dosa')!;
      expect(catalog.validateItem(dosa.copyWith(name: 'X')), isNotNull);
      expect(
        catalog.validateItem(dosa.copyWith(price: Money.zero)),
        startsWith('Price must be'),
      );
      expect(
        catalog.validateItem(dosa.copyWith(name: 'Chicken 65')),
        contains('already called'),
      );
      await expectLater(
        catalog.saveItem(dosa.copyWith(price: Money.zero)),
        throwsA(isA<ValidationException>()),
      );

      guard.actor = staffWith(StaffRole.kitchen);
      await expectLater(
        catalog.saveItem(dosa.copyWith(price: const Money.rupees(150))),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test(
      'price changes reach guests but never rewrite placed orders',
      () async {
        final orders = await testOrders(MemoryStore());
        final before = await placeTestOrder(orders, {'masala_dosa': 2});
        final oldTotal = before.bill.total;

        final dosa = catalog.byId('masala_dosa')!;
        await catalog.saveItem(
          dosa.copyWith(price: dosa.price + const Money.rupees(30)),
        );
        expect(
          catalog.byId('masala_dosa')!.price,
          dosa.price + const Money.rupees(30),
        );

        // Persisted: a fresh controller on the same storage sees the edit.
        final reloaded = CatalogController(
          DemoMenuRepository(latency: Duration.zero, store: store),
          store,
        );
        await reloaded.load();
        expect(
          reloaded.byId('masala_dosa')!.price,
          dosa.price + const Money.rupees(30),
        );

        expect(orders.byId(before.id)!.bill.total, oldTotal);
        expect(orders.byId(before.id)!.lines.single.unitPrice, dosa.price);
      },
    );

    test('sold-out and archived dishes', () async {
      await catalog.setAvailable('masala_dosa', false);
      final dosa = catalog.items.firstWhere((i) => i.id == 'masala_dosa');
      expect(dosa.isOrderable, isFalse);

      await catalog.setArchived('masala_dosa', true);
      expect(catalog.items.any((i) => i.id == 'masala_dosa'), isFalse);
      expect(catalog.allItems.any((i) => i.id == 'masala_dosa'), isTrue);
    });

    test(
      'categories: hidden categories hide their dishes, used ones stay',
      () async {
        await expectLater(
          catalog.deleteCategory(MenuCategory.desserts.id),
          throwsA(isA<ValidationException>()),
        );
        await catalog.setCategoryActive(MenuCategory.desserts.id, false);
        expect(catalog.categories, isNot(contains(MenuCategory.desserts)));
        expect(
          catalog.items.any((i) => i.category.id == MenuCategory.desserts.id),
          isFalse,
        );

        final id = catalog.newCategoryId('Breakfast');
        await catalog.saveCategory(
          MenuCategory(
            id: id,
            label: 'Breakfast',
            coverImage: '',
            sortOrder: 9,
          ),
        );
        expect(catalog.categoryById(id)?.label, 'Breakfast');
        await catalog.deleteCategory(id);
        expect(catalog.categoryById(id), isNull);
      },
    );
  });

  group('staff management', () {
    late MemoryStore store;
    late LocalStaffRepository repository;
    late FakeGuard guard;
    late StaffController staff;

    setUp(() async {
      store = MemoryStore();
      final now = DateTime.utc(2026, 10, 17);
      repository = LocalStaffRepository(
        store,
        seed: () => DemoCredentials.seedAccounts(now),
      );
      guard = FakeGuard();
      staff = StaffController(
        repository,
        guard,
        AuditLog(repository)..guard = guard,
      );
      await staff.load();
      guard.actor = staff.staff.firstWhere((a) => a.role == StaffRole.owner);
    });

    test('owners cannot lock themselves out', () async {
      final me = guard.actor!;
      await expectLater(
        staff.changeRole(me.id, StaffRole.cashier),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        staff.setActive(me.id, false),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      'new accounts are validated and stored without plain passwords',
      () async {
        await expectLater(
          staff.addStaff(
            name: 'Asha',
            email: 'asha@dineqr.demo',
            role: StaffRole.waiter,
            password: 'weak',
          ),
          throwsA(isA<ValidationException>()),
        );
        await expectLater(
          staff.addStaff(
            name: 'Dup',
            email: 'owner@dineqr.demo',
            role: StaffRole.waiter,
            password: 'Strong2026',
          ),
          throwsA(isA<ValidationException>()),
        );
        final account = await staff.addStaff(
          name: 'Asha',
          email: 'Asha@DineQR.demo',
          role: StaffRole.waiter,
          password: 'Strong2026',
        );
        expect(account.email, 'asha@dineqr.demo');
        expect(account.passwordHash, isNot(contains('Strong2026')));

        guard.actor = staffWith(StaffRole.manager);
        await expectLater(
          staff.setActive(account.id, false),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );
  });

  group('date ranges', () {
    late int original;

    setUp(() => original = RestaurantTime.offset.inMinutes);
    tearDown(() => RestaurantTime.configure(original));

    test('presets follow the restaurant time zone', () {
      RestaurantTime.configure(330); // UTC+5:30
      // 01:30 on 18 Oct in the restaurant.
      final now = DateTime.utc(2026, 10, 17, 20);
      final today = DateRange.preset(RangePreset.today, now);
      expect(today.start, DateTime.utc(2026, 10, 17, 18, 30));
      expect(today.end, DateTime.utc(2026, 10, 18, 18, 30));
      expect(today.contains(now), isTrue);
      expect(today.contains(today.end), isFalse);

      final yesterday = DateRange.preset(RangePreset.yesterday, now);
      expect(yesterday.end, today.start);
      expect(yesterday.dayCount, 1);

      final week = DateRange.preset(RangePreset.last7, now);
      expect(week.dayCount, 7);
      expect(week.end, today.end);
      expect(week.dayStarts.first, week.start);
      expect(DateRange.preset(RangePreset.last30, now).dayCount, 30);
      expect(week.previous.end, week.start);
    });
  });

  group('reports', () {
    test(
      'collections exclude pending and failed payments, refunds are separate',
      () async {
        final store = MemoryStore();
        final guard = FakeGuard(StaffRole.owner);
        var gatewayDown = false;
        final billing = BillingController(
          LocalBillingRepository(store),
          _SwitchableGateway(() => gatewayDown),
          guard: guard,
        );
        final orders = OrderController(
          LocalOrderRepository(
            store,
            latency: Duration.zero,
            seedDemoOrders: false,
          ),
          guard: guard,
          onPlaced: billing.createForOrder,
          onCancelled: billing.voidForOrder,
        );
        await orders.load();

        final paid = await placeTestOrder(orders, {'chicken_65': 2});
        final partial = await placeTestOrder(orders, {'masala_dosa': 2});
        final pending = await placeTestOrder(orders, {'gulab_jamun': 2});
        final cancelled = await placeTestOrder(orders, {'masala_dosa': 1});

        final paidBill = billing.forOrder(paid.id)!;
        final payment = await billing.payOnline(
          invoiceId: paidBill.id,
          amount: paidBill.outstanding,
          method: PaymentMethodType.upi,
        );
        await billing.refund(
          invoiceId: paidBill.id,
          paymentId: payment.id,
          amount: const Money.rupees(20),
          reason: 'Late dish',
        );
        final partialBill = billing.forOrder(partial.id)!;
        await billing.payOnline(
          invoiceId: partialBill.id,
          amount: partialBill.outstanding,
          method: PaymentMethodType.card,
          outcome: SimulatedOutcome.failure,
        );
        await billing.recordCounterPayment(
          invoiceId: partialBill.id,
          amount: const Money.rupees(50),
          method: PaymentMethodType.cash,
        );
        gatewayDown = true;
        final pendingBill = billing.forOrder(pending.id)!;
        await expectLater(
          billing.payOnline(
            invoiceId: pendingBill.id,
            amount: pendingBill.outstanding,
            method: PaymentMethodType.upi,
          ),
          throwsA(isA<PaymentException>()),
        );
        await orders.updateStatus(
          cancelled.id,
          OrderStatus.cancelled,
          reason: 'Duplicate order',
        );

        final now = DateTime.now();
        final report = SalesReport.build(
          orders: orders.orders,
          invoices: billing.invoices,
          range: DateRange.preset(RangePreset.today, now),
          now: now,
        );

        final sales = [paid, partial, pending];
        expect(report.orderCount, 3);
        expect(report.cancelledCount, 1);
        expect(report.grossSales, Money.sum(sales.map((o) => o.bill.subtotal)));
        expect(report.billed, Money.sum(sales.map((o) => o.bill.total)));
        expect(report.collected, paidBill.total + const Money.rupees(50));
        expect(report.refunds, const Money.rupees(20));
        expect(report.netCollected, report.collected - report.refunds);
        expect(
          report.netSales,
          report.grossSales - report.discounts - report.refunds,
        );
        expect(report.failedPayments, 1);
        expect(report.paidBills, 1);
        expect(report.partiallyPaidBills, 1);
        expect(report.pendingBills, 1);
        expect(
          report.outstanding,
          partialBill.total - const Money.rupees(50) + pendingBill.total,
        );
        expect(report.byMethod[PaymentMethodType.upi], paidBill.total);
        expect(report.byMethod[PaymentMethodType.cash], const Money.rupees(50));
        expect(report.byMethod.containsKey(PaymentMethodType.card), isFalse);
        expect(report.averageOrderValue.paise, report.billed.paise ~/ 3);

        // The export carries the same figures as the screen.
        final csv = ReportCsv.build(report, const RestaurantSettings());
        final rows = csv.split('\r\n');
        String valueOf(String metric) =>
            rows.firstWhere((r) => r.startsWith('$metric,')).split(',')[1];
        expect(valueOf('Collected'), ReportCsv.amount(report.collected));
        expect(valueOf('Refunds'), ReportCsv.amount(report.refunds));
        expect(valueOf('Outstanding'), ReportCsv.amount(report.outstanding));
        expect(valueOf('Net sales'), ReportCsv.amount(report.netSales));
        expect(valueOf('Orders'), '3');
        final dishRows = rows
            .skipWhile((r) => r != 'Dishes')
            .skip(2)
            .takeWhile((r) => r.isNotEmpty);
        expect(dishRows.length, report.items.length);
      },
    );

    test('demo samples can be excluded', () async {
      final orders = await testOrders(MemoryStore());
      await placeTestOrder(orders, {'masala_dosa': 1});
      final now = DateTime.now();
      final sample = RestaurantOrder.fromJson({
        ...orders.orders.single.toJson(),
        'demo': true,
      });
      final withDemo = SalesReport.build(
        orders: [sample],
        invoices: const [],
        range: DateRange.preset(RangePreset.today, now),
        now: now,
      );
      final withoutDemo = SalesReport.build(
        orders: [sample],
        invoices: const [],
        range: DateRange.preset(RangePreset.today, now),
        now: now,
        includeDemo: false,
      );
      expect(withDemo.orderCount, 1);
      expect(withDemo.demoOrders, 1);
      expect(withoutDemo.orderCount, 0);
    });
  });

  group('table QR codes', () {
    test('scans are checked against configured tables', () {
      bool exists(int table) => table == 5 || table == 45;
      bool active(int table) => table == 45;
      expect(
        TableQrParser.parse(
          'DINEQR:TABLE:45',
          tableExists: exists,
          tableActive: active,
        ),
        isA<ValidTableQr>().having((r) => r.tableNumber, 'table', 45),
      );
      expect(
        TableQrParser.parse(
          'DINEQR:TABLE:05',
          tableExists: exists,
          tableActive: active,
        ),
        isA<InvalidTableQr>().having(
          (r) => r.error,
          'error',
          TableQrError.tableInactive,
        ),
      );
      expect(
        TableQrParser.parse('DINEQR:TABLE:07', tableExists: exists),
        isA<InvalidTableQr>().having(
          (r) => r.error,
          'error',
          TableQrError.invalidTable,
        ),
      );
      // A table QR is only an ordering context: anything else is rejected.
      expect(TableQrParser.parse('DINEQR:ADMIN:01'), isA<InvalidTableQr>());
    });
  });
}

/// Simulator that can be switched to lose the connection mid-payment.
class _SwitchableGateway extends SimulatedPaymentGateway {
  _SwitchableGateway(this._down) : super(processingTime: Duration.zero);

  final bool Function() _down;

  @override
  Future<PaymentResult> collect(
    PaymentRequest request, {
    SimulatedOutcome outcome = SimulatedOutcome.success,
  }) {
    if (_down()) throw StateError('connection lost');
    return super.collect(request, outcome: outcome);
  }
}
