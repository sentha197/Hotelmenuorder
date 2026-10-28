import 'package:flutter/foundation.dart';

import '../models/staff.dart';
import '../models/upi.dart';
import '../repositories/menu_repository.dart';
import '../repositories/payment_settings_repository.dart';
import 'access.dart';
import 'settings_controller.dart';

/// The restaurant's UPI payment settings: what the owner edits, and whether
/// this server can verify payments automatically. The server validates and
/// authorises every save; the checks here only save a round trip.
class PaymentSettingsController extends ChangeNotifier {
  PaymentSettingsController(this._repository, this._guard);

  final PaymentSettingsRepository _repository;
  final AccessGuard _guard;

  UpiSettings _upi = const UpiSettings();
  bool _automaticAvailable = false;
  bool _loaded = false;

  /// Shown when automatic verification is chosen without a provider.
  static const automaticUnavailableMessage =
      'Automatic verification needs a bank or payment provider connected to '
      'this server, and none is set up. Choose manual verification so a '
      'cashier confirms each payment.';

  /// Whether this build can read and save payment settings (it cannot in the
  /// offline demo).
  bool get isAvailable => _repository.isAvailable;

  /// Whether a merchant QR picture can be uploaded.
  bool get canUploadQr => _repository is UpiQrUploader;

  /// The saved settings.
  UpiSettings get upi => _upi;

  /// True only when the server has a bank or payment-provider integration.
  bool get automaticVerificationAvailable => _automaticAvailable;

  /// Whether the server's settings have been read.
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (!isAvailable) return;
    _apply(await _repository.fetch());
  }

  void _apply(PaymentSettingsSnapshot snapshot) {
    _upi = snapshot.upi;
    _automaticAvailable = snapshot.automaticVerificationAvailable;
    _loaded = true;
    notifyListeners();
  }

  /// Validates and saves [next].
  Future<void> save(UpiSettings next) async {
    _guard.require(Permission.manageSettings);
    final cleaned = next.copyWith(
      upiId: UpiSettings.normalizeId(next.upiId),
      payeeName: next.payeeName.trim(),
    );
    final problem = cleaned.validate();
    if (problem != null) throw ValidationException(problem);
    if (cleaned.verificationMode == UpiVerificationMode.automatic &&
        !_automaticAvailable) {
      throw const ValidationException(automaticUnavailableMessage);
    }
    _apply(await _repository.save(cleaned));
  }

  /// Uploads a merchant QR picture and returns its URL, to be saved with the
  /// settings. Checked here (size and real file type) before the upload.
  Future<String> uploadQr(List<int> bytes) async {
    _guard.require(Permission.manageSettings);
    final repository = _repository;
    if (repository is! UpiQrUploader) {
      throw const ValidationException(
        'Uploading a QR image needs the restaurant server.',
      );
    }
    if (bytes.isEmpty) {
      throw const ValidationException('Choose a QR image to upload.');
    }
    if (bytes.length > DishImageUploader.maxBytes) {
      final limit = DishImageUploader.maxBytes ~/ (1024 * 1024);
      throw ValidationException(
        'That image is too large. The limit is $limit MB.',
      );
    }
    // Which formats are accepted is the server's call, as for dish photos:
    // it decodes the file and answers with a message.
    final extension = DishImageUploader.extensionFor(bytes) ?? 'img';
    return (repository as UpiQrUploader).uploadUpiQr(
      bytes: bytes,
      filename: 'upi-qr.$extension',
    );
  }
}
