import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'app/routes.dart';

/// Staff entry point, built separately from the guest app:
///
///     flutter run -t lib/main_admin.dart
///     flutter build web -t lib/main_admin.dart
///
/// It opens straight to staff sign-in and has no guest screens in its
/// navigation stack. Signing in is still required for every staff action;
/// with a real backend the server must also authorize each request.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
    final dependencies = await AppDependencies.create();
    runApp(
      DineQrApp(
        dependencies: dependencies,
        initialRoute: Routes.admin,
        title: 'DineQR Admin',
      ),
    );
  } on Object catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'startup'),
    );
    runApp(StartupErrorApp(onRetry: _start));
  }
}
