import 'package:flutter/foundation.dart';

import '../models/discount_offer.dart';
import '../models/order_type.dart';
import '../models/pricing.dart';
import '../models/restaurant_settings.dart';
import '../models/staff.dart';
import '../repositories/settings_repository.dart';
import '../utils/currency.dart';
import '../utils/restaurant_time.dart';
import 'access.dart';

/// A rejected settings change, with a message for the form.
class ValidationException implements Exception {
  const ValidationException(this.message);

  final String message;

  @override
  String toString() => 'ValidationException($message)';
}

/// Restaurant settings, offers and tables.
class SettingsController extends ChangeNotifier {
  SettingsController(this._repository, this._guard, this._audit);

  final SettingsRepository _repository;
  final AccessGuard _guard;
  final AuditLog? _audit;

  RestaurantSettings _settings = const RestaurantSettings();
  List<RestaurantTable> _tables = const [];

  RestaurantSettings get settings => _settings;

  PricingConfig get pricing => _settings.pricing;

  /// Tables sorted by number.
  List<RestaurantTable> get tables => _tables;

  Future<void> load() async {
    // Independent reads, side by side; a failure surfaces as it was thrown.
    final settingsRead = _repository.fetchSettings();
    final tablesRead = _repository.fetchTables();
    await Future.wait([settingsRead, tablesRead], eagerError: true);
    _settings = await settingsRead;
    _tables = [...await tablesRead]
      ..sort((a, b) => a.number.compareTo(b.number));
    _applyGlobals(_settings);
    notifyListeners();
  }

  /// Time zone and currency are read everywhere through static helpers.
  static void _applyGlobals(RestaurantSettings settings) {
    RestaurantTime.configure(settings.utcOffsetMinutes);
    CurrencyFormatter.configure(settings.currencyCode);
  }

  RestaurantTable? table(int number) =>
      _tables.where((t) => t.number == number).firstOrNull;

  bool isKnownTable(int number) => table(number) != null;

  /// Whether guests can start ordering at [number]: an active table, or
  /// takeaway ([OrderTables.takeaway], which is never in [tables]) while the
  /// restaurant takes takeaway orders.
  bool isOrderable(int number) => OrderTables.isTakeaway(number)
      ? _settings.takeawayOrdersEnabled
      : table(number)?.isActive ?? false;

  // ---------------------------------------------------------------- settings

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _phone = RegExp(r'^[0-9+()\-\s]{6,20}$');
  static final RegExp _taxId = RegExp(r'^[A-Za-z0-9\-]{5,20}$');

  /// Returns a message for the first invalid field, or null.
  static String? validate(RestaurantSettings s) {
    final name = s.name.trim();
    if (name.length < 2 || name.length > 60) {
      return 'Restaurant name must be 2 to 60 characters.';
    }
    if (s.email.isNotEmpty && !_email.hasMatch(s.email)) {
      return 'Enter a valid email address or leave it empty.';
    }
    if (s.phone.isNotEmpty && !_phone.hasMatch(s.phone)) {
      return 'Enter a valid phone number or leave it empty.';
    }
    if (s.address.length > 160) return 'Address can be at most 160 characters.';
    if (s.taxRegistration.isNotEmpty && !_taxId.hasMatch(s.taxRegistration)) {
      return 'Tax registration must be 5 to 20 letters or digits.';
    }
    final taxName = s.taxName.trim();
    if (taxName.isEmpty || taxName.length > 20) {
      return 'Tax name must be 1 to 20 characters.';
    }
    if (s.taxRateBasisPoints < 0 || s.taxRateBasisPoints > 2800) {
      return 'Tax rate must be between 0% and 28%.';
    }
    if (s.serviceChargeBasisPoints < 0 || s.serviceChargeBasisPoints > 2000) {
      return 'Service charge must be between 0% and 20%.';
    }
    if (s.utcOffsetMinutes < -720 || s.utcOffsetMinutes > 840) {
      return 'Choose a valid time zone.';
    }
    if (s.receiptFooter.length > 120) {
      return 'Receipt note can be at most 120 characters.';
    }
    if (s.prepBufferMinutes < 0 || s.prepBufferMinutes > 60) {
      return 'Preparation buffer must be 0 to 60 minutes.';
    }
    if (CurrencyFormatter.lookup(s.currencyCode) == null) {
      return 'Choose a supported currency.';
    }
    return null;
  }

