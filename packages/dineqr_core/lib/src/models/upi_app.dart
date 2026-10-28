import 'dart:convert';
import 'dart:typed_data';

/// A UPI app a guest can pay with. Each opens a UPI payment link with its own
/// scheme, so the right app opens with the payee and amount filled in;
/// [other] is the plain `upi://pay` link, for which the phone offers every
/// installed UPI app.
enum UpiApp {
  googlePay('Google Pay', 'gpay', 'tez', 'upi/pay'),
  phonePe('PhonePe', 'phonepe', 'phonepe', 'pay'),
  paytm('Paytm', 'paytm', 'paytmmp', 'pay'),
  other('Other UPI apps', 'default', 'upi', 'pay');

  const UpiApp(this.label, this.key, this.scheme, this.path);

  final String label;

  /// Its name in a gateway's checkout links (`gpay`, `default`, ...).
  final String key;

  /// The link scheme the app registers (`tez`, `phonepe`, ...).
  final String scheme;

  /// What follows `scheme://` before the query (`upi/pay` for Google Pay).
  final String path;

  /// A link that only this app handles, to check whether it is installed.
  Uri get probe => Uri.parse('$scheme://$path');

  /// The apps with a scheme of their own, in the order guests see them.
  static const named = [googlePay, phonePe, paytm];

  /// [upiPay] (a `upi://pay?...` link) for this app: the same payee, amount
  /// and note, opened by this app.
  Uri linkFor(Uri upiPay) =>
      Uri.parse('$scheme://$path${upiPay.hasQuery ? '?${upiPay.query}' : ''}');

  /// This app's link from a gateway checkout: the gateway's own link for
  /// the app when it gave one, otherwise its plain link opened by this app.
  Uri? linkIn(GatewayCheckout checkout) {
    final own = checkout.links[key];
    if (own != null && own.isNotEmpty) return Uri.parse(own);
    final plain = checkout.links['default'];
    return plain == null || plain.isEmpty ? null : linkFor(Uri.parse(plain));
  }
}

/// What a guest pays a gateway UPI payment with (from the server's
/// `/payments/{id}/checkout`): app links and a QR code, both for the exact
/// amount. Paying them proves nothing to the app: the gateway reports the
/// payment to the server, which settles the bill.
class GatewayCheckout {
  const GatewayCheckout({
    this.links = const {},
    this.qrImage = '',
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
        expiresAt: switch (json['expiresAt']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
      );

  /// Links by app key (`default`, `gpay`, `phonepe`, `paytm`, `bhim`).
  final Map<String, String> links;

  /// A `data:image/png;base64,...` picture of the QR code, or empty.
  final String qrImage;

  /// When the gateway stops taking this payment.
  final DateTime? expiresAt;

  bool get hasQr => qrPng != null;

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
