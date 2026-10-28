import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_customer/app/upi_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real launcher against MainActivity.kt's `dineqr/upi` channel (as an
/// Android phone answers it), and the links it opens on iOS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const launcher = SystemUpiLauncher();
  final calls = <MethodCall>[];

  void phone(Object? Function(MethodCall call) answer) =>
      messenger.setMockMethodCallHandler(SystemUpiLauncher.channel, (call) {
        calls.add(call);
        return Future.sync(() => answer(call));
      });

  setUp(calls.clear);
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemUpiLauncher.channel, null),
  );

  const link =
      'upi://pay?pa=cashfree.test@axis&pn=Test%20Cafe&tr=5001&am=450.00&cu=INR';

  group('Android', () {
    test('lists every UPI app with its name and icon, the known ones '
        'first', () async {
      final icon = Uint8List.fromList([137, 80, 78, 71]);
      phone(
        (_) => [
          {'package': 'in.org.npci.upiapp', 'label': 'BHIM', 'icon': icon},
          {'package': 'com.phonepe.app', 'label': 'PhonePe', 'icon': null},
          {'package': 'com.dreamplug.androidapp', 'label': 'CRED'},
          {
            'package': 'com.google.android.apps.nbu.paisa.user',
            'label': 'GPay',
          },
        ],
      );
      final apps = await launcher.installedApps();
      expect(calls.single.method, 'apps');
      expect(apps.map((a) => a.label), ['GPay', 'PhonePe', 'BHIM', 'CRED']);
      expect(apps.map((a) => a.known), [
        UpiApp.googlePay,
        UpiApp.phonePe,
        null,
        null,
      ]);
      expect(apps[2].id, 'in.org.npci.upiapp');
      expect(apps[2].icon, icon);
      expect(apps[2].key, 'in.org.npci.upiapp');
      expect(apps[0].key, 'googlePay');
      expect(apps.any((a) => a.isChooser), isFalse);
    });

    test('a phone that cannot list its apps lists none', () async {
      phone((_) => throw PlatformException(code: 'failed'));
      expect(await launcher.installedApps(), isEmpty);
    });

    test('opens the plain UPI link in the chosen app by its package', () async {
      phone((_) => 'opened');
      final phonePe = InstalledUpiApp.of(UpiApp.phonePe);
      expect(
        await launcher.open(Uri.parse(link), app: phonePe),
        UpiLaunchResult.opened,
      );
      expect(calls.single.method, 'open');
      expect(calls.single.arguments, {
        'link': link,
        'package': 'com.phonepe.app',
      });

      // Any app: the phone's own list.
      await launcher.open(Uri.parse(link), app: InstalledUpiApp.chooser);
      expect(calls.last.arguments, {'link': link, 'package': null});
    });

    test('an app that is gone, or a refusal, is reported', () async {
      phone((_) => 'noApp');
      expect(
        await launcher.open(
          Uri.parse(link),
          app: InstalledUpiApp.of(UpiApp.paytm),
        ),
        UpiLaunchResult.noApp,
      );
      phone((_) => throw PlatformException(code: 'boom'));
      expect(await launcher.open(Uri.parse(link)), UpiLaunchResult.failed);
    });
  });

  group('iOS links', () {
    final upi = Uri.parse(link);

    test('a known app opens by its own scheme with the same payment', () {
      expect(
        SystemUpiLauncher.schemeLink(
          upi,
          InstalledUpiApp.of(UpiApp.phonePe),
          const {},
        ).toString(),
        link.replaceFirst('upi://pay', 'phonepe://pay'),
      );
      expect(
        SystemUpiLauncher.schemeLink(
          upi,
          InstalledUpiApp.of(UpiApp.googlePay),
          const {},
        ).toString(),
        link.replaceFirst('upi://pay', 'tez://upi/pay'),
      );
    });

    test('the gateway\'s own link for the app wins', () {
      expect(
        SystemUpiLauncher.schemeLink(upi, InstalledUpiApp.of(UpiApp.paytm), {
          'paytm': 'paytmmp://pay?pa=x@axis&am=450.00',
        }).toString(),
        'paytmmp://pay?pa=x@axis&am=450.00',
      );
    });

    test('any other app, the chooser and test pages keep the link', () {
      expect(
        SystemUpiLauncher.schemeLink(upi, InstalledUpiApp.chooser, const {}),
        upi,
      );
      expect(SystemUpiLauncher.schemeLink(upi, null, const {}), upi);
      final page = Uri.parse('https://sandbox.example/simulator?am=450.00');
      expect(
        SystemUpiLauncher.schemeLink(
          page,
          InstalledUpiApp.of(UpiApp.phonePe),
          const {},
        ),
        page,
      );
    });
  });
}
