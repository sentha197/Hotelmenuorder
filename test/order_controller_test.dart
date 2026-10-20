import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/core/utils/currency.dart';
import 'package:menu_order/data/demo/demo_menu_data.dart';
import 'package:menu_order/data/models/cart_item.dart';
import 'package:menu_order/data/models/menu_item.dart';
import 'package:menu_order/data/models/order_feedback.dart';
import 'package:menu_order/data/models/order_status.dart';
import 'package:menu_order/data/models/restaurant_order.dart';
import 'package:menu_order/data/repositories/order_repository.dart';
import 'package:menu_order/data/storage/key_value_store.dart';
import 'package:menu_order/state/cart_controller.dart';
import 'package:menu_order/state/order_controller.dart';

MenuItem dish(String id) => demoMenuItems.firstWhere((item) => item.id == id);

/// Deterministic clock that moves forward one minute per call.
class StepClock {
  StepClock(this.now);

  DateTime now;

  DateTime call() {
    final value = now;
    now = now.add(const Duration(minutes: 1));
    return value;
  }
}

class FailingRepository implements OrderRepository {
  @override
  Future<RestaurantOrder> advanceStatus(String orderId) =>
      throw UnimplementedError();

  @override
  Future<List<RestaurantOrder>> fetchOrders() async => [];

  @override
  Future<void> reset() async {}

  @override
  Future<RestaurantOrder> submitFeedback(
    String orderId,
    OrderFeedback feedback,
  ) => throw UnimplementedError();

  @override
  Future<RestaurantOrder> submitOrder(OrderDraft draft) async =>
      throw StateError('kitchen offline');
}

