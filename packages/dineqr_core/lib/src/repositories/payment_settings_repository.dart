import '../models/upi.dart';

/// The restaurant's UPI payment settings. Only a server can hold them (the
/// guests' apps read them from there, and cashiers confirm payments against
/// them), so the offline demo has none.
abstract interface class PaymentSettingsRepository {
  /// False when this build cannot read or save payment settings.
  bool get isAvailable;

  Future<PaymentSettingsSnapshot> fetch();

  /// Saves [settings] and returns what the server stored.
  Future<PaymentSettingsSnapshot> save(UpiSettings settings);
}

/// Stores the restaurant's UPI QR picture and returns the URL to save with
/// the settings. Implemented by repositories backed by a server with image
/// storage. Uses the same size and format limits as dish photos
/// ([DishImageUploader]).
abstract interface class UpiQrUploader {
  Future<String> uploadUpiQr({
    required List<int> bytes,
    required String filename,
  });
}

/// Used where there is no server (the offline demo).
class UnavailablePaymentSettingsRepository
    implements PaymentSettingsRepository {
  const UnavailablePaymentSettingsRepository();

  @override
  bool get isAvailable => false;

  @override
  Future<PaymentSettingsSnapshot> fetch() async =>
      const PaymentSettingsSnapshot();

  @override
  Future<PaymentSettingsSnapshot> save(UpiSettings settings) =>
      throw StateError(
        'UPI payment settings need the restaurant server. They are not part '
        'of the offline demo.',
      );
}
