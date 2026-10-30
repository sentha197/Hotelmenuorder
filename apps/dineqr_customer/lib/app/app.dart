import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/network/dine_in_lock.dart';
import 'dependencies.dart';
import 'routes.dart';
import 'upi_launcher.dart';

class DineQrApp extends StatelessWidget {
  const DineQrApp({
    super.key,
    required this.dependencies,
    this.initialRoute = Routes.splash,
  });

  final CustomerDependencies dependencies;
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CustomerDependencies>.value(value: dependencies),
        Provider<AppConfig>.value(value: dependencies.config.app),
        Provider<CustomerConfig>.value(value: dependencies.config),
        ChangeNotifierProvider.value(value: dependencies.session),
        ChangeNotifierProvider.value(value: dependencies.access),
        ChangeNotifierProvider.value(value: dependencies.catalog),
        ChangeNotifierProvider.value(value: dependencies.cart),
        ChangeNotifierProvider.value(value: dependencies.orders),
        ChangeNotifierProvider.value(value: dependencies.shell),
        ChangeNotifierProvider.value(value: dependencies.settings),
        ChangeNotifierProvider.value(value: dependencies.billing),
        Provider.value(value: dependencies.printer),
        Provider<UpiLauncher>.value(value: dependencies.upiLauncher),
        Provider.value(value: dependencies.demoData),
      ],
      child: MaterialApp(
        title: 'DineQR',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: initialRoute,
        navigatorKey: dependencies.navigatorKey,
        onGenerateRoute: AppRouter.onGenerateRoute,
        onGenerateInitialRoutes: AppRouter.onGenerateInitialRoutes,
        // Allow larger text, within limits the layouts are designed for.
        // Every screen sits under the dine-in Wi-Fi lock.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: DineInLock(
            onScanOther: () async {
              await dependencies.session.clear();
              dependencies.navigatorKey.currentState?.pushNamedAndRemoveUntil(
                Routes.scan,
                (route) => false,
              );
            },
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Shown if the app could not start (e.g. local storage failed in an
/// unexpected way). Offers a retry instead of a blank screen.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DineQR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DineQrMark(size: 120),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'DineQR could not start',
                    textAlign: TextAlign.center,
                    style: AppTypography.sectionTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'The restaurant server could not be reached, or '
                    'something went wrong while preparing the app. Check '
                    'your connection and try again.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySecondary.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  PrimaryButton(
                    label: 'Try again',
                    expand: false,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A build whose `DINEQR_API_URL` cannot work (and not the explicit offline
/// demo): explains how to fix it instead of showing invented data.
class NotConfiguredApp extends StatelessWidget {
  const NotConfiguredApp({super.key, this.issue});

  /// What exactly is wrong with the build's address, when it is known.
  final ApiConfigIssue? issue;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DineQR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DineQrMark(size: 120),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    issue?.title ?? 'DineQR is not connected',
                    textAlign: TextAlign.center,
                    style: AppTypography.sectionTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    issue?.detail ??
                        'This build has no restaurant server address. Build '
                            'it with --dart-define=DINEQR_API_URL=<server '
                            'URL>, or with --dart-define=DINEQR_MODE=demo for '
                            'the offline demo.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySecondary.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
