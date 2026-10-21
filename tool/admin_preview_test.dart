// Walks through the staff dashboard with the demo data and saves a PNG of
// each module at phone and tablet size.
// Run: flutter test tool/admin_preview_test.dart --dart-define=OUT=<dir>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menu_order/admin/admin_modules.dart';
import 'package:menu_order/admin/dashboard/dashboard_screen.dart';
import 'package:menu_order/app/app.dart';
import 'package:menu_order/app/dependencies.dart';
import 'package:menu_order/app/routes.dart';
import 'package:menu_order/data/services/auth_service.dart';
import 'package:menu_order/data/storage/key_value_store.dart';
import 'package:provider/provider.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/screens_admin');

void main() {
  setUpAll(loadBrandFonts);

  const sizes = {'phone': Size(390, 844), 'tablet': Size(1280, 800)};

  for (final MapEntry(key: device, value: size) in sizes.entries) {
    testWidgets('admin $device', (tester) async {
      debugDisableShadows = false;
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final deps = await AppDependencies.create(
        store: MemoryStore(),
        config: const AppConfig(enableCamera: false),
        menuLatency: Duration.zero,
        orderLatency: Duration.zero,
        paymentTime: Duration.zero,
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: DineQrApp(dependencies: deps, initialRoute: Routes.admin),
        ),
      );
      final context = key.currentContext!;
      await tester.runAsync(() async {
        for (final file in Directory('assets/images').listSync()) {
          final path = file.path.replaceAll(r'\', '/');
          if (!path.endsWith('.jpg') && !path.endsWith('.png')) continue;
          if (!context.mounted) return;
          await precacheImage(AssetImage(path), context);
        }
      });

      var index = 0;
      Future<void> shot(String name) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final number = (index++).toString().padLeft(2, '0');
          File('$_out/${device}_${number}_$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> wait(int ms) async {
        await tester.pump();
        for (var t = 0; t < ms; t += 16) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      // Sign-in.
      await wait(900);
      await shot('login');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'owner@dineqr.demo');
      await tester.enterText(fields.last, DemoCredentials.password);
      await tester.tap(find.text('Sign in'));
      await wait(1200);

      final shell = Provider.of<AdminShellController>(
        tester.element(find.byType(DashboardScreen)),
        listen: false,
      );
      final vertical = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      for (final module in AdminModule.values) {
        shell.open(module);
        await wait(900);
        await shot(module.name);
        if (device == 'phone' &&
            {
              AdminModule.dashboard,
              AdminModule.reports,
              AdminModule.settings,
            }.contains(module)) {
          await tester.drag(vertical.first, const Offset(0, -700));
          await wait(600);
          await shot('${module.name}_more');
        }
      }

      // A bill, and a table's QR code.
      shell.open(AdminModule.bills);
      await wait(900);
      await tester.tap(find.textContaining('DQ-').first);
      await wait(1000);
      await shot('bill_detail');
      await tester.pageBack();
      await wait(800);
      shell.open(AdminModule.tables);
      await wait(900);
      await tester.tap(find.text('05').first);
      await wait(900);
      await shot('table_qr');

      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = true;
    });
  }
}
