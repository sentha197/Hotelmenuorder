import '../utils/currency.dart';
import 'billing.dart';
import 'discount_offer.dart';
import 'network_access.dart';
import 'pricing.dart';

/// Restaurant configuration, edited from the admin dashboard. Optional
/// business details (contact, tax registration) are empty until the
/// restaurant fills them in; bills never invent them.
class RestaurantSettings {
  const RestaurantSettings({
    this.name = 'DineQR Demo Restaurant',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.taxRegistration = '',
    this.taxName = 'Taxes',
    this.taxRateBasisPoints = 500,
    this.serviceChargeBasisPoints = 0,
    this.utcOffsetMinutes = 330,
    this.allowPartialPayments = true,
    this.onlineMethods = const {
      PaymentMethodType.upi,
      PaymentMethodType.card,
      PaymentMethodType.netBanking,
      PaymentMethodType.wallet,
    },
    this.receiptFooter = 'Thank you for dining with us!',
    this.showSoldOutDishes = true,
    this.autoUnavailableWhenOutOfStock = true,
    this.prepBufferMinutes = 5,
    this.takeawayOrdersEnabled = false,
    this.offers = defaultOffers,
    this.paymentMode = PaymentMode.demo,
    this.currencyCode = 'INR',
    this.wifi = DineInWifi.off,
  });

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) {
    const defaults = RestaurantSettings();
    return RestaurantSettings(
      name: json['name'] as String? ?? defaults.name,
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      address: json['address'] as String? ?? '',
      taxRegistration: json['taxReg'] as String? ?? '',
      taxName: json['taxName'] as String? ?? defaults.taxName,
      taxRateBasisPoints:
          json['taxRate'] as int? ?? defaults.taxRateBasisPoints,
      serviceChargeBasisPoints: json['serviceRate'] as int? ?? 0,
      utcOffsetMinutes: json['utcOffset'] as int? ?? defaults.utcOffsetMinutes,
      allowPartialPayments: json['partial'] as bool? ?? true,
      onlineMethods: {
        for (final name
            in (json['methods'] as List? ??
                    [for (final m in defaults.onlineMethods) m.name])
                .cast<String>())
          ?PaymentMethodType.tryParse(name),
      }..remove(PaymentMethodType.cash),
      receiptFooter: json['footer'] as String? ?? defaults.receiptFooter,
      showSoldOutDishes: json['showSoldOut'] as bool? ?? true,
      autoUnavailableWhenOutOfStock: json['autoUnavailable'] as bool? ?? true,
      prepBufferMinutes: json['prepBuffer'] as int? ?? 5,
      // Servers from before takeaway was renamed from "parcel" send only the
      // old key.
      takeawayOrdersEnabled:
          json['takeaway'] as bool? ?? json['parcel'] as bool? ?? false,
      offers: [
        for (final o in json['offers'] as List? ?? const [])
          DiscountOffer.fromJson(o as Map<String, dynamic>),
      ],
      paymentMode: PaymentMode.parse(json['paymentMode'] as String?),
      currencyCode: json['currency'] as String? ?? 'INR',
      wifi: DineInWifi.fromJson(json['wifi'] as Map<String, dynamic>?),
    );
  }

  static const defaultOffers = [
    DiscountOffer(
      code: 'WELCOME10',
      title: 'Welcome offer (demo)',
      type: DiscountType.percent,
      value: 1000,
      minSubtotal: Money.rupees(300),
      maxDiscount: Money.rupees(100),
    ),
    DiscountOffer(
      code: 'FEAST75',
      title: 'Feast for two (demo)',
      type: DiscountType.flat,
      value: 7500,
      minSubtotal: Money.rupees(800),
    ),
  ];

  final String name;
  final String phone;
  final String email;
  final String address;

  /// Tax registration number (e.g. a GSTIN). Printed on bills only when set.
  final String taxRegistration;
  final String taxName;
  final int taxRateBasisPoints;
  final int serviceChargeBasisPoints;

  /// Restaurant time zone as a fixed offset from UTC, in minutes.
  final int utcOffsetMinutes;

  /// ISO code of the currency bills are in ([CurrencyFormatter.supported]).
  /// The server refuses to change it once bills exist.
  final String currencyCode;

  /// The dine-in Wi-Fi restriction as guests see it (read only: staff
  /// change it with [NetworkAccessSettings]).
  final DineInWifi wifi;

  /// Demo (payments simulated, no money moves) or live (a verified payment
  /// gateway; refused by the server while none is configured).
  final PaymentMode paymentMode;

  /// Whether guests may pay part of a bill and the rest later.
  final bool allowPartialPayments;

  /// Online methods offered to guests (subject to the payment provider).
  final Set<PaymentMethodType> onlineMethods;
  final String receiptFooter;

  /// Show sold-out dishes greyed out (true) or hide them (false).
  final bool showSoldOutDishes;

  /// Mark dishes linked to an inventory item unavailable when it runs out.
  final bool autoUnavailableWhenOutOfStock;

  /// Minutes added to the longest dish preparation time for estimates.
  final int prepBufferMinutes;

  /// Whether the restaurant takes takeaway orders. The takeaway QR code is
  /// refused while this is off.
  final bool takeawayOrdersEnabled;

  final List<DiscountOffer> offers;

  PricingConfig get pricing => PricingConfig(
    taxRateBasisPoints: taxRateBasisPoints,
    taxName: taxName,
    serviceChargeBasisPoints: serviceChargeBasisPoints,
  );

  RestaurantSnapshot get snapshot => RestaurantSnapshot(
    name: name,
    phone: phone,
    email: email,
    address: address,
    taxRegistration: taxRegistration,
    footer: receiptFooter,
  );

  DiscountOffer? offerByCode(String code) {
    final normalized = DiscountOffer.normalize(code);
    for (final offer in offers) {
      if (offer.code == normalized) return offer;
    }
    return null;
  }

  /// `UTC+05:30`
  String get utcOffsetLabel => formatOffset(utcOffsetMinutes);

  static String formatOffset(int minutes) {
    final sign = minutes < 0 ? '−' : '+';
    final abs = minutes.abs();
    final hours = (abs ~/ 60).toString().padLeft(2, '0');
    final mins = (abs % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$mins';
  }

  RestaurantSettings copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    String? taxRegistration,
    String? taxName,
    int? taxRateBasisPoints,
    int? serviceChargeBasisPoints,
    int? utcOffsetMinutes,
    bool? allowPartialPayments,
    Set<PaymentMethodType>? onlineMethods,
    String? receiptFooter,
    bool? showSoldOutDishes,
    bool? autoUnavailableWhenOutOfStock,
    int? prepBufferMinutes,
    bool? takeawayOrdersEnabled,
    List<DiscountOffer>? offers,
    PaymentMode? paymentMode,
    String? currencyCode,
    DineInWifi? wifi,
  }) => RestaurantSettings(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    taxRegistration: taxRegistration ?? this.taxRegistration,
    taxName: taxName ?? this.taxName,
    taxRateBasisPoints: taxRateBasisPoints ?? this.taxRateBasisPoints,
    serviceChargeBasisPoints:
        serviceChargeBasisPoints ?? this.serviceChargeBasisPoints,
    utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
    allowPartialPayments: allowPartialPayments ?? this.allowPartialPayments,
    onlineMethods: onlineMethods ?? this.onlineMethods,
    receiptFooter: receiptFooter ?? this.receiptFooter,
    showSoldOutDishes: showSoldOutDishes ?? this.showSoldOutDishes,
    autoUnavailableWhenOutOfStock:
        autoUnavailableWhenOutOfStock ?? this.autoUnavailableWhenOutOfStock,
    prepBufferMinutes: prepBufferMinutes ?? this.prepBufferMinutes,
    takeawayOrdersEnabled: takeawayOrdersEnabled ?? this.takeawayOrdersEnabled,
    offers: offers ?? this.offers,
    paymentMode: paymentMode ?? this.paymentMode,
    currencyCode: currencyCode ?? this.currencyCode,
    wifi: wifi ?? this.wifi,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'taxReg': taxRegistration,
    'taxName': taxName,
    'taxRate': taxRateBasisPoints,
    'serviceRate': serviceChargeBasisPoints,
    'utcOffset': utcOffsetMinutes,
    'partial': allowPartialPayments,
    'methods': [for (final m in onlineMethods) m.name],
    'footer': receiptFooter,
    'showSoldOut': showSoldOutDishes,
    'autoUnavailable': autoUnavailableWhenOutOfStock,
    'prepBuffer': prepBufferMinutes,
    'takeaway': takeawayOrdersEnabled,
    // Also under its old name, which servers from before the rename read
    // (and would otherwise save as "off").
    'parcel': takeawayOrdersEnabled,
    'offers': [for (final o in offers) o.toJson()],
    'paymentMode': paymentMode.name,
    'currency': currencyCode,
    'wifi': wifi.toJson(),
  };
}

/// A dining table.
class RestaurantTable {
  const RestaurantTable({
    required this.number,
    this.seats = 4,
    this.area = '',
    this.isActive = true,
  });

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        number: json['number'] as int,
        seats: json['seats'] as int? ?? 4,
        area: json['area'] as String? ?? '',
        isActive: json['active'] as bool? ?? true,
      );

  final int number;
  final int seats;

  /// Optional zone, e.g. "Terrace".
  final String area;

  /// Inactive tables cannot start new orders.
  final bool isActive;

  RestaurantTable copyWith({int? seats, String? area, bool? isActive}) =>
      RestaurantTable(
        number: number,
        seats: seats ?? this.seats,
        area: area ?? this.area,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toJson() => {
    'number': number,
    'seats': seats,
    if (area.isNotEmpty) 'area': area,
    'active': isActive,
  };
}
