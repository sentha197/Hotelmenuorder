import 'package:dineqr_customer/app/app.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart'
    show createDependencies, scanDemoTable, settle, usePhoneScreen;

void main() {
  testWidgets('splash reaches the scanner with reduced motion enabled', (
    tester,
  ) async {
    usePhoneScreen(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    expect(find.byType(DineQrMark), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2700));
    await settle(tester, 700);
    expect(find.text('Scan QR Code'), findsOneWidget);
  });

  testWidgets('home settles: no animation keeps running without a purpose', (
    tester,
  ) async {
    usePhoneScreen(tester);
    final deps = await createDependencies();
    await tester.pumpWidget(DineQrApp(dependencies: deps));
    await scanDemoTable(tester, 'Table 05');
    await tester.tap(find.text('Start Ordering'));
    await settle(tester, 900);
    expect(find.text('Popular Dishes'), findsOneWidget);
    // Would time out if a loader, shimmer or pulse were left running.
    await tester.pumpAndSettle();
    expect(find.byType(BrandShimmer), findsNothing);
  });
}
