import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// What happened when a payment link was handed to the phone.
enum UpiLaunchResult {
  /// A UPI app took the link. That says nothing about whether the guest paid.
  opened,

  /// This device has no app that handles UPI links.
  noApp,

  /// This kind of device cannot hand a payment to an app (web, desktop).
  unsupported,

  /// The system refused for another reason.
  failed,
}

/// Hands a `upi://pay` link to the guest's UPI apps (Google Pay, PhonePe,
/// Paytm, BHIM, ...). On Android the system offers every installed app that
/// handles UPI links; the guest picks one.
///
/// Opening an app proves nothing about payment: Android gives no trustworthy
/// result for a link, so the app asks the guest and the restaurant confirms.
abstract interface class UpiLauncher {
  /// Whether this device can hand a link to a UPI app at all.
  bool get canOpenApps;

  /// Which of [UpiApp.named] are installed (as far as the system says).
  Future<Set<UpiApp>> installedApps();

  Future<UpiLaunchResult> open(Uri link);
}

/// The real thing, through the system.
class SystemUpiLauncher implements UpiLauncher {
  const SystemUpiLauncher();

  @override
  bool get canOpenApps =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<Set<UpiApp>> installedApps() async {
    if (!canOpenApps) return const {};
    final found = <UpiApp>{};
    for (final app in UpiApp.named) {
      try {
        // Each app's own scheme is declared in the Android manifest's
        // <queries> and iOS's LSApplicationQueriesSchemes.
        if (await canLaunchUrl(app.probe)) found.add(app);
      } on Object catch (error) {
        debugPrint('Could not check for ${app.label}: $error');
      }
    }
    return found;
  }

  @override
  Future<UpiLaunchResult> open(Uri link) async {
    if (!canOpenApps) return UpiLaunchResult.unsupported;
    try {
      // Never a browser: a upi:// link means nothing to one.
      final opened = await launchUrl(
        link,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      return opened ? UpiLaunchResult.opened : UpiLaunchResult.noApp;
    } on Object catch (error) {
      debugPrint('Could not open a UPI app: $error');
      return UpiLaunchResult.failed;
    }
  }
}
