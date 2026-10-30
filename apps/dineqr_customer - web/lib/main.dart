import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await _start();
}

Future<void> _start() async {
  final config = CustomerConfig.fromEnvironment();
  if (!config.isConfigured) {
    // No usable server address: say exactly what is wrong and what to use,
    // rather than showing any menu.
    runApp(NotConfiguredApp(issue: ApiConfig.issueFromEnvironment()));
    return;
  }
  try {
    final dependencies = await CustomerDependencies.create(config: config);
    runApp(DineQrApp(dependencies: dependencies));
  } on Object catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'startup'),
    );
    runApp(StartupErrorApp(onRetry: _start));
  }
}
