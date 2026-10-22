import 'dart:math' as math;

import '../models/billing.dart';
import '../models/inventory.dart';
import '../models/menu_item.dart';
import '../models/order_status.dart';
import '../models/pricing.dart';
import '../models/restaurant_order.dart';
import '../models/restaurant_settings.dart';
import '../utils/currency.dart';
import '../utils/restaurant_time.dart';
import 'demo_menu_data.dart';

/// Clearly labelled sample data for the offline demo: two example orders in
/// the guest's history and two weeks of restaurant orders and bills so the
/// admin dashboard and reports have something to calculate. Every record is
/// flagged with `isDemoSample`; demo payments are flagged `isSimulated`.
///
/// Generation is deterministic for a given [now], so orders and bills always
/// match each other.
class DemoSeed {
  DemoSeed._(this.orders, this.invoices);

  factory DemoSeed.generate(DateTime now) {
    final builder = _SeedBuilder(now);
    return DemoSeed._(builder.orders, builder.invoices);
  }

  /// No samples at all (tests and production).
  static final empty = DemoSeed._(const [], const []);

  final List<RestaurantOrder> orders;
  final List<Invoice> invoices;

  /// Starter inventory for the demo (labelled as sample data).
  static List<InventoryItem> inventory(DateTime now) {
    InventoryItem item(
      String id,
      String name,
      String unit,
      double qty,
      double reorder, {
      String supplier = '',
      List<String> dishes = const [],
    }) => InventoryItem(
      id: id,
      name: name,
      unit: unit,
      quantity: qty,
      reorderLevel: reorder,
      updatedAt: now,
      supplier: supplier,
      linkedDishIds: dishes,
      isDemoSample: true,
    );
    return [
      item(
        'inv_chicken',
        'Chicken',
        'kg',
        14,
        5,
        supplier: 'Sample Farms',
        dishes: [
          'chicken_65',
          'chilli_chicken',
          'tandoori_chicken',
          'chicken_biryani',
          'butter_chicken',
        ],
      ),
      item(
        'inv_paneer',
        'Paneer',
        'kg',
        2.5,
        3,
        supplier: 'Sample Dairy',
        dishes: ['paneer_tikka', 'paneer_butter_masala'],
      ),
      item('inv_rice', 'Basmati rice', 'kg', 24, 10, supplier: 'Sample Grains'),
      item('inv_potato', 'Potatoes', 'kg', 16, 8),
      item('inv_oil', 'Cooking oil', 'L', 9, 6),
      item(
        'inv_milk',
        'Milk',
        'L',
        5,
        8,
        supplier: 'Sample Dairy',
        dishes: ['lassi', 'rasmalai'],
      ),
      item('inv_coffee', 'Coffee beans', 'kg', 1.4, 1, dishes: ['cold_coffee']),
      item(
        'inv_icecream',
        'Vanilla ice cream',
        'L',
        3,
        2,
        dishes: ['affogato'],
      ),
      item('inv_flour', 'Wheat flour', 'kg', 20, 8, dishes: ['butter_naan']),
      item('inv_lemon', 'Lemons', 'pcs', 45, 30, dishes: ['fresh_lime_soda']),
    ];
  }
}

class _SeedBuilder {
  _SeedBuilder(this.now) {
    _build();
  }

  final DateTime now;
  final orders = <RestaurantOrder>[];
  final invoices = <Invoice>[];
  final _random = math.Random(2026);
  final _menu = {for (final item in demoMenuItems) item.id: item};
  static const _pricing = PricingConfig();
  static const _restaurant = RestaurantSettings();
  int _invoiceSeq = 0;
  int _paymentSeq = 0;
  int _refundSeq = 0;

  static const _methods = [
    PaymentMethodType.upi,
    PaymentMethodType.cash,
    PaymentMethodType.card,
    PaymentMethodType.upi,
    PaymentMethodType.wallet,
    PaymentMethodType.netBanking,
    PaymentMethodType.upi,
    PaymentMethodType.cash,
  ];

