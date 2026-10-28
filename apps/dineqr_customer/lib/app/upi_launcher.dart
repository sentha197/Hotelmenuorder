import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// What happened when a payment link was handed to the phone.
enum UpiLaunchResult {
  /// A UPI app took the link. That says nothing about whether the guest paid.
  opened,

  /// This device has no app that handles UPI links (or not the chosen one).
  noApp,

  /// This kind of device cannot hand a payment to an app (web, desktop).
  unsupported,

  /// The system refused for another reason.
  failed,
}

/// What a UPI app said when the guest came back from it.
enum UpiAppOutcome {
  /// It reports the money as sent (`SUCCESS`, or `SUBMITTED` while the bank
  /// finishes).
  sent,

  /// It reports a failure, e.g. it refused to pay this UPI ID.
  failed,

  /// The guest backed out before paying.
  cancelled,

  /// It said nothing useful.
  unknown,
}

/// A UPI app's own report of a payment it was opened for (Android hands it
/// back; iOS has no such thing). Apps can be wrong or say nothing, so this
/// only decides what the guest is asked next: it never marks anything paid.
@immutable
class UpiAppReply {
  const UpiAppReply(this.outcome, {this.reference = ''});

  /// Reads a UPI app's `response` extra
  /// (`txnId=…&responseCode=…&Status=SUCCESS&txnRef=…&ApprovalRefNo=…`);
  /// [ok] is whether the app finished rather than was backed out of.
  factory UpiAppReply.parse(String? response, {required bool ok}) {
    final fields = <String, String>{
      for (final pair in (response ?? '').split('&'))
        if (pair.contains('='))
          pair
              .substring(0, pair.indexOf('='))
              .trim()
              .toLowerCase(): Uri.decodeQueryComponent(
            pair.substring(pair.indexOf('=') + 1),
          ).trim(),
    };
    final outcome = switch (fields['status']?.toUpperCase()) {
      'SUCCESS' || 'SUBMITTED' => UpiAppOutcome.sent,
      'FAILURE' || 'FAILED' => UpiAppOutcome.failed,
      _ when fields.isEmpty && !ok => UpiAppOutcome.cancelled,
      _ => UpiAppOutcome.unknown,
    };
    // The bank's reference for the transfer (the UTR), when it gave one.
    final reference = UpiReference.normalize(fields['approvalrefno'] ?? '');
    return UpiAppReply(
      outcome,
      reference:
          outcome == UpiAppOutcome.sent && UpiReference.isValid(reference)
          ? reference
          : '',
    );
  }

  final UpiAppOutcome outcome;

  /// The bank reference the app reported for a sent payment, or empty.
  final String reference;

  @override
  String toString() => 'UpiAppReply($outcome, $reference)';
}

/// A UPI app on this phone, as the system reports it.
@immutable
class InstalledUpiApp {
  const InstalledUpiApp({
    required this.id,
    required this.label,
    this.icon,
    this.known,
  });

  /// One of the [UpiApp.named] apps, without a system icon (iOS lends none).
  InstalledUpiApp.of(UpiApp app)
    : this(
        id: defaultTargetPlatform == TargetPlatform.android
            ? app.androidPackage
            : app.scheme,
        label: app.label,
        known: app,
      );

  /// An app as Android's `dineqr/upi` channel lists it (MainActivity.kt).
  factory InstalledUpiApp.fromAndroid(Map<Object?, Object?> app) {
    final package = app['package']! as String;
    final label = app['label'] as String?;
    return InstalledUpiApp(
      id: package,
      label: label == null || label.isEmpty ? package : label,
      icon: app['icon'] as Uint8List?,
      known: UpiApp.ofPackage(package),
    );
  }

  /// Any UPI app: the phone shows its own list. Always offered (NPCI asks
  /// for it), also where no app could be listed.
  static const chooser = InstalledUpiApp(
    id: '',
    label: 'Other UPI apps',
    known: UpiApp.other,
  );

  /// The Android package (`com.phonepe.app`), the app's link scheme on iOS,
  /// or empty for [chooser].
  final String id;

  /// The app's name as this phone shows it.
  final String label;

  /// The app's own icon as the system draws it (PNG); null on iOS.
  final Uint8List? icon;

  /// Google Pay, PhonePe or Paytm ([UpiApp.other] for [chooser]); null for
  /// any other UPI app.
  final UpiApp? known;

  bool get isChooser => id.isEmpty;

  /// A stable name for keys: `googlePay`, `other`, or the package.
  String get key => known?.name ?? id;

  /// Google Pay, PhonePe and Paytm first (in that order), then the rest by
  /// name.
  static List<InstalledUpiApp> sorted(Iterable<InstalledUpiApp> apps) {
    int rank(InstalledUpiApp app) => switch (app.known) {
      final known? => UpiApp.named.indexOf(known),
      null => UpiApp.named.length,
    };
    return apps.toList()..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0
          ? byRank
          : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  @override
  bool operator ==(Object other) => other is InstalledUpiApp && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'InstalledUpiApp($id, $label)';
}

/// Hands a `upi://pay` link to the guest's UPI apps (Google Pay, PhonePe,
/// Paytm, BHIM, ...).
///
/// Opening an app proves nothing about payment: the payment is confirmed by
/// the gateway (or by the restaurant), never by what an app reports back.
abstract interface class UpiLauncher {
  /// Whether this device can hand a link to a UPI app at all.
  bool get canOpenApps;

