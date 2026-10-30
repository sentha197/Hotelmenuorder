import '../utils/currency.dart';
import '../utils/formatters.dart';
import '../utils/restaurant_time.dart';
import 'discount_offer.dart';
import 'menu_item.dart';

/// When coupons and promotions can be used (same rules as the server's
/// OfferRules): switched on, within their dates and with uses left.
///
/// Offer dates are restaurant days, both ends included. They are held as
/// UTC midnights and compared by calendar day only.
abstract final class OfferRules {
  /// Today in the restaurant's time zone.
  static DateTime today([DateTime? now]) =>
      asDay(RestaurantTime.wall(now ?? DateTime.now()));

  /// [value]'s calendar day as a UTC midnight.
  static DateTime asDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  /// Reads `2026-11-01`; anything else is null.
  static DateTime? parseDay(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : asDay(parsed);
  }

  /// `2026-11-01`
  static String dayJson(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static bool inDates(DateTime? startsOn, DateTime? endsOn, DateTime today) =>
      (startsOn == null || !today.isBefore(startsOn)) &&
      (endsOn == null || !today.isAfter(endsOn));

  static bool hasUsesLeft(int? limit, int used) =>
      limit == null || used < limit;

  /// Where an offer stands on [today] (staff lists).
  static OfferStatus status({
    required bool isActive,
    required DateTime today,
    DateTime? startsOn,
    DateTime? endsOn,
    int? usageLimit,
    int usedCount = 0,
  }) {
    if (!isActive) return OfferStatus.paused;
    if (endsOn != null && today.isAfter(endsOn)) return OfferStatus.ended;
    if (!hasUsesLeft(usageLimit, usedCount)) return OfferStatus.usedUp;
    if (startsOn != null && today.isBefore(startsOn)) {
      return OfferStatus.scheduled;
    }
    return OfferStatus.live;
  }

  /// `1 Nov – 30 Nov 2026`, `From 1 Nov 2026`, `Until 30 Nov 2026`, or
  /// `Always` (dates are calendar days: shown as they are, never converted).
  static String validity(DateTime? startsOn, DateTime? endsOn) {
    String day(DateTime d) => AppFormat.day(d);
    if (startsOn == null && endsOn == null) return 'Always';
    if (startsOn == null) return 'Until ${day(endsOn!)}';
    if (endsOn == null) return 'From ${day(startsOn)}';
    if (startsOn == endsOn) return 'On ${day(startsOn)}';
    return '${AppFormat.shortDay(startsOn)} – ${day(endsOn)}';
  }
}

/// Where an offer stands today.
enum OfferStatus {
  live('Live'),
  scheduled('Scheduled'),
  ended('Ended'),
  paused('Paused'),
  usedUp('Used up');

  const OfferStatus(this.label);

  final String label;
}

enum PromotionKind {
  /// A discount on chosen dishes, applied without a code.
  special('Special offer'),

  /// Several dishes sold together for one price.
  combo('Combo');

  const PromotionKind(this.label);

  final String label;

  static PromotionKind parse(Object? name) =>
      name == 'combo' ? PromotionKind.combo : PromotionKind.special;
}

/// A dish in a promotion: covered by a special offer, or [quantity] of it
/// in one combo.
class PromotionItem {
  const PromotionItem(this.itemId, {this.quantity = 1});

  factory PromotionItem.fromJson(Map<String, dynamic> json) => PromotionItem(
    json['itemId'] as String,
    quantity: json['quantity'] as int? ?? 1,
  );

  final String itemId;
  final int quantity;

  Map<String, dynamic> toJson() => {'itemId': itemId, 'quantity': quantity};

  @override
  bool operator ==(Object other) =>
      other is PromotionItem &&
      other.itemId == itemId &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(itemId, quantity);
}

/// A special offer or a combo set up by the restaurant (Offers section).
/// What an order pays is decided by [OfferPricing], and by the server.
class Promotion {
  const Promotion({
    required this.id,
    required this.kind,
    required this.title,
    this.description = '',
    this.image = '',
    this.startsOn,
    this.endsOn,
    this.isActive = true,
    this.usageLimit,
    this.usedCount = 0,
    this.sortOrder = 0,
    this.discountType = DiscountType.percent,
    this.discountValue = 0,
    this.comboPrice,
    this.items = const [],
  });

