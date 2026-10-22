import 'package:dineqr_admin/app/app.dart';
import 'package:dineqr_admin/modules/dashboard/dashboard_screen.dart';
import 'package:dineqr_admin/shell/admin_modules.dart';
import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/brand_fonts.dart';
import 'support/harness.dart';

/// Opens every admin module with the demo data and scrolls through it,
/// failing on any layout error (e.g. a row overflowing on a phone). Uses the
/// real brand font at the largest text size the app allows.
void main() {
  setUpAll(loadBrandFonts);

  const sizes = {'small phone': Size(360, 760), 'tablet': Size(1280, 800)};

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('every admin module lays out on a $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final deps = await createAdminDependencies(seedDemoData: true);
      await deps.admin.signIn('owner@dineqr.demo', DemoCredentials.password);

      final errors = <String>[];
      var current = AdminModule.dashboard;
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final context =
            details.informationCollector?.call() ?? const <DiagnosticsNode>[];
        errors.add(
          [
            '[${current.name}] ${details.exceptionAsString()}',
            ...context
                .map((n) => n.toStringDeep())
                .expand((s) => s.split('\n'))
                .where((l) => l.contains('←'))
                .take(4),
          ].join('\n'),
        );
      };
      try {
        await tester.pumpWidget(DineQrAdminApp(dependencies: deps));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        final shell = Provider.of<AdminShellController>(
          tester.element(find.byType(DashboardScreen)),
          listen: false,
        );
        final vertical = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        for (final module in AdminModule.values) {
          current = module;
          shell.open(module);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          for (var i = 0; i < 8 && vertical.evaluate().isNotEmpty; i++) {
            await tester.drag(
              vertical.first,
              const Offset(0, -500),
              warnIfMissed: false,
            );
            await tester.pump(const Duration(milliseconds: 250));
          }
        }
      } finally {
        FlutterError.onError = original;
      }
      expect(errors, isEmpty, reason: errors.join('\n\n'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
