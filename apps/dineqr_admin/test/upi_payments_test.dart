import 'dart:typed_data';

import 'package:dineqr_admin/app/admin_theme.dart';
import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/app/dependencies.dart';
import 'package:dineqr_admin/modules/settings/payment_settings_card.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_admin/widgets/admin_widgets.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/brand_fonts.dart';
import 'support/harness.dart';

const _ready = UpiSettings(
  enabled: true,
  upiId: 'cafe@okhdfcbank',
  payeeName: 'Test Cafe',
);

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, //
]);

Finder _key(String key) => find.byKey(ValueKey(key));

/// Types into a field of the card, scrolling it into view first. Waits for
/// the field's own animations (an error fading out, for instance).
Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(_key(key));
  await tester.enterText(_key(key), text);
  await settle(tester, 300);
}

/// Taps [finder] after scrolling it into view. A floating snackbar from an
/// earlier step would sit over the bottom of the page and take the tap, so
/// those are cleared first (as a user would wait for them to go).
Future<void> _tap(WidgetTester tester, Finder finder) async {
  ScaffoldMessenger.of(
    tester.element(find.byType(Scaffold).first),
  ).clearSnackBars();
  await settle(tester, 400);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// The title of a settings card, as opposed to the navigation label of the
/// same name.
Finder _cardTitle(String title) =>
    find.descendant(of: find.byType(SectionCard), matching: find.text(title));

/// The Payment Settings card on its own, in a scrolling page.
Future<PaymentSettingsController> _pumpCard(
  WidgetTester tester,
  PaymentSettingsRepository repository, {
  QrImagePicker? picker,
  bool load = true,
  StaffRole role = StaffRole.owner,
}) async {
  usePhoneScreen(tester);
  final controller = PaymentSettingsController(repository, FakeGuard(role));
  if (load) await tester.runAsync(controller.load);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        theme: AdminTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [PaymentSettingsCard(picker: picker ?? () async => null)],
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return controller;
}

void main() {
  setUpAll(loadBrandFonts);

  group('Payment Settings card', () {
    testWidgets('shows the saved details and that UPI is on', (tester) async {
      await _pumpCard(tester, FakePaymentSettingsRepository(stored: _ready));
      expect(find.text('Payment Settings'), findsOneWidget);
      expect(find.text('Enable UPI Payments'), findsOneWidget);
      expect(find.text('cafe@okhdfcbank'), findsOneWidget);
      expect(find.text('Test Cafe'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(_key('upi-enabled')).value, isTrue);
      expect(find.text('Active'), findsOneWidget);
      // Nothing is hidden behind a feature that is not there.
      expect(find.text('Manual verification'), findsOneWidget);
      expect(find.text('Automatic verification'), findsOneWidget);
      expect(find.text('Save payment settings'), findsOneWidget);
    });

    testWidgets('a fresh restaurant starts switched off with manual checks', (
      tester,
    ) async {
      await _pumpCard(tester, FakePaymentSettingsRepository());
      expect(tester.widget<SwitchListTile>(_key('upi-enabled')).value, isFalse);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('No QR image'), findsOneWidget);
    });

    testWidgets('a saved UPI ID no one can pay is flagged straight away', (
      tester,
    ) async {
      // Saved before the rule existed: Google Pay has no @okabi.
      final repository = FakePaymentSettingsRepository(
        stored: _ready.copyWith(upiId: 'cafe.owner@okabi'),
      );
      await _pumpCard(tester, repository);
      expect(find.textContaining('Did you mean @oksbi?'), findsOneWidget);
      // Nothing to scan until the ID is right.
      expect(_key('upi-id-check'), findsNothing);

      await _type(tester, 'upi-id', 'cafe.owner@oksbi');
      expect(find.textContaining('Did you mean'), findsNothing);
      expect(_key('upi-id-check'), findsOneWidget);
      expect(
        tester.widget<PlainQrCode>(find.byType(PlainQrCode)).payload,
        'upi://pay?pa=cafe.owner@oksbi&pn=Test%20Cafe&cu=INR',
      );
      // The owner is told why guests' apps don't open with the amount in.
      expect(_key('upi-id-check-copy'), findsOneWidget);
      await _tap(tester, _key('upi-save'));
      expect(repository.saves.single.upiId, 'cafe.owner@oksbi');
    });

    testWidgets('saves tidy details and confirms it', (tester) async {
      final repository = FakePaymentSettingsRepository();
      final controller = await _pumpCard(tester, repository);

      await _tap(tester, _key('upi-enabled'));
      await _type(tester, 'upi-id', '  Cafe@OkHDFCBank ');
      await _type(tester, 'upi-name', ' Spice Route ');
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(repository.saves, isEmpty);

      await _tap(tester, _key('upi-save'));
      expect(find.text('Payment settings saved'), findsOneWidget);
      final saved = repository.saves.single;
      expect(saved.enabled, isTrue);
      expect(saved.upiId, 'cafe@okhdfcbank');
      expect(saved.payeeName, 'Spice Route');
      expect(saved.verificationMode, UpiVerificationMode.manual);
      expect(controller.upi.isReady, isTrue);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    testWidgets('a malformed UPI ID is explained next to the field', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository();
      await _pumpCard(tester, repository);
      await _tap(tester, _key('upi-enabled'));
      await _type(tester, 'upi-id', 'not a upi id');
      await _type(tester, 'upi-name', 'Test Cafe');
      await _tap(tester, _key('upi-save'));

      expect(find.text('Enter a valid UPI ID, like name@bank.'), findsWidgets);
      expect(repository.saves, isEmpty);
      expect(find.text('Payment settings saved'), findsNothing);

      // Fixing it clears the message and saves.
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await _type(tester, 'upi-id', 'cafe@oksbi');
      expect(find.text('Enter a valid UPI ID, like name@bank.'), findsNothing);
      await _tap(tester, _key('upi-save'));
      expect(repository.saves.single.upiId, 'cafe@oksbi');
    });

    testWidgets('switching on needs both the ID and the name', (tester) async {
      final repository = FakePaymentSettingsRepository();
      await _pumpCard(tester, repository);
      await _tap(tester, _key('upi-enabled'));
      await _tap(tester, _key('upi-save'));
      expect(
        find.text("Enter the restaurant's UPI ID to switch UPI payments on."),
        findsWidgets,
      );
      expect(
        find.text('Enter the name guests will see when they pay.'),
        findsOneWidget,
      );
      expect(repository.saves, isEmpty);
    });

    testWidgets('a refusal from the server is shown, and nothing changes', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository(stored: _ready)
        ..saveError = const ValidationException('The server said no.');
      final controller = await _pumpCard(tester, repository);
      await _type(tester, 'upi-name', 'Renamed Cafe');
      await _tap(tester, _key('upi-save'));
      expect(find.text('The server said no.'), findsOneWidget);
      expect(controller.upi.payeeName, 'Test Cafe');
      expect(find.text('Unsaved changes'), findsOneWidget);

      // Trying again works.
      await _tap(tester, _key('upi-save'));
      expect(repository.saves.single.payeeName, 'Renamed Cafe');
    });

    testWidgets('can be disabled and enabled again with the details kept', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository(stored: _ready);
      final controller = await _pumpCard(tester, repository);

      await _tap(tester, _key('upi-enabled'));
      await _tap(tester, _key('upi-save'));
      expect(controller.upi.enabled, isFalse);
      expect(controller.upi.upiId, 'cafe@okhdfcbank');
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('cafe@okhdfcbank'), findsOneWidget);

      await _tap(tester, _key('upi-enabled'));
      await _tap(tester, _key('upi-save'));
      expect(controller.upi.isReady, isTrue);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets(
      'a QR picture can be uploaded, previewed, replaced and removed',
      (tester) async {
        final repository = FakePaymentSettingsRepository(stored: _ready);
        final controller = await _pumpCard(
          tester,
          repository,
          picker: () async => _png,
        );
        expect(find.text('Upload QR image'), findsOneWidget);
        expect(_key('upi-qr-remove'), findsNothing);

        await _tap(tester, _key('upi-qr-upload'));
        expect(repository.uploads, ['upi-qr.png']);
        // Previewed at once, but not live until saved.
        expect(find.byKey(ValueKey(repository.uploadUrl)), findsOneWidget);
        expect(
          find.text('Save to start showing this image to guests.'),
          findsOneWidget,
        );
        expect(controller.upi.hasQrImage, isFalse);
        expect(find.text('Replace'), findsOneWidget);

        await _tap(tester, _key('upi-save'));
        expect(repository.saves.single.qrImageUrl, repository.uploadUrl);
        expect(controller.upi.hasQrImage, isTrue);
        expect(_key('upi-qr-pending'), findsNothing);

        // Replace with another picture.
        repository.uploadUrl = 'https://x.test/uploads/upi/second.png';
        await _tap(tester, _key('upi-qr-upload'));
        expect(
          find.byKey(const ValueKey('https://x.test/uploads/upi/second.png')),
          findsOneWidget,
        );
        await _tap(tester, _key('upi-save'));
        expect(
          controller.upi.qrImageUrl,
          'https://x.test/uploads/upi/second.png',
        );

        // Remove it.
        await _tap(tester, _key('upi-qr-remove'));
        expect(
          find.text('Save to stop showing the image to guests.'),
          findsOneWidget,
        );
        await _tap(tester, _key('upi-save'));
        expect(controller.upi.hasQrImage, isFalse);
        expect(find.text('No QR image'), findsOneWidget);
      },
    );

    testWidgets('a cancelled picker changes nothing', (tester) async {
      final repository = FakePaymentSettingsRepository(stored: _ready);
      await _pumpCard(tester, repository);
      await _tap(tester, _key('upi-qr-upload'));
      expect(repository.uploads, isEmpty);
      expect(find.text('No QR image'), findsOneWidget);
    });

    testWidgets('a file that is not a picture is explained', (tester) async {
      final repository = FakePaymentSettingsRepository(stored: _ready);
      await _pumpCard(
        tester,
        repository,
        picker: () async => Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 1, 2]),
      );
      await _tap(tester, _key('upi-qr-upload'));
      // The server's answer.
      expect(
        find.text('That file is not a supported image. Use JPEG, PNG or WebP.'),
        findsOneWidget,
      );
      expect(repository.uploads, isEmpty);
      expect(find.text('No QR image'), findsOneWidget);
    });

    testWidgets('a failed upload says so and keeps the old picture', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository(
        stored: _ready.copyWith(qrImageUrl: 'https://x.test/uploads/upi/a.png'),
      );
      final controller = await _pumpCard(
        tester,
        _FailingUploads(repository),
        picker: () async => _png,
      );
      await _tap(tester, _key('upi-qr-upload'));
      expect(find.text('The server is busy.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('https://x.test/uploads/upi/a.png')),
        findsOneWidget,
      );
      expect(controller.upi.qrImageUrl, 'https://x.test/uploads/upi/a.png');
    });

    testWidgets('automatic verification explains it needs a provider', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository(stored: _ready);
      await _pumpCard(tester, repository);

      expect(find.text('Not set up'), findsOneWidget);
      expect(_key('upi-automatic-setup-note'), findsOneWidget);
      expect(
        find.text(PaymentSettingsController.automaticUnavailableMessage),
        findsOneWidget,
      );

      // Choosing it explains why not, and manual stays selected.
      await _tap(tester, _key('upi-mode-automatic'));
      expect(
        find.text(PaymentSettingsController.automaticUnavailableMessage),
        findsWidgets,
      );
      await _tap(tester, _key('upi-save'));
      expect(
        repository.saves.single.verificationMode,
        UpiVerificationMode.manual,
      );
    });

    testWidgets('automatic verification can be chosen once a provider exists', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository(
        stored: _ready,
        automaticAvailable: true,
      );
      final controller = await _pumpCard(tester, repository);
      expect(find.text('Not set up'), findsNothing);
      expect(_key('upi-automatic-setup-note'), findsNothing);
      await _tap(tester, _key('upi-mode-automatic'));
      await _tap(tester, _key('upi-save'));
      expect(controller.upi.verificationMode, UpiVerificationMode.automatic);
    });

    testWidgets('the offline demo explains that it needs the server', (
      tester,
    ) async {
      await _pumpCard(tester, const UnavailablePaymentSettingsRepository());
      expect(_key('upi-unavailable'), findsOneWidget);
      expect(find.textContaining('offline demo'), findsOneWidget);
      expect(_key('upi-save'), findsNothing);
      expect(_key('upi-id'), findsNothing);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final repository = FakePaymentSettingsRepository(stored: _ready)
        ..fetchError = const ApiException(
          0,
          'network',
          'Cannot reach the server.',
        );
      final controller = await _pumpCard(tester, repository, load: false);
      await settle(tester);
      expect(_key('upi-load-failed'), findsOneWidget);
      expect(find.text('Cannot reach the server.'), findsOneWidget);
      expect(_key('upi-save'), findsNothing);

      repository.fetchError = null;
      await _tap(tester, find.text('Try again'));
      expect(_key('upi-load-failed'), findsNothing);
      expect(find.text('cafe@okhdfcbank'), findsOneWidget);
      expect(controller.isLoaded, isTrue);
    });

    testWidgets('a newer copy from the server replaces an untouched form', (
      tester,
    ) async {
      final repository = FakePaymentSettingsRepository(stored: _ready);
      final controller = await _pumpCard(tester, repository);
      repository.stored = _ready.copyWith(payeeName: 'Changed Elsewhere');
      await tester.runAsync(controller.load);
      await settle(tester);
      expect(find.text('Changed Elsewhere'), findsOneWidget);
    });

    testWidgets('but never overwrites what is being typed', (tester) async {
      final repository = FakePaymentSettingsRepository(stored: _ready);
      final controller = await _pumpCard(tester, repository);
      await _type(tester, 'upi-name', 'My Edit');
      repository.stored = _ready.copyWith(payeeName: 'Changed Elsewhere');
      await tester.runAsync(controller.load);
      await settle(tester);
      expect(find.text('My Edit'), findsOneWidget);
      expect(find.text('Changed Elsewhere'), findsNothing);
      expect(find.text('Unsaved changes'), findsOneWidget);
    });

    for (final MapEntry(key: name, value: size) in _sizes.entries) {
      testWidgets('lays out on a $name at the largest text size', (
        tester,
      ) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString());
        try {
          final controller = PaymentSettingsController(
            FakePaymentSettingsRepository(
              stored: _ready.copyWith(
                qrImageUrl: 'https://x.test/uploads/upi/a.png',
              ),
            ),
            FakeGuard(StaffRole.owner),
          );
          await tester.runAsync(controller.load);
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: controller,
              child: MaterialApp(
                theme: AdminTheme.light(),
                builder: (context, child) => MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: child!,
                ),
                home: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [PaymentSettingsCard()],
                  ),
                ),
              ),
            ),
          );
          await settle(tester);
          await _type(tester, 'upi-id', 'x');
          await _tap(tester, _key('upi-save')); // field errors on screen too
          await tester.drag(find.byType(ListView), const Offset(0, -900));
          await settle(tester);
        } finally {
          FlutterError.onError = original;
        }
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }
  });

  group('Settings screen', () {
    testWidgets('puts Payment Settings below Taxes & charges', (tester) async {
      usePhoneScreen(tester);
      final deps = await _adminWith(
        paymentSettings: FakePaymentSettingsRepository(stored: _ready),
      );
      await deps.paymentSettings.load();
      await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      _openModule(tester, AdminModule.settings);
      await settle(tester, 900);

      final taxes = tester.getTopLeft(_cardTitle('Taxes & charges')).dy;
      final payment = tester.getTopLeft(_cardTitle('Payment Settings')).dy;
      final providers = tester.getTopLeft(_cardTitle('Payments')).dy;
      expect(taxes, lessThan(payment));
      expect(payment, lessThan(providers));
      expect(find.text('Enable UPI Payments'), findsOneWidget);
      // The page-wide save is still there for everything else.
      expect(find.text('Save settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the offline demo shows why UPI is not available', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await _adminWith();
      await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      _openModule(tester, AdminModule.settings);
      await settle(tester, 900);
      expect(_cardTitle('Payment Settings'), findsOneWidget);
      expect(_key('upi-unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('cashier confirms UPI payments', () {
    Invoice bill({DateTime? claimedAt, String reference = ''}) => Invoice(
      id: 'INV00001',
      billNumber: 'DQ-2026-00012',
      orderId: 'OD12345',
      tableNumber: 5,
      createdAt: DateTime.now(),
      lines: const [],
      amounts: const BillBreakdown(
        subtotal: Money(45000),
        tax: Money.zero,
        total: Money(45000),
        taxRateBasisPoints: 0,
      ),
      restaurant: const RestaurantSnapshot(name: 'Test Cafe'),
      payments: [
        PaymentTransaction(
          id: 'PAY000001',
          invoiceId: 'INV00001',
          orderId: 'OD12345',
          amount: const Money(45000),
          method: PaymentMethodType.upi,
          status: PaymentStatus.pending,
          provider: PaymentTransaction.upiDirectProvider,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          idempotencyKey: 'key-1',
          reference: reference,
          claimedAt: claimedAt,
        ),
      ],
    );

    /// Opens the bill as [email] and returns the server fake behind it.
    Future<(AdminDependencies, FakeUpiBackend)> openBill(
      WidgetTester tester,
      Invoice invoice, {
      String email = 'cashier@dineqr.demo',
    }) async {
      usePhoneScreen(tester);
      final server = FakeUpiBackend(invoice);
      final deps = await _adminWith(
        backend: server,
        invoices: [invoice],
        paymentSettings: FakePaymentSettingsRepository(stored: _ready),
      );
      await tester.runAsync(deps.billing.load);
      await tester.runAsync(deps.paymentSettings.load);
      await deps.admin.signIn(email, DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);
      _openModule(tester, AdminModule.bills);
      await settle(tester, 900);
      await _tap(tester, find.text('DQ-2026-00012').first);
      await settle(tester, 900);
      return (deps, server);
    }

    testWidgets(
      'a claimed payment waits for the cashier, and the bill is not paid',
      (tester) async {
        final (deps, _) = await openBill(
          tester,
          bill(claimedAt: DateTime.now(), reference: '412345678901'),
        );
        expect(find.text('UPI · Pending verification'), findsOneWidget);
        expect(find.textContaining('(from guest, unverified)'), findsOneWidget);
        expect(_key('confirm-PAY000001'), findsOneWidget);
        expect(find.text('Not received'), findsOneWidget);
        expect(deps.billing.byId('INV00001')!.status, InvoiceStatus.pending);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('confirming needs the bank reference and a ticked check', (
      tester,
    ) async {
      final (deps, server) = await openBill(
        tester,
        bill(claimedAt: DateTime.now(), reference: '412345678901'),
      );
      await _tap(tester, _key('confirm-PAY000001'));
      expect(find.text('Confirm UPI payment'), findsOneWidget);
      expect(find.textContaining('cafe@okhdfcbank'), findsOneWidget);
      // The guest's own note is only a starting point.
      expect(
        tester.widget<TextField>(_key('upi-reference')).controller!.text,
        '412345678901',
      );

      // Not ticked: nothing is sent.
      await _tap(tester, _key('upi-confirm'));
      expect(
        find.text('Tick the box once you have checked the credit.'),
        findsOneWidget,
      );
      expect(server.calls.where((c) => c.startsWith('verify')), isEmpty);

      // A malformed reference is refused.
      await _tap(tester, _key('upi-seen'));
      await tester.enterText(_key('upi-reference'), '12');
      await _tap(tester, _key('upi-confirm'));
      expect(find.text(UpiReference.rule), findsOneWidget);
      expect(server.calls.where((c) => c.startsWith('verify')), isEmpty);

      // Typed in any case; it is recorded the way banks print it.
      await tester.enterText(_key('upi-reference'), 'utr987654321');
      await _tap(tester, _key('upi-confirm'));
      expect(server.calls, contains('verify:PAY000001:UTR987654321'));

      final paid = deps.billing.byId('INV00001')!;
      expect(paid.status, InvoiceStatus.paid);
      expect(paid.outstanding, Money.zero);
      expect(find.text('Payment of ₹450 confirmed'), findsOneWidget);
      expect(_key('confirm-PAY000001'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('backing out of the dialog sends nothing', (tester) async {
      final (deps, server) = await openBill(
        tester,
        bill(claimedAt: DateTime.now()),
      );
      await _tap(tester, _key('confirm-PAY000001'));
      await _tap(tester, find.text('Back'));
      expect(server.calls.where((c) => c.startsWith('verify')), isEmpty);
      expect(deps.billing.byId('INV00001')!.status, InvoiceStatus.pending);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a payment that never arrived can be rejected with a reason', (
      tester,
    ) async {
      final (deps, server) = await openBill(
        tester,
        bill(claimedAt: DateTime.now()),
      );
      await _tap(tester, find.text('Not received'));
      expect(find.text('Payment not received?'), findsOneWidget);
      await tester.enterText(_key('upi-reject-reason'), ' Not in statement ');
      await _tap(tester, _key('upi-reject-confirm'));

      expect(server.calls, contains('reject:PAY000001:Not in statement'));
      final settled = deps.billing.byId('INV00001')!;
      expect(settled.status, InvoiceStatus.failed);
      expect(settled.amountPaid, Money.zero);
      expect(settled.payableNow, const Money(45000));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'a payment the guest never claimed is cancelled, not rejected',
      (tester) async {
        final (deps, server) = await openBill(tester, bill());
        expect(find.text('UPI · Payment started'), findsOneWidget);
        expect(find.text('Not received'), findsNothing);
        await _tap(tester, _key('reject-PAY000001'));
        expect(find.text('Cancel this UPI payment?'), findsOneWidget);
        await _tap(tester, find.text('Cancel payment'));
        expect(server.calls, contains('cancel:PAY000001'));
        expect(deps.billing.byId('INV00001')!.status, InvoiceStatus.unpaid);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('a role that cannot take payments cannot confirm them', (
      tester,
    ) async {
      final (deps, server) = await openBill(
        tester,
        bill(claimedAt: DateTime.now()),
        email: 'accounts@dineqr.demo',
      );
      // Accountants can read bills, so they see the payment...
      expect(find.text('UPI · Pending verification'), findsOneWidget);
      // ...but not the buttons that settle it.
      expect(_key('confirm-PAY000001'), findsNothing);
      expect(find.text('Not received'), findsNothing);
      await expectLater(
        deps.billing.verifyUpiPayment('PAY000001', reference: 'UTR987654321'),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(server.calls.where((c) => c.startsWith('verify')), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final MapEntry(key: name, value: size) in _sizes.entries) {
      testWidgets('the confirm dialog fits a $name at large text', (
        tester,
      ) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.exceptionAsString());
        try {
          final invoice = bill(
            claimedAt: DateTime.now(),
            reference: '412345678901',
          );
          final server = FakeUpiBackend(invoice);
          final deps = await _adminWith(
            backend: server,
            invoices: [invoice],
            paymentSettings: FakePaymentSettingsRepository(stored: _ready),
          );
          await tester.runAsync(deps.billing.load);
          await tester.runAsync(deps.paymentSettings.load);
          await deps.admin.signIn(
            'cashier@dineqr.demo',
            DemoCredentials.password,
          );
          await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
          await settle(tester, 900);
          await settle(tester, 900);
          _openModule(tester, AdminModule.bills);
          await settle(tester, 900);
          await _tap(tester, find.text('DQ-2026-00012').first);
          await settle(tester, 900);
          await _tap(tester, _key('confirm-PAY000001'));
          await _tap(tester, _key('upi-confirm')); // errors showing as well
        } finally {
          FlutterError.onError = original;
        }
        expect(errors, isEmpty, reason: errors.join('\n'));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}

/// Screen sizes the layout checks run at (logical pixels).
const _sizes = {'small phone': Size(360, 760), 'tablet': Size(1280, 800)};

/// Admin dependencies in the offline-demo shell with the given server fakes
/// swapped in for the UPI parts.
Future<AdminDependencies> _adminWith({
  FakeUpiBackend? backend,
  List<Invoice> invoices = const [],
  PaymentSettingsRepository? paymentSettings,
}) => AdminDependencies.create(
  store: MemoryStore(),
  config: const AppConfig(),
  billingRepository: backend == null
      ? null
      : LocalBillingRepository(MemoryStore(), seed: invoices),
  billingBackend: backend,
  paymentSettingsRepository: paymentSettings,
  menuLatency: Duration.zero,
  orderLatency: Duration.zero,
  paymentTime: const Duration(milliseconds: 300),
  seedDemoData: false,
);

void _openModule(WidgetTester tester, AdminModule module) {
  final shell = Provider.of<AdminShellController>(
    tester.element(find.byType(Scaffold).first),
    listen: false,
  );
  shell.open(module);
}

/// Uploads fail with an API error; everything else works.
class _FailingUploads implements PaymentSettingsRepository, UpiQrUploader {
  _FailingUploads(this._inner);

  final FakePaymentSettingsRepository _inner;

  @override
  bool get isAvailable => true;

  @override
  Future<PaymentSettingsSnapshot> fetch() => _inner.fetch();

  @override
  Future<PaymentSettingsSnapshot> save(UpiSettings settings) =>
      _inner.save(settings);

  @override
  Future<String> uploadUpiQr({
    required List<int> bytes,
    required String filename,
  }) async => throw const ApiException(
    503,
    'storageUnavailable',
    'The server is busy.',
  );
}
