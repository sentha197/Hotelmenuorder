import '../utils/currency.dart';
import 'billing.dart';

/// How a UPI payment to the restaurant's own account is confirmed.
enum UpiVerificationMode {
  /// A cashier checks that the money arrived and records the bank's
  /// transaction ID.
  manual('Manual verification'),

  /// A connected bank or payment provider reports it. Only possible when the
  /// server has such an integration (it has none by default).
  automatic('Automatic verification');

  const UpiVerificationMode(this.label);

  final String label;

  static UpiVerificationMode parse(String? name) => values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => UpiVerificationMode.manual,
  );
}

/// The restaurant's UPI details for payments straight to its own account
/// (no payment gateway). Only public payee details: never a PIN, a card or
/// any bank credential.
///
/// The server is the source of truth and checks the same rules; they are
/// repeated here so a mistake shows in the form before anything is sent.
class UpiSettings {
  const UpiSettings({
    this.enabled = false,
    this.upiId = '',
    this.payeeName = '',
    this.qrImageUrl = '',
    this.verificationMode = UpiVerificationMode.manual,
  });

  factory UpiSettings.fromJson(Map<String, dynamic> json) => UpiSettings(
    enabled: json['enabled'] as bool? ?? false,
    upiId: json['upiId'] as String? ?? '',
    payeeName: json['payeeName'] as String? ?? '',
    qrImageUrl: json['qrImage'] as String? ?? '',
    verificationMode: UpiVerificationMode.parse(
      json['verificationMode'] as String?,
    ),
  );

  /// Guests are only offered UPI while this is on.
  final bool enabled;

  /// The restaurant's UPI ID (VPA), e.g. `cafe@okhdfcbank`.
  final String upiId;

  /// The name guests see in their UPI app.
  final String payeeName;

  /// The restaurant's own merchant QR picture, or empty.
  final String qrImageUrl;

  final UpiVerificationMode verificationMode;

  // handle@bank, lower case: letters, digits, '.', '-' and '_' before the
  // '@', letters and digits after it.
  static final RegExp _idPattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9]{1,31}$',
  );
  static final RegExp _badNameCharacter = RegExp(
    r'[<>\u0000-\u001F\u007F-\u009F]',
  );

  /// A UPI ID as it is stored: trimmed and lower case.
  static String normalizeId(String id) => id.trim().toLowerCase();

  /// Whether [id] (already normalised) looks like `name@bank`.
  static bool isValidId(String id) => _idPattern.hasMatch(id);

  /// Whether [name] (already trimmed) can be shown to guests.
  static bool isValidName(String name) =>
      name.length >= 2 &&
      name.length <= 60 &&
      !_badNameCharacter.hasMatch(name);

  bool get hasQrImage => qrImageUrl.isNotEmpty;

  /// Guests can be offered UPI: switched on and fully set up.
  bool get isReady =>
      enabled && isValidId(normalizeId(upiId)) && isValidName(payeeName.trim());

  /// What is wrong with each field, for showing next to it.
  ({String? upiId, String? payeeName}) get problems {
    final id = normalizeId(upiId);
    final name = payeeName.trim();
    return (
      upiId: id.isNotEmpty
          ? (isValidId(id) ? null : 'Enter a valid UPI ID, like name@bank.')
          : (enabled
                ? "Enter the restaurant's UPI ID to switch UPI payments on."
                : null),
      payeeName: name.isNotEmpty
          ? (isValidName(name) ? null : 'The name must be 2 to 60 characters.')
          : (enabled ? 'Enter the name guests will see when they pay.' : null),
    );
  }

  /// A message for the first problem, or null when these can be saved.
  String? validate() => problems.upiId ?? problems.payeeName;

  UpiSettings copyWith({
    bool? enabled,
    String? upiId,
    String? payeeName,
    String? qrImageUrl,
    UpiVerificationMode? verificationMode,
  }) => UpiSettings(
    enabled: enabled ?? this.enabled,
    upiId: upiId ?? this.upiId,
    payeeName: payeeName ?? this.payeeName,
    qrImageUrl: qrImageUrl ?? this.qrImageUrl,
    verificationMode: verificationMode ?? this.verificationMode,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'upiId': upiId,
    'payeeName': payeeName,
    'qrImage': qrImageUrl,
    'verificationMode': verificationMode.name,
  };

  @override
  bool operator ==(Object other) =>
      other is UpiSettings &&
      other.enabled == enabled &&
      other.upiId == upiId &&
      other.payeeName == payeeName &&
      other.qrImageUrl == qrImageUrl &&
      other.verificationMode == verificationMode;

  @override
  int get hashCode =>
      Object.hash(enabled, upiId, payeeName, qrImageUrl, verificationMode);
}

