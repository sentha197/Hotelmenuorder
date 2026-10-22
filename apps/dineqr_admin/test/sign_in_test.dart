import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('staff sign-in screen', () {
    testWidgets(
      'validates input, rejects bad passwords and opens the dashboard',
      (tester) async {
        usePhoneScreen(tester);
        final deps = await createAdminDependencies();
        await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
        await settle(tester, 800);

        expect(find.text('Staff sign in'), findsOneWidget);
        expect(find.text('Demo accounts (offline demo only)'), findsOneWidget);

        await tester.ensureVisible(find.text('Sign in'));
        await tester.tap(find.text('Sign in'));
        await settle(tester, 300);
        expect(find.text('Enter your email.'), findsOneWidget);
        expect(find.text('Enter your password.'), findsOneWidget);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'owner@dineqr.demo');
        await tester.enterText(fields.at(1), 'not-the-password1');
        await tester.tap(find.text('Sign in'));
        await settle(tester, 600);
        expect(find.text(AuthError.invalidCredentials.message), findsOneWidget);
        expect(deps.admin.isSignedIn, isFalse);

        await tester.enterText(fields.at(1), DemoCredentials.password);
        await tester.tap(find.text('Sign in'));
        await settle(tester, 800);
        await settle(tester, 800);
        expect(deps.admin.isSignedIn, isTrue);
        expect(deps.admin.actor!.name, 'Demo Owner');
        expect(find.text('Staff sign in'), findsNothing);
        expect(find.text('Dashboard'), findsWidgets);

        // Dispose the shell so its periodic session check stops.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('the demo accounts panel fills in the sign-in', (tester) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 800);

      await tester.ensureVisible(find.text('Owner'));
      await tester.tap(find.text('Owner'));
      await settle(tester, 400);
      await tester.tap(find.text('Sign in'));
      await settle(tester, 900);
      await settle(tester, 900);

      expect(deps.admin.isSignedIn, isTrue);
      expect(deps.admin.actor!.email, 'owner@dineqr.demo');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a kitchen account only sees its own modules', (tester) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      await deps.admin.signIn('kitchen@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 800);
      await settle(tester, 800);

      expect(find.text('Kitchen'), findsWidgets);
      expect(find.text('Bills'), findsNothing);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Settings'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('signing out returns to the sign-in screen', (tester) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies();
      await deps.admin.signIn('manager@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 800);
      await settle(tester, 800);
      expect(find.text('Staff sign in'), findsNothing);

      await deps.admin.signOut(reason: 'Signed out for the test.');
      await settle(tester, 800);
      expect(find.text('Staff sign in'), findsOneWidget);
      expect(find.text('Signed out for the test.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('without demo mode there are no demo accounts to use', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies(demoMode: false);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 800);

      expect(find.text('Staff sign in'), findsOneWidget);
      expect(find.text('Demo accounts (offline demo only)'), findsNothing);
      expect(deps.admin.isDemo, isFalse);
      // Without a configured sign-in service, sign-in is refused outright.
      await expectLater(
        deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password),
        throwsA(isA<AuthException>()),
      );
      expect(deps.admin.isSignedIn, isFalse);
    });
  });
}
