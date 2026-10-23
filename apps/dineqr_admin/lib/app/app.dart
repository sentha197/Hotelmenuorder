import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/admin_gate.dart';
import 'admin_theme.dart';
import 'dependencies.dart';

/// DineQR Admin: the staff and management app. It has its own entry point,
/// sign-in, navigation and build configuration; it shares only the business
/// layer (dineqr_core) and the design system with the customer app.
class DineQrAdminApp extends StatelessWidget {
  const DineQrAdminApp({super.key, required this.dependencies});

  final AdminDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppConfig>.value(value: dependencies.config),
        ChangeNotifierProvider.value(value: dependencies.admin),
        ChangeNotifierProvider.value(value: dependencies.catalog),
        ChangeNotifierProvider.value(value: dependencies.orders),
        ChangeNotifierProvider.value(value: dependencies.settings),
        ChangeNotifierProvider.value(value: dependencies.billing),
        ChangeNotifierProvider.value(value: dependencies.staff),
        ChangeNotifierProvider.value(value: dependencies.inventory),
        ChangeNotifierProvider.value(value: dependencies.sections),
        Provider.value(value: dependencies.audit),
        Provider.value(value: dependencies.printer),
        Provider.value(value: dependencies.demoData),
      ],
      child: MaterialApp(
        title: 'DineQR Admin',
        debugShowCheckedModeBanner: false,
        theme: AdminTheme.light(),
        // One home: the sign-in until a valid session exists, then the
        // role's workspace. Deep links on the web land here too, so no
        // module can be opened without signing in.
        home: const AdminGate(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Shown if the app could not start (e.g. local storage failed in an
/// unexpected way). Offers a retry instead of a blank screen.
class AdminStartupErrorApp extends StatelessWidget {
  const AdminStartupErrorApp({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DineQR Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DineQrMark(size: 110),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'DineQR Admin could not start',
                    textAlign: TextAlign.center,
                    style: AppTypography.sectionTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'The DineQR server could not be reached, or something '
                    'went wrong while preparing the app. Check the '
                    'connection and try again.',
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
/// demo).
class AdminNotConfiguredApp extends StatelessWidget {
  const AdminNotConfiguredApp({super.key, this.issue});

  /// What exactly is wrong with the build's address, when it is known.
  final ApiConfigIssue? issue;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DineQR Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DineQrMark(size: 110),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    issue?.title ?? 'DineQR Admin is not connected',
                    textAlign: TextAlign.center,
                    style: AppTypography.sectionTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    issue?.detail ??
                        'This build has no server address. Build it with '
                            '--dart-define=DINEQR_API_URL=<server URL>, or '
                            'with --dart-define=DINEQR_MODE=demo for the '
                            'offline demo.',
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