/// The bank's UPI transaction ID (UTR / reference number) that a cashier
/// records when confirming a payment, or that a guest may type to help them.
/// Same rule as the server: 6 to 40 letters or digits (and `. _ / -`).
abstract final class UpiReference {
  static final RegExp _pattern = RegExp(r'^[A-Z0-9][A-Z0-9._/-]{5,39}$');

  static const rule = 'The UPI transaction ID is 6 to 40 letters or digits.';

  /// As it is stored: trimmed and upper case.
  static String normalize(String reference) => reference.trim().toUpperCase();

  /// Whether [reference] (already normalised) is well formed.
  static bool isValid(String reference) => _pattern.hasMatch(reference);
}

/// What the owner sees when editing the payment settings: the saved details
/// and whether this server can verify UPI payments automatically.
class PaymentSettingsSnapshot {
  const PaymentSettingsSnapshot({
    this.upi = const UpiSettings(),
    this.automaticVerificationAvailable = false,
  });

  factory PaymentSettingsSnapshot.fromJson(Map<String, dynamic> json) =>
      PaymentSettingsSnapshot(
        upi: UpiSettings.fromJson(json),
        automaticVerificationAvailable:
            json['automaticVerificationAvailable'] as bool? ?? false,
      );

  final UpiSettings upi;

  /// True only when a bank or payment-provider integration is connected.
  final bool automaticVerificationAvailable;
}

/// The `upi://pay` link for one payment (the NPCI UPI linking format): what
/// a UPI app opens, and what the fallback QR code contains.
///
/// It carries the restaurant's UPI ID and name, the exact amount, INR and a
/// reference that is unique to the payment, so the guest has nothing to type
/// and the restaurant can match the credit to the bill. Opening it proves
/// nothing: whether the money moved is decided by staff, not by the app.
class UpiPaymentLink {
  const UpiPaymentLink({
    required this.payeeUpiId,
    required this.payeeName,
    required this.amount,
    required this.transactionRef,
    required this.note,
  });

  /// The link for [payment] of [invoice], paid to the restaurant described by
  /// [settings]. Everything in it is derived, so it can be rebuilt at any
  /// time (for example when the guest comes back to the screen).
  factory UpiPaymentLink.forPayment({
    required UpiSettings settings,
    required Invoice invoice,
    required PaymentTransaction payment,
  }) => UpiPaymentLink(
    payeeUpiId: settings.upiId,
    payeeName: settings.payeeName,
    amount: payment.amount,
    transactionRef: payment.id,
    note: 'Bill ${invoice.billNumber}',
  );

  static const currency = 'INR';

  final String payeeUpiId;
  final String payeeName;
  final Money amount;

  /// Unique per payment attempt (the server's payment id).
  final String transactionRef;

  /// Shown in the guest's and the restaurant's bank statements.
  final String note;

  /// The amount as UPI wants it: rupees with two decimals, e.g. `450.00`.
  String get amountText =>
      '${amount.paise ~/ 100}.${(amount.paise % 100).toString().padLeft(2, '0')}';

  // Percent-encoded (a space is %20, never '+'); '@' stays readable in the
  // UPI ID, as UPI apps expect.
  static String _encode(String value) =>
      Uri.encodeComponent(value).replaceAll('%40', '@');

  String get uriString =>
      'upi://pay?pa=${_encode(payeeUpiId)}&pn=${_encode(payeeName)}'
      '&am=$amountText&cu=$currency&tn=${_encode(note)}'
      '&tr=${_encode(transactionRef)}';

  Uri get uri => Uri.parse(uriString);
}
