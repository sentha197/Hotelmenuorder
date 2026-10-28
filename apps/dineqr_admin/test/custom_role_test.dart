import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/app/dependencies.dart';
import 'package:dineqr_admin/state/staff_controller.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('typed role names', () {
    test('standard roles are recognised by label or key', () {
      for (final typed in ['Manager', ' kitchen STAFF ', 'kitchen']) {
        expect(StaffRole.fromText(typed)?.role, isNotNull, reason: typed);
        expect(StaffRole.fromText(typed)?.title, isNull, reason: typed);
      }
      expect(StaffRole.fromText('service staff')?.role, StaffRole.waiter);
      expect(StaffRole.fromText('Waiter')?.role, StaffRole.waiter);
      expect(StaffRole.fromText('ACCOUNTANT')?.role, StaffRole.accountant);
    });

    test('any other name is a custom role with that name', () {
      final officer = StaffRole.fromText('  Officer ')!;
      expect(officer.role, StaffRole.custom);
      expect(officer.title, 'Officer');
      // Even the words "custom role" are only a name.
      expect(StaffRole.fromText('Custom role')?.title, 'Custom role');
    });

    test('a name must be 2 to 30 characters', () {
      expect(StaffRole.fromText(''), isNull);
      expect(StaffRole.fromText('  A '), isNull);
      expect(StaffRole.fromText('AB')?.title, 'AB');
      expect(StaffRole.fromText('x' * 30)?.title, 'x' * 30);
      expect(StaffRole.fromText('x' * 31), isNull);
    });

    test('a custom role starts with nothing', () {
      expect(StaffRole.custom.permissions, isEmpty);
    });
  });

  group('an account with a custom role', () {
    final officer = staffWith(StaffRole.custom).copyWith(
      roleTitle: 'Officer',
      customPermissions: {Permission.viewOrders},
    );

    test('is called by its own name', () {
      expect(officer.roleLabel, 'Officer');
      expect(staffWith(StaffRole.custom).roleLabel, 'Custom role');
      expect(staffWith(StaffRole.cashier).roleLabel, 'Cashier');
      expect(officer.can(Permission.viewOrders), isTrue);
      expect(officer.can(Permission.viewBills), isFalse);
    });

    test('is kept when saved and read back, and comes from the server', () {
      final restored = StaffAccount.fromJson(officer.toJson());
      expect(restored.roleTitle, 'Officer');
      expect(restored.customPermissions, {Permission.viewOrders});

      final fromApi = staffFromApi({
        'id': '9',
        'name': 'Adolf',
        'email': 'adolf@x.test',
        'role': 'custom',
        'roleTitle': 'Officer',
        'active': true,
        'createdAt': '2026-10-29T00:00:00Z',
        'permissions': ['viewOrders'],
        'customAccess': true,
      });
      expect(fromApi.role, StaffRole.custom);
      expect(fromApi.roleLabel, 'Officer');
      expect(fromApi.permissions, {Permission.viewOrders});
    });

    test('renaming keeps its access; another role replaces both', () {
      final renamed = officer.copyWith(roleTitle: 'Inspector');
      expect(renamed.roleLabel, 'Inspector');
      expect(renamed.customPermissions, {Permission.viewOrders});

      final cashier = officer.copyWith(role: StaffRole.cashier);
      expect(cashier.roleTitle, isNull);
      expect(cashier.roleLabel, 'Cashier');
      expect(cashier.hasCustomAccess, isFalse);
    });
  });

  group('staff controller', () {
    late LocalStaffRepository repository;
    late FakeGuard guard;
    late StaffController staff;

    setUp(() async {
      final now = DateTime.utc(2026, 10, 29);
      repository = LocalStaffRepository(
        MemoryStore(),
        seed: () => DemoCredentials.seedAccounts(now),
      );
      guard = FakeGuard();
      staff = StaffController(
        repository,
        guard,
        AuditLog(repository)..guard = guard,
      );
      await staff.load();
      guard.actor = staff.staff.firstWhere((a) => a.role == StaffRole.owner);
    });

    Future<StaffAccount> addOfficer([String title = ' Officer ']) =>
        staff.addStaff(
          name: 'Adolf',
          email: 'adolf@dineqr.demo',
          role: StaffRole.custom,
          roleTitle: title,
          password: 'Strong2026',
        );

    test('can be added under any name and starts with no access', () async {
      final adolf = await addOfficer();
      expect(adolf.roleLabel, 'Officer');
      expect(adolf.permissions, isEmpty);
      expect(adolf.can(Permission.viewOrders), isFalse);
      expect(
        (await repository.fetchAudit()).first.summary,
        'Added Adolf as Officer',
      );
    });

    test('needs a readable name', () async {
      for (final title in ['', ' ', 'A', 'x' * 31]) {
        await expectLater(
          addOfficer(title),
          throwsA(isA<ValidationException>()),
          reason: '"$title"',
        );
      }
    });

    test('a name only means something for a custom role', () async {
      final cashier = await staff.addStaff(
        name: 'Cash',
        email: 'cash@dineqr.demo',
        role: StaffRole.cashier,
        roleTitle: 'Officer',
        password: 'Strong2026',
      );
      expect(cashier.roleTitle, isNull);
      expect(cashier.roleLabel, 'Cashier');
    });

    test('can be renamed without losing granted access', () async {
      final adolf = await addOfficer();
      await staff.changeAccess(adolf.id, {Permission.viewOrders});

      await staff.changeRole(
        adolf.id,
        StaffRole.custom,
        roleTitle: 'Inspector',
      );

      final renamed = staff.byId(adolf.id)!;
      expect(renamed.roleLabel, 'Inspector');
      expect(renamed.customPermissions, {Permission.viewOrders});
      expect(
        (await repository.fetchAudit()).first.summary,
        'Adolf: Officer → Inspector',
      );
    });

    test('moving to or from a standard role starts from that role', () async {
      final adolf = await addOfficer();
      await staff.changeAccess(adolf.id, {Permission.viewOrders});

      await staff.changeRole(adolf.id, StaffRole.cashier);
      expect(staff.byId(adolf.id)!.roleLabel, 'Cashier');
      expect(staff.byId(adolf.id)!.permissions, StaffRole.cashier.permissions);

      await staff.changeRole(adolf.id, StaffRole.custom, roleTitle: 'Clerk');
      expect(staff.byId(adolf.id)!.roleLabel, 'Clerk');
      expect(staff.byId(adolf.id)!.permissions, isEmpty);
    });

    test('changing nothing is not recorded', () async {
      final adolf = await addOfficer();
      final before = (await repository.fetchAudit()).length;
      await staff.changeRole(adolf.id, StaffRole.custom, roleTitle: 'Officer');
      expect((await repository.fetchAudit()).length, before);
    });
  });

  group('workspace for an account with little or no access', () {
    Future<void> signInAs(
      WidgetTester tester,
      Set<Permission> permissions,
    ) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies(seedDemoData: true);
      await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
      final adolf = (await tester.runAsync(
        () => deps.staff.addStaff(
          name: 'Adolf',
          email: 'adolf@dineqr.demo',
          role: StaffRole.custom,
          roleTitle: 'Officer',
          password: 'Strong2026',
        ),
      ))!;
      if (permissions.isNotEmpty) {
        await tester.runAsync(
          () => deps.staff.changeAccess(adolf.id, permissions),
        );
      }
      await tester.runAsync(deps.admin.signOut);
      await deps.admin.signIn('adolf@dineqr.demo', 'Strong2026');
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);
    }

    testWidgets('nothing switched on shows a message, not a broken bar', (
      tester,
    ) async {
      await signInAs(tester, {});
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.textContaining('Ask the owner'), findsOneWidget);
      expect(find.text('Officer workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('one screen needs no navigation bar', (tester) async {
      await signInAs(tester, {Permission.viewOrders});
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.textContaining('Ask the owner'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('two screens get the bar again', (tester) async {
      await signInAs(tester, {Permission.viewOrders, Permission.viewBills});
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('adding staff with a name of their own', () {
    Future<AdminDependencies> openStaff(WidgetTester tester) async {
      usePhoneScreen(tester);
      final deps = await createAdminDependencies(seedDemoData: true);
      await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);
      await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
      await settle(tester, 900);
      await settle(tester, 900);
      await tester.tap(find.text('More'));
      await settle(tester, 600);
      await tester.tap(find.text('Staff').last);
      await settle(tester, 900);
      await tester.tap(find.text('Add staff'));
      await settle(tester, 600);
      return deps;
    }

    Future<void> fill(WidgetTester tester, String role) async {
      Future<void> type(String label, String text) =>
          tester.enterText(find.widgetWithText(TextField, label), text);
      await type('Full name', 'Adolf');
      await type('Email', 'adolf@gmail.com');
      await type('Role', role);
      await type('Temporary password', 'adolf@123');
    }

    testWidgets('"Officer" is accepted, then its access is asked for', (
      tester,
    ) async {
      final deps = await openStaff(tester);
      await fill(tester, 'Officer');
      await tester.tap(find.text('Add').last);
      await settle(tester, 600);
      await settle(tester, 600);

      final adolf = deps.staff.staff.firstWhere((s) => s.name == 'Adolf');
      expect(adolf.role, StaffRole.custom);
      expect(adolf.roleLabel, 'Officer');
      expect(find.text('Access for Adolf'), findsOneWidget);

      // Switch one thing on and save.
      final tile = find.byKey(const ValueKey('access-viewOrders'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester, 600);
      await settle(tester, 600);
      expect(deps.staff.byId(adolf.id)!.permissions, {Permission.viewOrders});
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a standard role is still recognised by name', (tester) async {
      final deps = await openStaff(tester);
      await fill(tester, 'cashier');
      await tester.tap(find.text('Add').last);
      await settle(tester, 600);
      await settle(tester, 600);

      final adolf = deps.staff.staff.firstWhere((s) => s.name == 'Adolf');
      expect(adolf.role, StaffRole.cashier);
      expect(find.text('Access for Adolf'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a one-letter role is refused with a reason', (tester) async {
      final deps = await openStaff(tester);
      await fill(tester, 'X');
      await tester.tap(find.text('Add').last);
      await settle(tester, 300);

      expect(find.textContaining('2 to 30 characters'), findsOneWidget);
      expect(deps.staff.staff.where((s) => s.name == 'Adolf'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
