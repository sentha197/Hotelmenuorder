import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'app/secure_tokens.dart';

/// DineQR Admin entry point. A separate app from the customer app:
///
///     cd apps/dineqr_admin
///     flutter run --dart-define=DINEQR_API_URL=http://10.0.2.2:5264
///
/// It opens on staff sign-in against the DineQR API, which authorises every
/// request by the account's role. Without the define, a debug build uses the
/// API on this computer (port 5264) and a release build the deployed API
/// ([ApiConfig.productionUrl]). `--dart-define=DINEQR_MODE=demo` runs the
/// explicit offline demo instead.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  final demo = AdminDependencies.demoRequested;
  final api = AdminDependencies.apiFromEnvironment;
  if (!demo && api == null) {
    // No usable server address: say exactly what is wrong and what to use,
    // rather than showing any data.
    runApp(AdminNotConfiguredApp(issue: ApiConfig.issueFromEnvironment()));
    return;
  }
  try {
    final dependencies = await AdminDependencies.create(
      config: AppConfig(demoMode: demo),
      api: api,
      tokens: const SecureTokenStorage(),
    );
    runApp(DineQrAdminApp(dependencies: dependencies));
  } on Object catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'startup'),
    );
    runApp(AdminStartupErrorApp(onRetry: _start));
  }
}