  void _build() {
    // Restaurant orders over the past 13 days, then a few today. Times are
    // generated oldest first so ids and bill numbers increase with time.
    const perDay = [3, 2, 4, 3, 2, 4, 3, 2, 3, 4, 2, 3, 3];
    final placed = <({DateTime at, int index})>[];
    var index = 0;
    for (var daysAgo = 13; daysAgo >= 1; daysAgo--) {
      final day = RestaurantTime.startOfDay(
        now,
      ).subtract(Duration(days: daysAgo));
      final count = perDay[13 - daysAgo];
      final minutes = [
        for (var i = 0; i < count; i++) 12 * 60 + _random.nextInt(10 * 60),
      ]..sort();
      for (final minute in minutes) {
        placed.add((at: day.add(Duration(minutes: minute)), index: index++));
      }
    }
    var number = 12200;
    for (final entry in placed) {
      _addRestaurantOrder('OD${number++}', entry.at, entry.index, today: false);
    }
    // Today: two served and paid, one preparing, one just placed.
    for (final (i, ago) in const [130, 80, 25, 8].indexed) {
      _addRestaurantOrder(
        'OD${number++}',
        now.subtract(Duration(minutes: ago)),
        index++,
        today: true,
        todayStage: i,
      );
    }
    _addGuestSamples();
  }

  List<OrderLine> _randomLines() {
    final ids = _menu.keys.toList();
    final count = 1 + _random.nextInt(3);
    final picked = <String>{};
    while (picked.length < count) {
      picked.add(ids[_random.nextInt(ids.length)]);
    }
    return [
      for (final id in picked)
        _line(_menu[id]!, quantity: _random.nextInt(4) == 0 ? 2 : 1),
    ];
  }

  OrderLine _line(MenuItem item, {int quantity = 1, List<String>? options}) =>
      OrderLine(
        itemId: item.id,
        name: item.name,
        image: item.image,
        isVeg: item.isVeg,
        unitPrice: item.price,
        quantity: quantity,
        options:
            options ??
            (item.hasSpiceLevel
                ? ['Spice: ${item.defaultSpice.label}']
                : const []),
        categoryId: item.category.id,
        categoryName: item.category.label,
      );

  void _addRestaurantOrder(
    String id,
    DateTime at,
    int index, {
    required bool today,
    int todayStage = 0,
  }) {
    final lines = _randomLines();
    final subtotal = Money.sum(lines.map((l) => l.lineTotal));
    final offer = index % 7 == 4 ? _restaurant.offerByCode('WELCOME10') : null;
    final discount = offer?.discountFor(subtotal) ?? Money.zero;
    final bill = BillBreakdown.fromSubtotal(
      subtotal,
      _pricing,
      discount: discount,
      discountLabel: discount.isZero ? null : 'Offer ${offer!.code}',
    );
    final cancelled = !today && index % 11 == 6;
    final status = today
        ? const [
            OrderStatus.served,
            OrderStatus.served,
            OrderStatus.preparing,
            OrderStatus.placed,
          ][todayStage]
        : (cancelled ? OrderStatus.cancelled : OrderStatus.served);
    final times = <OrderStatus, DateTime>{OrderStatus.placed: at};
    if (status == OrderStatus.cancelled) {
      times[OrderStatus.cancelled] = at.add(const Duration(minutes: 4));
    } else {
      const offsets = {
        OrderStatus.accepted: 1,
        OrderStatus.preparing: 3,
        OrderStatus.readyToServe: 18,
        OrderStatus.served: 22,
      };
      for (final MapEntry(key: s, value: m) in offsets.entries) {
        if (s.index > status.index) break;
        times[s] = at.add(Duration(minutes: m));
      }
    }
    final order = RestaurantOrder(
      id: id,
      tableNumber: 1 + _random.nextInt(20),
      createdAt: at,
      lines: lines,
      bill: bill,
      specialInstructions: index % 9 == 2 ? 'Less spicy, please (sample)' : '',
      status: status,
      statusTimes: times,
      estimatedReadyAt: at.add(const Duration(minutes: 25)),
      isDemoSample: true,
      source: OrderSource.demoSeed,
      cancelReason: cancelled ? 'Guest changed their mind (sample)' : '',
    );
    orders.add(order);

    var invoice = _invoiceFor(order);
    if (cancelled) {
      invoices.add(invoice.voided(order.cancelReason));
      return;
    }
    if (today && todayStage >= 2) {
      invoices.add(invoice); // still eating: unpaid
      return;
    }
    final paidAt = at.add(Duration(minutes: 40 + _random.nextInt(15)));
    final method = _methods[index % _methods.length];
    if (!today && index % 13 == 5) {
      invoices.add(invoice); // left unpaid: shows as outstanding
    } else if (!today && index % 13 == 8) {
      final half = Money(bill.total.paise ~/ 2);
      invoices.add(invoice.withPayment(_payment(order, half, method, paidAt)));
    } else if (!today && index % 13 == 10) {
      invoice = invoice.withPayment(
        _payment(
          order,
          bill.total,
          PaymentMethodType.card,
          paidAt.subtract(const Duration(minutes: 2)),
          status: PaymentStatus.failed,
          failure: 'Card declined by bank (sample)',
        ),
      );
      invoices.add(
        invoice.withPayment(
          _payment(order, bill.total, PaymentMethodType.upi, paidAt),
        ),
      );
    } else {
      final payment = _payment(order, bill.total, method, paidAt);
      invoice = invoice.withPayment(payment);
      if (!today && index % 17 == 3) {
        invoice = invoice.withRefund(
          RefundRecord(
            id: 'RF${(++_refundSeq).toString().padLeft(6, '0')}',
            invoiceId: invoice.id,
            paymentId: payment.id,
            amount: lines.first.unitPrice,
            reason: 'Dish returned to kitchen (sample)',
            status: RefundStatus.processed,
            createdAt: paidAt.add(const Duration(minutes: 5)),
            processedBy: 'Demo data',
            reference: 'DEMO-RF-${_token()}',
            isSimulated: true,
          ),
        );
      }
      invoices.add(invoice);
    }
  }