  factory Promotion.fromJson(Map<String, dynamic> json) {
    final kind = PromotionKind.parse(json['kind']);
    return Promotion(
      id: json['id'] as String,
      kind: kind,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      image: json['image'] as String? ?? '',
      startsOn: OfferRules.parseDay(json['startsOn']),
      endsOn: OfferRules.parseDay(json['endsOn']),
      isActive: json['active'] as bool? ?? true,
      usageLimit: json['limit'] as int?,
      usedCount: json['used'] as int? ?? 0,
      sortOrder: json['sort'] as int? ?? 0,
      discountType: json['discountType'] == 'flat'
          ? DiscountType.flat
          : DiscountType.percent,
      discountValue: json['value'] as int? ?? 0,
      comboPrice: json['comboPrice'] == null
          ? null
          : Money(json['comboPrice'] as int),
      items: List.unmodifiable([
        for (final item in json['items'] as List? ?? const [])
          PromotionItem.fromJson(item as Map<String, dynamic>),
      ]),
    );
  }

  final String id;
  final PromotionKind kind;
  final String title;
  final String description;

  /// A picture for banners and combo cards ('' uses a dish photo).
  final String image;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool isActive;

  /// How many orders may use it (null: no limit), and how many did. Guests
  /// are not told either: they only ever see live offers.
  final int? usageLimit;
  final int usedCount;
  final int sortOrder;

  /// Special offers: percent (basis points) or flat (paise) off each unit.
  final DiscountType discountType;
  final int discountValue;

  /// Combos: the price of the whole package.
  final Money? comboPrice;
  final List<PromotionItem> items;

  bool get isCombo => kind == PromotionKind.combo;

  bool get isSpecial => kind == PromotionKind.special;

  bool covers(String itemId) => items.any((i) => i.itemId == itemId);

  bool isLiveOn(DateTime today) =>
      isActive &&
      OfferRules.inDates(startsOn, endsOn, today) &&
      OfferRules.hasUsesLeft(usageLimit, usedCount);

  OfferStatus statusOn(DateTime today) => OfferRules.status(
    isActive: isActive,
    today: today,
    startsOn: startsOn,
    endsOn: endsOn,
    usageLimit: usageLimit,
    usedCount: usedCount,
  );

  /// What a special offer takes off one unit costing [unitPrice]: never
  /// more than the unit itself.
  Money unitDiscount(Money unitPrice) {
    final amount = discountType == DiscountType.percent
        ? unitPrice.applyRate(discountValue)
        : Money(discountValue);
    if (amount.paise < 0) return Money.zero;
    return amount.compareTo(unitPrice) > 0 ? unitPrice : amount;
  }

  /// `20% OFF` or `₹50 OFF` (special offers).
  String get badge => discountType == DiscountType.percent
      ? '${_percent(discountValue)} OFF'
      : '${CurrencyFormatter.format(Money(discountValue))} OFF';

  /// The combo as the menu shows it now, or null when one of its dishes is
  /// not on the menu (any more).
  ComboView? comboView(Map<String, MenuItem> menu) {
    if (!isCombo) return null;
    final dishes = <({MenuItem item, int quantity})>[];
    for (final part in items) {
      final item = menu[part.itemId];
      if (item == null) return null;
      dishes.add((item: item, quantity: part.quantity));
    }
    if (dishes.isEmpty) return null;
    return ComboView._(this, dishes);
  }

  static String _percent(int basisPoints) {
    final percent = basisPoints / 100;
    return percent == percent.roundToDouble()
        ? '${percent.toStringAsFixed(0)}%'
        : '${percent.toStringAsFixed(1)}%';
  }

