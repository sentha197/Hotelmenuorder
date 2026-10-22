import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

/// DineQR Admin entry point. A separate app from the customer app:
///
///     cd apps/dineqr_admin
///     flutter run
///
/// It opens on staff sign-in. Every staff action checks the role's
/// permission in the state layer; with a real backend the server must
/// authorise each request as well.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
    final dependencies = await AdminDependencies.create();
    runApp(DineQrAdminApp(dependencies: dependencies));
  } on Object catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'startup'),
    );
    runApp(AdminStartupErrorApp(onRetry: _start));
  }
}