  Invoice _invoiceFor(RestaurantOrder order) {
    _invoiceSeq++;
    final year = RestaurantTime.wall(order.createdAt).year;
    return Invoice(
      id: 'INV${_invoiceSeq.toString().padLeft(6, '0')}',
      billNumber: 'DQ-$year-${_invoiceSeq.toString().padLeft(5, '0')}',
      orderId: order.id,
      tableNumber: order.tableNumber,
      createdAt: order.createdAt,
      lines: order.lines,
      amounts: order.bill,
      restaurant: _restaurant.snapshot,
      isDemoSample: true,
    );
  }

  PaymentTransaction _payment(
    RestaurantOrder order,
    Money amount,
    PaymentMethodType method,
    DateTime at, {
    PaymentStatus status = PaymentStatus.succeeded,
    String failure = '',
  }) {
    _paymentSeq++;
    return PaymentTransaction(
      id: 'PAY${_paymentSeq.toString().padLeft(6, '0')}',
      invoiceId: 'INV${_invoiceSeq.toString().padLeft(6, '0')}',
      orderId: order.id,
      amount: amount,
      method: method,
      status: status,
      provider: method == PaymentMethodType.cash
          ? 'Counter (sample)'
          : 'Demo data',
      createdAt: at,
      updatedAt: at,
      idempotencyKey: 'seed-$_paymentSeq',
      reference: 'DEMO-${_token()}',
      failureReason: failure,
      isSimulated: true,
      recordedBy: method == PaymentMethodType.cash ? 'Demo data' : '',
    );
  }

  String _token() => String.fromCharCodes([
    for (var i = 0; i < 8; i++)
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.codeUnitAt(_random.nextInt(32)),
  ]);

  /// The two example orders shown in the guest's "Past Orders".
  void _addGuestSamples() {
    RestaurantOrder sample(
      String id,
      int table,
      Duration ago,
      List<OrderLine> lines,
      PaymentMethodType method,
    ) {
      final at = now.subtract(ago);
      final subtotal = Money.sum(lines.map((line) => line.lineTotal));
      final order = RestaurantOrder(
        id: id,
        tableNumber: table,
        createdAt: at,
        lines: lines,
        bill: BillBreakdown.fromSubtotal(subtotal, _pricing),
        specialInstructions: '',
        status: OrderStatus.served,
        statusTimes: {
          OrderStatus.placed: at,
          OrderStatus.accepted: at.add(const Duration(minutes: 1)),
          OrderStatus.preparing: at.add(const Duration(minutes: 2)),
          OrderStatus.readyToServe: at.add(const Duration(minutes: 18)),
          OrderStatus.served: at.add(const Duration(minutes: 21)),
        },
        estimatedReadyAt: at.add(const Duration(minutes: 20)),
        isDemoSample: true,
      );
      orders.add(order);
      invoices.add(
        _invoiceFor(order).withPayment(
          _payment(
            order,
            order.bill.total,
            method,
            at.add(const Duration(minutes: 45)),
          ),
        ),
      );
      return order;
    }

    sample('OD12318', 12, const Duration(days: 2, hours: 3), [
      _line(_menu['chicken_biryani']!, quantity: 2, options: ['Spice: Medium']),
      _line(_menu['lassi']!, quantity: 2, options: const []),
    ], PaymentMethodType.upi);
    sample('OD12301', 5, const Duration(days: 6, hours: 1), [
      _line(_menu['masala_dosa']!, options: const []),
      _line(_menu['gulab_jamun']!, options: const []),
    ], PaymentMethodType.cash);
  }
}