  Future<void> updateSettings(RestaurantSettings next) async {
    _guard.require(Permission.manageSettings);
    final trimmed = next.copyWith(
      name: next.name.trim(),
      phone: next.phone.trim(),
      email: next.email.trim().toLowerCase(),
      address: next.address.trim(),
      taxRegistration: next.taxRegistration.trim().toUpperCase(),
      taxName: next.taxName.trim(),
      receiptFooter: next.receiptFooter.trim(),
    );
    final error = validate(trimmed);
    if (error != null) throw ValidationException(error);
    final previous = _settings;
    final changes = _describeChanges(previous, trimmed);
    _settings = trimmed;
    _applyGlobals(trimmed);
    notifyListeners();
    try {
      await _repository.saveSettings(trimmed);
    } on Object {
      // The server refused it (e.g. live payments without a gateway): show
      // what is really in force again.
      _settings = previous;
      _applyGlobals(previous);
      notifyListeners();
      rethrow;
    }
    await _audit?.record(
      'settings.update',
      changes.isEmpty ? 'Saved settings' : 'Updated ${changes.join(', ')}',
    );
  }

  static List<String> _describeChanges(
    RestaurantSettings a,
    RestaurantSettings b,
  ) => [
    if (a.name != b.name) 'name',
    if (a.phone != b.phone || a.email != b.email || a.address != b.address)
      'contact details',
    if (a.taxRegistration != b.taxRegistration) 'tax registration',
    if (a.taxRateBasisPoints != b.taxRateBasisPoints || a.taxName != b.taxName)
      'tax (${b.taxName} ${PricingConfig.formatRate(b.taxRateBasisPoints)})',
    if (a.serviceChargeBasisPoints != b.serviceChargeBasisPoints)
      'service charge (${PricingConfig.formatRate(b.serviceChargeBasisPoints)})',
    if (a.utcOffsetMinutes != b.utcOffsetMinutes)
      'time zone (${b.utcOffsetLabel})',
    if (a.allowPartialPayments != b.allowPartialPayments) 'partial payments',
    if (!setEquals(a.onlineMethods, b.onlineMethods)) 'payment methods',
    if (a.receiptFooter != b.receiptFooter) 'receipt note',
    if (a.showSoldOutDishes != b.showSoldOutDishes) 'sold-out display',
    if (a.autoUnavailableWhenOutOfStock != b.autoUnavailableWhenOutOfStock)
      'stock rule',
    if (a.prepBufferMinutes != b.prepBufferMinutes) 'preparation buffer',
    if (a.takeawayOrdersEnabled != b.takeawayOrdersEnabled)
      'takeaway (${b.takeawayOrdersEnabled ? 'open' : 'closed'})',
    if (a.paymentMode != b.paymentMode)
      'payment mode (${b.paymentMode.label.toLowerCase()})',
    if (a.currencyCode != b.currencyCode) 'currency (${b.currencyCode})',
  ];

  // ------------------------------------------------------------------ offers

  /// Validates and saves [offer] (a coupon). [originalCode] is the code
  /// being edited (it may be renamed).
  Future<void> saveOffer(DiscountOffer offer, {String? originalCode}) async {
    _guard.require(Permission.manageOffers);
    final code = DiscountOffer.normalize(offer.code);
    if (!DiscountOffer.isValidCode(code)) {
      throw const ValidationException(
        'Codes use 3 to 16 capital letters or digits, e.g. WELCOME10.',
      );
    }
    final clash = _settings.offers.any(
      (o) => o.code == code && o.code != originalCode,
    );
    if (clash) throw ValidationException('$code already exists.');
    if (offer.title.trim().isEmpty || offer.title.trim().length > 40) {
      throw const ValidationException(
        'Give the offer a title (up to 40 characters).',
      );
    }
    if (offer.type == DiscountType.percent &&
        (offer.value < 100 || offer.value > 9000)) {
      throw const ValidationException('Percentage must be between 1% and 90%.');
    }
    if (offer.type == DiscountType.flat &&
        (offer.value < 100 || offer.value > 10000000)) {
      throw ValidationException(
        'Flat discount must be at least '
        '${CurrencyFormatter.format(const Money.rupees(1))}.',
      );
    }
    if (offer.minSubtotal.paise < 0) {
      throw const ValidationException('Minimum order cannot be negative.');
    }
    final datesProblem = validateDates(offer.startsOn, offer.endsOn);
    if (datesProblem != null) throw ValidationException(datesProblem);
    final limitProblem = validateUsageLimit(offer.usageLimit);
    if (limitProblem != null) throw ValidationException(limitProblem);
    final normalized = DiscountOffer(
      code: code,
      title: offer.title.trim(),
      type: offer.type,
      value: offer.value,
      minSubtotal: offer.minSubtotal,
      maxDiscount: offer.maxDiscount,
      isActive: offer.isActive,
      startsOn: offer.startsOn,
      endsOn: offer.endsOn,
      usageLimit: offer.usageLimit,
    );
    final saved = await _repository.saveOffer(
      normalized,
      originalCode: originalCode,
    );
    _replaceOffer(originalCode ?? code, saved);
    await _audit?.record(
      originalCode == null ? 'offer.create' : 'offer.update',
      '${originalCode == null ? 'Created' : 'Updated'} offer $code '
      '(${normalized.summary})',
      targetId: code,
    );
  }

