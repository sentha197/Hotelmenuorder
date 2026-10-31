import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/modules/dashboard/dashboard_screen.dart';
import 'package:dineqr_admin/modules/settings/wifi_restriction_card.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

/// Stands in for the server: what it stores, and what it sees for this
/// device.
class _Server implements NetworkAccessSettingsRepository {
  _Server(this.you);

  NetworkCheck you;
  NetworkAccessSettings stored = const NetworkAccessSettings();
  final saves = <NetworkAccessSettings>[];

  @override
  bool get isAvailable => true;

  NetworkAccessSettings _view() => NetworkAccessSettings(
    enabled: stored.enabled,
    ssid: stored.ssid,
    restrictTakeaway: stored.restrictTakeaway,
    networks: stored.networks,
    you: you,
  );

  @override
  Future<NetworkAccessSettings> fetch() async => _view();

  @override
  Future<NetworkAccessSettings> save(NetworkAccessSettings settings) async {
    saves.add(settings);
    stored = settings;
    return _view();
  }
}

Future<void> _openSettings(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(360, 760) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final deps = await createAdminDependencies(networkSettingsRepository: server);
  await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
  await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
  await settle(tester, 800);
  Provider.of<AdminShellController>(
    tester.element(find.byType(DashboardScreen)),
    listen: false,
  ).open(AdminModule.settings);
  await settle(tester);
  final card = find.byType(WifiRestrictionCard);
  await Scrollable.ensureVisible(tester.element(card));
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets('the owner adds the restaurant network and switches it on', (
    tester,
  ) async {
    final server = _Server(
      const NetworkCheck(
        address: '203.0.113.10',
        source: 'remote address',
        matches: false,
        suggestedEntry: '203.0.113.10',
      ),
    );
    await _openSettings(tester, server);

    expect(find.text('This device: 203.0.113.10'), findsOneWidget);
    expect(find.text('Not on an authorised network.'), findsOneWidget);

    await _tap(tester, find.text('Add this network (203.0.113.10)'));
    expect(find.text('203.0.113.10'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Wi-Fi name shown to guests (optional)'),
      'DineQR Guest',
    );
    await _tap(tester, find.text('Require the restaurant Wi-Fi'));
    // The server now sees this device on the listed network.
    server.you = const NetworkCheck(
      address: '203.0.113.10',
      source: 'remote address',
      matches: true,
      matchedBy: '203.0.113.10/32',
    );
    await _tap(tester, find.text('Save Wi-Fi restriction'));
    // Not on a listed network when saving: asked to confirm.
    await tester.tap(find.text('Switch on'));
    await settle(tester);

    final saved = server.saves.single;
    expect(saved.enabled, isTrue);
    expect(saved.ssid, 'DineQR Guest');
    expect(saved.restrictTakeaway, isFalse);
    expect(saved.networks.single.value, '203.0.113.10');
    expect(
      find.text('On an authorised network (203.0.113.10/32).'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a deployment that hides guest addresses is called out', (
    tester,
  ) async {
    final server = _Server(
      const NetworkCheck(
        address: '172.70.1.2',
        source: 'remote address',
        matches: false,
        consistent: false,
        headers: {'CF-Connecting-IP': '203.0.113.10'},
        suggestedEntry: '172.70.1.2',
      ),
    );
    await _openSettings(tester, server);

    expect(
      find.textContaining('A proxy header names a different address'),
      findsOneWidget,
    );
    // Never offered as "this network": it is the proxy's address.
    expect(find.textContaining('Add this network'), findsNothing);

    // Switching on with no network is refused before it reaches the server.
    await _tap(tester, find.text('Require the restaurant Wi-Fi'));
    await _tap(tester, find.text('Save Wi-Fi restriction'));
    await tester.tap(find.text('Switch on'));
    await settle(tester);
    expect(server.saves, isEmpty);
    expect(find.textContaining("Add the restaurant's network"), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
