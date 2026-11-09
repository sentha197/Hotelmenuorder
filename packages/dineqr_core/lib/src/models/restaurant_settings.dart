import '../utils/currency.dart';
import 'billing.dart';
import 'discount_offer.dart';
import 'geofence.dart';
import 'network_access.dart';
import 'payment_option.dart';
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
    this.onlineOptions = const {
      PaymentOption.upi,
      PaymentOption.scanAndPay,
      PaymentOption.card,
      PaymentOption.netBanking,
      PaymentOption.wallet,
    },
    this.receiptFooter = 'Thank you for dining with us!',
    this.showSoldOutDishes = true,
    this.autoUnavailableWhenOutOfStock = true,
    this.prepBufferMinutes = 5,
    this.takeawayOrdersEnabled = false,
    this.offers = defaultOffers,
    this.currencyCode = 'INR',
    this.wifi = DineInWifi.off,
    this.location = DineInLocation.off,
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
      onlineOptions: switch (json['methods']) {
        final List<dynamic> names => {
          for (final name in names)
            ?PaymentOption.fromSettingKey(name as String?),
        },
        _ => defaults.onlineOptions,
      },
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
      currencyCode: json['currency'] as String? ?? 'INR',
      wifi: DineInWifi.fromJson(json['wifi'] as Map<String, dynamic>?),
      location: DineInLocation.fromJson(
        json['location'] as Map<String, dynamic>?,
      ),
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

  /// The GPS ordering area as guests see it (read only: staff change it
  /// with [GeofenceSettings]).
  final DineInLocation location;

  /// Whether guests may pay part of a bill and the rest later.
  final bool allowPartialPayments;

  /// The online options guests may be offered ([PaymentOption.online]), each
  /// switched on and off by itself: paying from a UPI app ([PaymentOption.upi])
  /// and scanning a QR code ([PaymentOption.scanAndPay]) are separate. What
  /// guests actually see also depends on the payment gateway (and, for UPI,
  /// on the restaurant's own UPI ID).
  final Set<PaymentOption> onlineOptions;

  /// The payment methods behind [onlineOptions] (UPI and QR are both UPI).
  Set<PaymentMethodType> get onlineMethods => {
    for (final option in onlineOptions) ?option.method,
  };
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
    Set<PaymentOption>? onlineOptions,
    String? receiptFooter,
    bool? showSoldOutDishes,
    bool? autoUnavailableWhenOutOfStock,
    int? prepBufferMinutes,
    bool? takeawayOrdersEnabled,
    List<DiscountOffer>? offers,
    String? currencyCode,
    DineInWifi? wifi,
    DineInLocation? location,
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
    onlineOptions: onlineOptions ?? this.onlineOptions,
    receiptFooter: receiptFooter ?? this.receiptFooter,
    showSoldOutDishes: showSoldOutDishes ?? this.showSoldOutDishes,
    autoUnavailableWhenOutOfStock:
        autoUnavailableWhenOutOfStock ?? this.autoUnavailableWhenOutOfStock,
    prepBufferMinutes: prepBufferMinutes ?? this.prepBufferMinutes,
    takeawayOrdersEnabled: takeawayOrdersEnabled ?? this.takeawayOrdersEnabled,
    offers: offers ?? this.offers,
    currencyCode: currencyCode ?? this.currencyCode,
    wifi: wifi ?? this.wifi,
    location: location ?? this.location,
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
    // In display order, so the server keeps them in that order too.
    'methods': [
      for (final option in PaymentOption.online)
        if (onlineOptions.contains(option)) option.settingKey,
    ],
    'footer': receiptFooter,
    'showSoldOut': showSoldOutDishes,
    'autoUnavailable': autoUnavailableWhenOutOfStock,
    'prepBuffer': prepBufferMinutes,
    'takeaway': takeawayOrdersEnabled,
    // Also under its old name, which servers from before the rename read
    // (and would otherwise save as "off").
    'parcel': takeawayOrdersEnabled,
    'offers': [for (final o in offers) o.toJson()],
    'currency': currencyCode,
    'wifi': wifi.toJson(),
    'location': location.toJson(),
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