  /// The UPI apps on this phone, sorted with [InstalledUpiApp.sorted];
  /// [InstalledUpiApp.chooser] is not among them.
  Future<List<InstalledUpiApp>> installedApps();

  /// Opens [link] (a `upi://pay` link, or a gateway's test page) in [app],
  /// or lets the guest pick a UPI app when [app] is null or the chooser.
  /// [appLinks] are a gateway's own links by app key (`gpay`, ...), used
  /// where apps are opened by their own scheme (iOS).
  Future<UpiLaunchResult> open(
    Uri link, {
    InstalledUpiApp? app,
    Map<String, String> appLinks = const {},
  });

  /// What each UPI app [open]ed says when the guest comes back from it.
  Stream<UpiAppReply> get replies;
}

/// The real thing. On Android, through MainActivity.kt's `dineqr/upi`
/// channel: every app that takes `upi://pay` links is listed with its own
/// name and icon, and a payment opens in the chosen app by its package. iOS
/// lists no apps: it only says whether each [UpiApp.named] app's own scheme
/// opens (LSApplicationQueriesSchemes in Info.plist), and opens it by that
/// scheme.
class SystemUpiLauncher implements UpiLauncher {
  const SystemUpiLauncher();

  static const channel = MethodChannel('dineqr/upi');

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  static final _replies = StreamController<UpiAppReply>.broadcast();
  static var _listening = false;

  /// MainActivity.kt calls `returned` with `{ok, response}` when a UPI app
  /// it opened finishes.
  @override
  Stream<UpiAppReply> get replies {
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler((call) async {
        if (call.method != 'returned') return;
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        _replies.add(
          UpiAppReply.parse(
            args['response'] as String?,
            ok: args['ok'] == true,
          ),
        );
      });
    }
    return _replies.stream;
  }

  @override
  bool get canOpenApps =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<List<InstalledUpiApp>> installedApps() async {
    if (!canOpenApps) return const [];
    if (_android) {
      try {
        final found =
            await channel.invokeListMethod<Map<Object?, Object?>>('apps') ??
            const [];
        return InstalledUpiApp.sorted(found.map(InstalledUpiApp.fromAndroid));
      } on Object catch (error) {
        // The chooser still offers whatever the phone has.
        debugPrint('Could not list the UPI apps: $error');
        return const [];
      }
    }
    final found = <InstalledUpiApp>[];
    for (final app in UpiApp.named) {
      try {
        if (await canLaunchUrl(app.probe)) found.add(InstalledUpiApp.of(app));
      } on Object catch (error) {
        debugPrint('Could not check for ${app.label}: $error');
      }
    }
    return found;
  }

  /// [link] for [app] where apps open by their own scheme (iOS): the
  /// gateway's own link for it when there is one, else [link] in its scheme.
  /// Any other app (or none) gets [link] itself.
  @visibleForTesting
  static Uri schemeLink(
    Uri link,
    InstalledUpiApp? app,
    Map<String, String> appLinks,
  ) => switch (app?.known) {
    final known? when !app!.isChooser => switch (appLinks[known.key]) {
      final own? when own.isNotEmpty => Uri.tryParse(own) ?? link,
      _ => known.linkFor(link),
    },
    _ => link,
  };

  @override
  Future<UpiLaunchResult> open(
    Uri link, {
    InstalledUpiApp? app,
    Map<String, String> appLinks = const {},
  }) async {
    if (!canOpenApps) return UpiLaunchResult.unsupported;
    final chosen = app == null || app.isChooser ? null : app;
    if (_android && link.scheme == 'upi') {
      try {
        final result = await channel.invokeMethod<String>('open', {
          'link': link.toString(),
          'package': chosen?.id,
        });
        return switch (result) {
          'opened' => UpiLaunchResult.opened,
          'noApp' => UpiLaunchResult.noApp,
          _ => UpiLaunchResult.failed,
        };
      } on MissingPluginException {
        // An embedding without the channel: hand the plain link over below.
      } on Object catch (error) {
        debugPrint('Could not open a UPI app: $error');
        return UpiLaunchResult.failed;
      }
    }
    final target = _android ? link : schemeLink(link, chosen, appLinks);
    // A gateway's test mode pays on a web page.
    final web = target.scheme == 'https' || target.scheme == 'http';
    try {
      final opened = await launchUrl(
        target,
        // Never a browser for a payment link: it means nothing to one.
        mode: web
            ? LaunchMode.externalApplication
            : LaunchMode.externalNonBrowserApplication,
      );
      return opened ? UpiLaunchResult.opened : UpiLaunchResult.noApp;
    } on Object catch (error) {
      debugPrint('Could not open a UPI app: $error');
      return UpiLaunchResult.failed;
    }
  }
}
