import 'package:dineqr_admin/modules/staff/access_dialog.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_admin/state/staff_controller.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('custom access on an account', () {
    test('uses the role until the owner customises it', () {
      final cashier = staffWith(StaffRole.cashier);
      expect(cashier.hasCustomAccess, isFalse);
      expect(cashier.permissions, StaffRole.cashier.permissions);
      expect(cashier.can(Permission.viewAuditLog), isFalse);

      final more = cashier.copyWith(
        customPermissions: {
          ...StaffRole.cashier.permissions,
          Permission.viewAuditLog,
        },
      );
      expect(more.hasCustomAccess, isTrue);
      expect(more.can(Permission.viewAuditLog), isTrue);
      expect(more.can(Permission.collectPayments), isTrue);

      final less = cashier.copyWith(customPermissions: {Permission.viewBills});
      expect(less.can(Permission.viewBills), isTrue);
      expect(less.can(Permission.collectPayments), isFalse);
    });

    test('a deactivated account can do nothing, whatever it was given', () {
      final account = staffWith(
        StaffRole.cashier,
      ).copyWith(customPermissions: {Permission.viewBills}, isActive: false);
      expect(account.can(Permission.viewBills), isFalse);
    });

    test('a new role drops custom access; the same role keeps it', () {
      final custom = staffWith(
        StaffRole.waiter,
      ).copyWith(customPermissions: {Permission.viewOrders});
      expect(custom.copyWith(name: 'Renamed').hasCustomAccess, isTrue);
      expect(custom.copyWith(role: StaffRole.waiter).hasCustomAccess, isTrue);
      final cashier = custom.copyWith(role: StaffRole.cashier);
      expect(cashier.hasCustomAccess, isFalse);
      expect(cashier.permissions, StaffRole.cashier.permissions);
      expect(
        custom.copyWith(clearCustomPermissions: true).hasCustomAccess,
        isFalse,
      );
    });

    test('owners always have everything', () {
      final owner = staffWith(
        StaffRole.owner,
      ).copyWith(customPermissions: {Permission.viewOrders});
      expect(owner.hasCustomAccess, isFalse);
      expect(owner.permissions, Permission.values.toSet());
    });

    test('is kept when saved and read back', () {
      final account = staffWith(StaffRole.kitchen).copyWith(
        customPermissions: {Permission.viewOrders, Permission.viewAuditLog},
      );
      final restored = StaffAccount.fromJson(account.toJson());
      expect(restored.customPermissions, account.customPermissions);
      expect(
        StaffAccount.fromJson(
          staffWith(StaffRole.kitchen).toJson(),
        ).hasCustomAccess,
        isFalse,
      );
    });

    test('comes from the server as the permissions it allows', () {
      Map<String, dynamic> json({required bool custom}) => {
        'id': '7',
        'name': 'Asha',
        'email': 'asha@x.test',
        'role': 'kitchen',
        'active': true,
        'createdAt': '2026-10-28T00:00:00Z',
        'permissions': ['viewOrders', 'viewAuditLog', 'notAPermissionYet'],
        'customAccess': custom,
      };
      expect(staffFromApi(json(custom: false)).hasCustomAccess, isFalse);
      expect(staffFromApi(json(custom: true)).customPermissions, {
        Permission.viewOrders,
        Permission.viewAuditLog,
      });
    });
  });

  group('permissions that belong together', () {
    test('every built-in role already has what its actions need', () {
      for (final role in StaffRole.values) {
        for (final p in role.permissions) {
          final need = p.requires;
          if (need != null) {
            expect(role.can(need), isTrue, reason: '${role.name}: ${p.name}');
          }
        }
      }
    });

    test('the access editor lists every permission exactly once', () {
      final listed = [for (final (_, ps) in accessGroups) ...ps];
      expect(listed.length, Permission.values.length);
      expect(listed.toSet(), Permission.values.toSet());
    });
  });

  test('navigation follows custom access', () {
    expect(
      AdminModule.forRole(StaffRole.kitchen),
      isNot(contains(AdminModule.bills)),
    );
    final modules = AdminModule.forRole(
      StaffRole.kitchen,
      permissions: {...StaffRole.kitchen.permissions, Permission.viewBills},
    );
    expect(modules, contains(AdminModule.bills));
    expect(modules.first, AdminModule.kitchen);
    // Taking the kitchen away removes its tab.
    expect(
      AdminModule.forRole(
        StaffRole.kitchen,
        permissions: {Permission.viewOrders},
      ),
      [AdminModule.orders],
    );
  });

  group('changing access', () {
    late LocalStaffRepository repository;
    late FakeGuard guard;
    late StaffController staff;
    late StaffAccount cashier;

    setUp(() async {
      final store = MemoryStore();
      final now = DateTime.utc(2026, 10, 28);
      repository = LocalStaffRepository(
        store,
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
      cashier = staff.staff.firstWhere((a) => a.role == StaffRole.cashier);
    });

    test('the owner gives and takes away access, and it is recorded', () async {
      final chosen = {...StaffRole.cashier.permissions, Permission.viewAuditLog}
        ..remove(Permission.reconcilePayments);
      await staff.changeAccess(cashier.id, chosen);

      final saved = staff.byId(cashier.id)!;
      expect(saved.hasCustomAccess, isTrue);
      expect(saved.can(Permission.viewAuditLog), isTrue);
      expect(saved.can(Permission.reconcilePayments), isFalse);
      // It is stored, not only held in memory.
      final reloaded = (await repository.fetchStaff()).firstWhere(
        (a) => a.id == cashier.id,
      );
      expect(reloaded.customPermissions, chosen);

      final events = await repository.fetchAudit();
      expect(events.map((e) => e.action), contains('staff.access'));
      expect(
        events.firstWhere((e) => e.action == 'staff.access').summary,
        contains('+1 / −1 vs Cashier'),
      );
    });

    test('choosing the role\'s own permissions, or null, resets it', () async {
      await staff.changeAccess(cashier.id, {Permission.viewBills});
      expect(staff.byId(cashier.id)!.hasCustomAccess, isTrue);

      await staff.changeAccess(cashier.id, StaffRole.cashier.permissions);
      expect(staff.byId(cashier.id)!.hasCustomAccess, isFalse);

      await staff.changeAccess(cashier.id, {Permission.viewBills});
      await staff.changeAccess(cashier.id, null);
      expect(staff.byId(cashier.id)!.hasCustomAccess, isFalse);
    });

    test('a change that changes nothing is not recorded', () async {
      await staff.changeAccess(cashier.id, StaffRole.cashier.permissions);
      expect(
        (await repository.fetchAudit()).where(
          (e) => e.action == 'staff.access',
        ),
        isEmpty,
      );
    });

    test('moving to another role starts from that role', () async {
      await staff.changeAccess(cashier.id, {Permission.viewBills});
      await staff.changeRole(cashier.id, StaffRole.waiter);
      final moved = staff.byId(cashier.id)!;
      expect(moved.hasCustomAccess, isFalse);
      expect(moved.permissions, StaffRole.waiter.permissions);
    });

    test('only an owner, and never for themselves or another owner', () async {
      final owner = guard.actor!;
      await expectLater(
        staff.changeAccess(owner.id, {Permission.viewOrders}),
        throwsA(isA<ValidationException>()),
      );
      final otherOwner = await staff.addStaff(
        name: 'Second Owner',
        email: 'second@dineqr.demo',
        role: StaffRole.owner,
        password: 'Strong2026',
      );
      await expectLater(
        staff.changeAccess(otherOwner.id, {Permission.viewOrders}),
        throwsA(isA<ValidationException>()),
      );

      // A manager who was given "manage staff" is still not an owner.
      guard.actor = staffWith(StaffRole.manager).copyWith(
        customPermissions: {
          ...StaffRole.manager.permissions,
          Permission.manageStaff,
        },
      );
      await expectLater(
        staff.changeAccess(cashier.id, {Permission.viewOrders}),
        throwsA(isA<ValidationException>()),
      );
      // And without "manage staff" they cannot even ask.
      guard.actor = staffWith(StaffRole.manager);
      await expectLater(
        staff.changeAccess(cashier.id, {Permission.viewOrders}),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(staff.byId(cashier.id)!.hasCustomAccess, isFalse);
    });
  });

  group('access dialog', () {
    Future<Set<Permission>?> openAndSave(
      WidgetTester tester,
      StaffAccount account,
      Future<void> Function() edit, {
      String button = 'Save',
    }) async {
      Set<Permission>? result;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showAccessDialog(context, account);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await edit();
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      return result;
    }

    Future<void> toggle(WidgetTester tester, Permission permission) async {
      final tile = find.byKey(ValueKey('access-${permission.name}'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    bool isOn(WidgetTester tester, Permission permission) => tester
        .widget<SwitchListTile>(
          find.byKey(ValueKey('access-${permission.name}')),
        )
        .value;

    testWidgets('starts from the role and returns what was chosen', (
      tester,
    ) async {
      final kitchen = staffWith(StaffRole.kitchen);
      final saved = await openAndSave(tester, kitchen, () async {
        expect(find.text('Access for Test Kitchen staff'), findsOneWidget);
        expect(isOn(tester, Permission.manageKitchen), isTrue);
        expect(isOn(tester, Permission.viewAuditLog), isFalse);
        await toggle(tester, Permission.viewAuditLog);
        await toggle(tester, Permission.viewMenu);
      });
      expect(saved, {
        Permission.viewOrders,
        Permission.manageKitchen,
        Permission.viewAuditLog,
      });
    });

    testWidgets('an action switches on the screen it needs, and off with it', (
      tester,
    ) async {
      final kitchen = staffWith(StaffRole.kitchen);
      final saved = await openAndSave(tester, kitchen, () async {
        expect(isOn(tester, Permission.viewBills), isFalse);
        await toggle(tester, Permission.collectPayments);
        expect(isOn(tester, Permission.viewBills), isTrue);
        expect(isOn(tester, Permission.collectPayments), isTrue);

        await toggle(tester, Permission.issueRefunds);
        await toggle(tester, Permission.viewBills);
        expect(isOn(tester, Permission.collectPayments), isFalse);
        expect(isOn(tester, Permission.issueRefunds), isFalse);
      });
      expect(saved, StaffRole.kitchen.permissions);
    });

    testWidgets('reset puts the role\'s own permissions back', (tester) async {
      final waiter = staffWith(StaffRole.waiter).copyWith(
        customPermissions: {Permission.viewOrders, Permission.viewAuditLog},
      );
      final saved = await openAndSave(tester, waiter, () async {
        expect(isOn(tester, Permission.viewAuditLog), isTrue);
        expect(isOn(tester, Permission.serveOrders), isFalse);
        await tester.tap(find.text('Reset to Service staff'));
        await tester.pumpAndSettle();
        expect(isOn(tester, Permission.viewAuditLog), isFalse);
      });
      expect(saved, StaffRole.waiter.permissions);
    });

    testWidgets('fits a small phone at large text', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final saved = await openAndSave(
        tester,
        staffWith(StaffRole.accountant),
        () async {
          // Scrolls to the last switch (past the wordy "manage staff" note)
          // and on to the buttons without any overflow.
          await toggle(tester, Permission.viewAuditLog);
          expect(isOn(tester, Permission.viewAuditLog), isFalse);
          await toggle(tester, Permission.manageInventory);
          expect(isOn(tester, Permission.manageInventory), isTrue);
        },
      );
      expect(saved, contains(Permission.manageInventory));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel returns nothing', (tester) async {
      final saved = await openAndSave(
        tester,
        staffWith(StaffRole.waiter),
        () => toggle(tester, Permission.viewAuditLog),
        button: 'Cancel',
      );
      expect(saved, isNull);
    });
  });
}