  Promotion copyWith({
    String? id,
    String? title,
    String? description,
    String? image,
    DateTime? startsOn,
    DateTime? endsOn,
    bool clearStartsOn = false,
    bool clearEndsOn = false,
    bool? isActive,
    int? usageLimit,
    bool clearUsageLimit = false,
    int? usedCount,
    int? sortOrder,
    DiscountType? discountType,
    int? discountValue,
    Money? comboPrice,
    List<PromotionItem>? items,
  }) => Promotion(
    id: id ?? this.id,
    kind: kind,
    title: title ?? this.title,
    description: description ?? this.description,
    image: image ?? this.image,
    startsOn: clearStartsOn ? null : (startsOn ?? this.startsOn),
    endsOn: clearEndsOn ? null : (endsOn ?? this.endsOn),
    isActive: isActive ?? this.isActive,
    usageLimit: clearUsageLimit ? null : (usageLimit ?? this.usageLimit),
    usedCount: usedCount ?? this.usedCount,
    sortOrder: sortOrder ?? this.sortOrder,
    discountType: discountType ?? this.discountType,
    discountValue: discountValue ?? this.discountValue,
    comboPrice: comboPrice ?? this.comboPrice,
    items: items ?? this.items,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'description': description,
    'image': image,
    if (startsOn != null) 'startsOn': OfferRules.dayJson(startsOn!),
    if (endsOn != null) 'endsOn': OfferRules.dayJson(endsOn!),
    'active': isActive,
    'items': [for (final item in items) item.toJson()],
    if (isSpecial) 'discountType': discountType.name,
    if (isSpecial) 'value': discountValue,
    if (isCombo && comboPrice != null) 'comboPrice': comboPrice!.paise,
    if (usageLimit != null) 'limit': usageLimit,
    'used': usedCount,
    'sort': sortOrder,
  };
}

/// A combo with its dishes from the current menu.
class ComboView {
  ComboView._(this.combo, this.dishes);

  /// Where combo lines are filed on orders and reports.
  static const category = MenuCategory(
    id: 'combos',
    label: 'Combos',
    coverImage: '',
    sortOrder: 999,
  );

  final Promotion combo;
  final List<({MenuItem item, int quantity})> dishes;

  /// What one of [item] costs in a combo: its default portion, no add-ons
  /// (same as the server's Pricing.DefaultUnitPrice).
  static Money defaultUnitPrice(MenuItem item) =>
      item.price + (item.defaultPortion?.extraPrice ?? Money.zero);

  /// What the dishes cost separately.
  Money get originalPrice =>
      Money.sum(dishes.map((d) => defaultUnitPrice(d.item) * d.quantity));

  Money get price => combo.comboPrice ?? originalPrice;

  /// What one combo saves (none if its dishes became cheaper than it).
  Money get saving {
    final saving = originalPrice - price;
    return saving.paise > 0 ? saving : Money.zero;
  }

  /// Whether every dish can be ordered right now.
  bool get dishesOrderable => dishes.every((d) => d.item.isOrderable);

  bool get isVeg => dishes.every((d) => d.item.isVeg);

  /// `2 × Punjabi Samosa`, `French Fries` (as orders list them).
  List<String> get partLabels => [
    for (final d in dishes) partLabel(d.quantity, d.item.name),
  ];

  static String partLabel(int quantity, String name) =>
      quantity > 1 ? '$quantity × $name' : name;

  String get image =>
      combo.image.isNotEmpty ? combo.image : dishes.first.item.image;

  /// The combo dressed as a dish, so a cart line can show it like one: its
  /// full price is what the dishes cost separately (the saving is applied
  /// as a discount), and it can be ordered only while live ([live]) and
  /// every dish can.
  MenuItem asItem({required bool live}) => MenuItem(
    id: combo.id,
    name: combo.title,
    category: category,
    description: combo.description,
    shortDescription: partLabels.join(', '),
    price: originalPrice,
    image: image,
    isVeg: isVeg,
    rating: 0,
    reviewCount: 0,
    prepMinutes: dishes
        .map((d) => d.item.prepMinutes)
        .reduce((a, b) => a > b ? a : b),
    isAvailable: live && dishesOrderable,
  );
}