  Future<void> setOfferActive(String code, bool active) async {
    _guard.require(Permission.manageOffers);
    final saved = await _repository.setOfferActive(code, active);
    _replaceOffer(code, saved);
    await _audit?.record(
      'offer.toggle',
      '${active ? 'Activated' : 'Paused'} offer $code',
      targetId: code,
    );
  }

  Future<void> deleteOffer(String code) async {
    _guard.require(Permission.manageOffers);
    await _repository.deleteOffer(code);
    _settings = _settings.copyWith(
      offers: [
        for (final o in _settings.offers)
          if (o.code != code) o,
      ],
    );
    notifyListeners();
    await _audit?.record('offer.delete', 'Deleted offer $code', targetId: code);
  }

  /// Puts [saved] where [code] was (or at the end).
  void _replaceOffer(String code, DiscountOffer saved) {
    final exists = _settings.offers.any((o) => o.code == code);
    _settings = _settings.copyWith(
      offers: exists
          ? [for (final o in _settings.offers) o.code == code ? saved : o]
          : [..._settings.offers, saved],
    );
    notifyListeners();
  }

  /// Shared by coupons, special offers and combos (same rules as the
  /// server's PromotionService).
  static String? validateDates(DateTime? startsOn, DateTime? endsOn) =>
      startsOn != null && endsOn != null && endsOn.isBefore(startsOn)
      ? 'The last day cannot be before the first day.'
      : null;

  static const maxUsageLimit = 1000000;

  static String? validateUsageLimit(int? limit) =>
      limit != null && (limit < 1 || limit > maxUsageLimit)
      ? 'A usage limit is 1 to 10,00,000 orders, or none.'
      : null;

  // ------------------------------------------------------------------ tables

  static String? validateTable(int number, int seats) {
    if (number < 1 || number > 999) return 'Table numbers go from 1 to 999.';
    if (seats < 1 || seats > 30) return 'Seats must be between 1 and 30.';
    return null;
  }

  Future<void> addTable(int number, {int seats = 4, String area = ''}) async {
    _guard.require(Permission.manageTables);
    final error = validateTable(number, seats);
    if (error != null) throw ValidationException(error);
    if (isKnownTable(number)) {
      throw ValidationException('Table $number already exists.');
    }
    await _saveTables([
      ..._tables,
      RestaurantTable(number: number, seats: seats, area: area.trim()),
    ]);
    await _audit?.record(
      'table.create',
      'Added table $number ($seats seats)',
      targetId: '$number',
    );
  }

  Future<void> updateTable(RestaurantTable updated) async {
    _guard.require(Permission.manageTables);
    final error = validateTable(updated.number, updated.seats);
    if (error != null) throw ValidationException(error);
    await _saveTables([
      for (final t in _tables) t.number == updated.number ? updated : t,
    ]);
    await _audit?.record(
      'table.update',
      'Updated table ${updated.number} (${updated.seats} seats'
          '${updated.area.isEmpty ? '' : ', ${updated.area}'})',
      targetId: '${updated.number}',
    );
  }

  Future<void> setTableActive(int number, bool active) async {
    _guard.require(Permission.manageTables);
    final current = table(number);
    if (current == null) return;
    await _saveTables([
      for (final t in _tables)
        t.number == number ? t.copyWith(isActive: active) : t,
    ]);
    await _audit?.record(
      'table.toggle',
      '${active ? 'Activated' : 'Deactivated'} table $number',
      targetId: '$number',
    );
  }

  /// [hasOpenOrders] guards against removing a table guests are using.
  Future<void> removeTable(int number, {required bool hasOpenOrders}) async {
    _guard.require(Permission.manageTables);
    if (hasOpenOrders) {
      throw ValidationException(
        'Table $number has open orders or unpaid bills. Close them first.',
      );
    }
    await _saveTables([
      for (final t in _tables)
        if (t.number != number) t,
    ]);
    await _audit?.record(
      'table.delete',
      'Removed table $number',
      targetId: '$number',
    );
  }

  Future<void> _saveTables(List<RestaurantTable> tables) async {
    _tables = [...tables]..sort((a, b) => a.number.compareTo(b.number));
    notifyListeners();
    await _repository.saveTables(_tables);
  }

  /// Restores default settings and tables (demo reset).
  Future<void> reset() async {
    await _repository.reset();
    await load();
  }

  /// Rupees text field → paise, or null when invalid.
  static Money? parseRupees(String text) {
    final cleaned = text
        .replaceAll(CurrencyFormatter.symbol, '')
        .replaceAll(RegExp(r'[₹,\s]'), '');
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final rupees = int.parse(match.group(1)!);
    final paise = int.parse((match.group(2) ?? '0').padRight(2, '0'));
    return Money(rupees * 100 + paise);
  }

  /// Percent text field (e.g. `5`, `2.5`) → basis points, or null.
  static int? parsePercent(String text) {
    final cleaned = text.replaceAll('%', '').trim();
    final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = int.parse((match.group(2) ?? '0').padRight(2, '0'));
    return whole * 100 + fraction;
  }
}
