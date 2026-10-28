import 'dart:convert';
import 'dart:typed_data';

/// A UPI app guests often pay with. On Android a payment opens in it as a
/// plain `upi://pay` link sent to its [androidPackage] (how Google documents
/// it for Google Pay); on iOS, which only opens apps by their own link
/// scheme, as its [scheme] link. [other] is the plain link, for which the
/// phone offers every installed UPI app (NPCI asks that this always be
/// offered).
enum UpiApp {
  googlePay(
    'Google Pay',
    'gpay',
    'tez',
    'upi/pay',
    'com.google.android.apps.nbu.paisa.user',
  ),
  phonePe('PhonePe', 'phonepe', 'phonepe', 'pay', 'com.phonepe.app'),
  paytm('Paytm', 'paytm', 'paytmmp', 'pay', 'net.one97.paytm'),
  other('Other UPI apps', 'default', 'upi', 'pay', '');

  const UpiApp(
    this.label,
    this.key,
    this.scheme,
    this.path,
    this.androidPackage,
  );

  final String label;

  /// Its name in a gateway's checkout links (`gpay`, `default`, ...).
  final String key;

  /// The link scheme the app registers on iOS (`tez`, `phonepe`, ...).
  final String scheme;

  /// What follows `scheme://` before the query (`upi/pay` for Google Pay).
  final String path;

  /// Its Android package name; empty for [other].
  final String androidPackage;

  /// A link that only this app handles, to check whether it is installed.
  Uri get probe => Uri.parse('$scheme://$path');

  /// The apps with a scheme of their own, in the order guests see them.
  static const named = [googlePay, phonePe, paytm];

  /// The named app with Android package [package], if any.
  static UpiApp? ofPackage(String package) =>
      named.where((app) => app.androidPackage == package).firstOrNull;

  /// [upiPay] (a `upi://pay?...` link) for this app: the same payee, amount
  /// and note, opened by this app's own scheme. Anything but a `upi:` link
  /// (a gateway's test page) is left as it is.
  Uri linkFor(Uri upiPay) => upiPay.scheme != 'upi'
      ? upiPay
      : Uri.parse(
          '$scheme://$path${upiPay.hasQuery ? '?${upiPay.query}' : ''}',
        );

  /// This app's link from a gateway checkout: the gateway's own link for
  /// the app when it gave one, otherwise its plain link opened by this app.
  Uri? linkIn(GatewayCheckout checkout) {
    final own = checkout.links[key];
    if (own != null && own.isNotEmpty) return Uri.tryParse(own);
    final plain = checkout.payLink;
    return plain == null ? null : linkFor(plain);
  }
}

/// What a guest pays a gateway UPI payment with (from the server's
/// `/payments/{id}/checkout`): app links and a QR code, all for the exact
/// amount (the server checks each one). Paying them proves nothing to the
/// app: the gateway reports the payment to the server, which settles the
/// bill.
class GatewayCheckout {
  const GatewayCheckout({
    this.links = const {},
    this.qrImage = '',
    this.qrText = '',
    this.expiresAt,
  });

  factory GatewayCheckout.fromJson(Map<String, dynamic> json) =>
      GatewayCheckout(
        links: {
          for (final MapEntry(:key, :value)
              in ((json['links'] as Map<String, dynamic>?) ?? const {}).entries)
            if (value is String) key: value,
        },
        qrImage: json['qrImage'] as String? ?? '',
        qrText: json['qrText'] as String? ?? '',
        expiresAt: switch (json['expiresAt']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
      );

  /// Links by app key (`default`, `gpay`, `phonepe`, `paytm`, `bhim`).
  final Map<String, String> links;

  /// A `data:image/png;base64,...` picture of the QR code, or empty.
  final String qrImage;

  /// The QR code as the `upi://pay` link it holds, for the app to draw when
  /// the gateway sends no picture; or empty.
  final String qrText;

  /// When the gateway stops taking this payment.
  final DateTime? expiresAt;

  /// The plain link any UPI app opens: `default`, else any `upi:` link, else
  /// whatever the gateway gave (in its test mode, a web page). Null when
  /// there is none.
  Uri? get payLink {
    final plain =
        links['default'] ??
        links.values.where((link) => link.startsWith('upi:')).firstOrNull ??
        links.values.firstOrNull;
    return plain == null || plain.isEmpty ? null : Uri.tryParse(plain);
  }

  bool get hasQr => qrPng != null || qrText.isNotEmpty;

  /// The QR code's PNG bytes, or null when there is none (or it is broken).
  Uint8List? get qrPng {
    final comma = qrImage.indexOf(',');
    if (!qrImage.startsWith('data:image/') || comma < 0) return null;
    try {
      return base64Decode(qrImage.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }
}