void main() {
  late MemoryStore store;
  late StepClock clock;
  late LocalOrderRepository repository;
  late OrderController orders;
  late CartController cart;

  setUp(() async {
    store = MemoryStore();
    clock = StepClock(DateTime(2026, 10, 17, 12, 30));
    repository = LocalOrderRepository(
      store,
      clock: clock.call,
      latency: Duration.zero,
      seedDemoOrders: false,
    );
    orders = OrderController(repository);
    await orders.load();
    cart = CartController(MemoryStore());
  });

  void fillCart() {
    cart.add(dish('chicken_65'));
    cart.add(dish('veg_manchurian'));
    cart.add(dish('french_fries'));
    cart.updateInstructions('  Less spicy  ');
  }

  group('checkout validation', () {
    test('an empty cart cannot be checked out', () async {
      await expectLater(
        orders.placeOrder(cart: cart, tableNumber: 5),
        throwsA(
          isA<CheckoutException>().having(
            (e) => e.error,
            'error',
            CheckoutError.emptyCart,
          ),
        ),
      );
      expect(orders.orders, isEmpty);
    });

    test('a table is required', () async {
      fillCart();
      await expectLater(
        orders.placeOrder(cart: cart, tableNumber: null),
        throwsA(
          isA<CheckoutException>().having(
            (e) => e.error,
            'error',
            CheckoutError.missingTable,
          ),
        ),
      );
      expect(cart.isNotEmpty, isTrue);
    });

    test('the cart is kept when the order cannot be created', () async {
      final failing = OrderController(FailingRepository());
      fillCart();
      await expectLater(
        failing.placeOrder(cart: cart, tableNumber: 5),
        throwsA(
          isA<CheckoutException>().having(
            (e) => e.error,
            'error',
            CheckoutError.failed,
          ),
        ),
      );
      expect(cart.totalQuantity, 3);
      expect(failing.isPlacing, isFalse);
    });
  });

  group('placing orders', () {
    test(
      'creates an order snapshot, adds it to history and clears the cart',
      () async {
        fillCart();
        final expectedBill = cart.bill;
        final order = await orders.placeOrder(cart: cart, tableNumber: 5);

        expect(order.id, 'OD12345');
        expect(order.tableNumber, 5);
        expect(order.status, OrderStatus.placed);
        expect(order.createdAt, DateTime(2026, 10, 17, 12, 30));
        expect(order.statusTimes[OrderStatus.placed], order.createdAt);
        expect(order.lines.map((line) => line.name), [
          'Chicken 65',
          'Veg Manchurian',
          'French Fries',
        ]);
        expect(order.bill.subtotal, const Money.rupees(450));
        expect(order.bill.tax, expectedBill.tax);
        expect(order.bill.total, const Money(47250));
        expect(order.specialInstructions, 'Less spicy');
        expect(order.estimatedReadyAt.isAfter(order.createdAt), isTrue);

        expect(cart.isEmpty, isTrue);
        expect(cart.specialInstructions, isEmpty);
        expect(orders.orders.first.id, order.id);
        expect(orders.currentOrders, hasLength(1));
        expect(orders.pastOrders, isEmpty);
      },
    );

    test('order ids are unique and sequential', () async {
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        cart.add(dish('butter_naan'));
        ids.add((await orders.placeOrder(cart: cart, tableNumber: 5)).id);
      }
      expect(ids, ['OD12345', 'OD12346', 'OD12347']);
      expect(OrderIdGenerator.next(['OD12301', 'OD99999', 'X1']), 'OD100000');
      expect(OrderIdGenerator.next(const []), 'OD12345');
    });

    test('the snapshot does not change when the cart changes later', () async {
      cart.add(
        dish('chicken_65'),
        customization: DishCustomization(
          spice: SpiceLevel.spicy,
          portionId: 'full',
          addOnIds: ['mint_mayo'],
        ),
      );
      final order = await orders.placeOrder(cart: cart, tableNumber: 12);
      final total = order.bill.total;

      cart.add(dish('butter_chicken'), quantity: 4);
      cart.add(dish('chicken_65'));

      final stored = orders.byId(order.id)!;
      expect(stored.bill.total, total);
      expect(stored.lines, hasLength(1));
      expect(stored.lines.single.unitPrice, const Money.rupees(350));
      expect(stored.lines.single.options, [
        'Spice: Spicy',
        'Full',
        'Mint Mayo Dip',
      ]);
      expect(
        () => stored.lines.add(stored.lines.first),
        throwsUnsupportedError,
      );
    });

    test('rapid repeated taps create only one order', () async {
      final slowOrders = OrderController(
        LocalOrderRepository(
          MemoryStore(),
          latency: const Duration(milliseconds: 50),
          seedDemoOrders: false,
        ),
      );
      fillCart();
      final first = slowOrders.placeOrder(cart: cart, tableNumber: 5);
      expect(slowOrders.isPlacing, isTrue);
      await expectLater(
        slowOrders.placeOrder(cart: cart, tableNumber: 5),
        throwsA(
          isA<CheckoutException>().having(
            (e) => e.error,
            'error',
            CheckoutError.alreadyPlacing,
          ),
        ),
      );
      await first;
      expect(slowOrders.orders, hasLength(1));
      expect(slowOrders.isPlacing, isFalse);
    });

    test('orders survive an app restart', () async {
      fillCart();
      final order = await orders.placeOrder(cart: cart, tableNumber: 5);
      final reloaded = OrderController(
        LocalOrderRepository(
          store,
          latency: Duration.zero,
          seedDemoOrders: false,
        ),
      );
      await reloaded.load();
      final restored = reloaded.byId(order.id)!;
      expect(restored.bill.total, order.bill.total);
      expect(restored.lines.map((l) => l.name), order.lines.map((l) => l.name));
      expect(restored.specialInstructions, order.specialInstructions);
      expect(restored.status, OrderStatus.placed);
    });

    test(
      'demo samples are flagged and the first real order is OD12345',
      () async {
        final seeded = OrderController(
          LocalOrderRepository(MemoryStore(), latency: Duration.zero),
        );
        await seeded.load();
        expect(seeded.pastOrders, hasLength(2));
        expect(seeded.orders.every((order) => order.isDemoSample), isTrue);
        expect(seeded.orders.any((order) => order.canRate), isFalse);
        fillCart();
        final order = await seeded.placeOrder(cart: cart, tableNumber: 5);
        expect(order.id, 'OD12345');
        expect(order.isDemoSample, isFalse);
      },
    );
  });

  group('status transitions', () {
    test('orders move forward one stage at a time', () {
      expect(OrderStatus.placed.next, OrderStatus.preparing);
      expect(OrderStatus.served.next, isNull);
      expect(OrderStatus.placed.canTransitionTo(OrderStatus.preparing), isTrue);
      expect(OrderStatus.placed.canTransitionTo(OrderStatus.served), isFalse);
      expect(
        OrderStatus.preparing.canTransitionTo(OrderStatus.placed),
        isFalse,
      );
    });

    test(
      'advancing records timestamps and moves the order to past orders',
      () async {
        cart.add(dish('masala_dosa'));
        final order = await orders.placeOrder(cart: cart, tableNumber: 5);

        final preparing = await orders.advanceStatus(order.id);
        expect(preparing!.status, OrderStatus.preparing);
        final ready = await orders.advanceStatus(order.id);
        expect(ready!.status, OrderStatus.readyToServe);
        final served = await orders.advanceStatus(order.id);
        expect(served!.status, OrderStatus.served);

        expect(served.statusTimes.keys, OrderStatus.values);
        final times = OrderStatus.values
            .map((s) => served.statusTimes[s]!)
            .toList();
        for (var i = 1; i < times.length; i++) {
          expect(times[i].isAfter(times[i - 1]), isTrue);
        }
        expect(await orders.advanceStatus(order.id), isNull);
        expect(orders.currentOrders, isEmpty);
        expect(orders.pastOrders.single.id, order.id);
      },
    );
  });

  group('feedback', () {
    test('validation', () {
      expect(
        OrderFeedback.validate(rating: 0, comment: ''),
        FeedbackError.missingRating,
      );
      expect(
        OrderFeedback.validate(rating: 6, comment: ''),
        FeedbackError.ratingOutOfRange,
      );
      expect(
        OrderFeedback.validate(rating: 4, comment: 'x' * 301),
        FeedbackError.commentTooLong,
      );
      expect(OrderFeedback.validate(rating: 5, comment: ''), isNull);
      expect(OrderFeedback.validate(rating: 1, comment: 'ok'), isNull);
    });

    Future<RestaurantOrder> servedOrder() async {
      cart.add(dish('gulab_jamun'));
      final order = await orders.placeOrder(cart: cart, tableNumber: 5);
      for (var i = 0; i < 3; i++) {
        await orders.advanceStatus(order.id);
      }
      return orders.byId(order.id)!;
    }

    test('orders can only be rated once they are served', () async {
      cart.add(dish('gulab_jamun'));
      final order = await orders.placeOrder(cart: cart, tableNumber: 5);
      expect(order.canRate, isFalse);
      await expectLater(
        orders.submitFeedback(order.id, rating: 4, comment: ''),
        throwsStateError,
      );
    });

    test('invalid feedback is rejected', () async {
      final order = await servedOrder();
      await expectLater(
        orders.submitFeedback(order.id, rating: 0, comment: 'nice'),
        throwsA(isA<FeedbackException>()),
      );
      expect(orders.byId(order.id)!.feedback, isNull);
    });

    test('feedback is stored against the order and persisted', () async {
      final order = await servedOrder();
      final at = DateTime(2026, 10, 17, 13, 15);
      await orders.submitFeedback(
        order.id,
        rating: 4,
        comment: '  Lovely dessert ',
        submittedAt: at,
      );
      final rated = orders.byId(order.id)!;
      expect(rated.feedback!.rating, 4);
      expect(rated.feedback!.comment, 'Lovely dessert');
      expect(rated.feedback!.submittedAt, at);
      expect(rated.canRate, isFalse);

      await expectLater(
        orders.submitFeedback(order.id, rating: 5, comment: ''),
        throwsStateError,
      );

      final reloaded = OrderController(
        LocalOrderRepository(
          store,
          latency: Duration.zero,
          seedDemoOrders: false,
        ),
      );
      await reloaded.load();
      expect(reloaded.byId(order.id)!.feedback!.rating, 4);
    });
  });
}
