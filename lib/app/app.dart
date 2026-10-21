import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/brand/dineqr_logo.dart';
import '../core/widgets/app_buttons.dart';
import 'dependencies.dart';
import 'routes.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/app_typography.dart';

class DineQrApp extends StatelessWidget {
  const DineQrApp({
    super.key,
    required this.dependencies,
    this.initialRoute = Routes.splash,
    this.title = 'DineQR',
  });

  final AppDependencies dependencies;
  final String initialRoute;

  /// Task-switcher title (the admin build uses its own).
  final String title;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppConfig>.value(value: dependencies.config),
        ChangeNotifierProvider.value(value: dependencies.session),
        ChangeNotifierProvider.value(value: dependencies.catalog),
        ChangeNotifierProvider.value(value: dependencies.cart),
        ChangeNotifierProvider.value(value: dependencies.orders),
        ChangeNotifierProvider.value(value: dependencies.shell),
        ChangeNotifierProvider.value(value: dependencies.settings),
        ChangeNotifierProvider.value(value: dependencies.billing),
        ChangeNotifierProvider.value(value: dependencies.admin),
        ChangeNotifierProvider.value(value: dependencies.staff),
        ChangeNotifierProvider.value(value: dependencies.inventory),
        Provider.value(value: dependencies.audit),
        Provider.value(value: dependencies.printer),
        Provider.value(value: dependencies.demoData),
      ],
      child: MaterialApp(
        title: title,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        initialRoute: initialRoute,
        onGenerateRoute: AppRouter.onGenerateRoute,
        onGenerateInitialRoutes: AppRouter.onGenerateInitialRoutes,
        // Allow larger text, within limits the layouts are designed for.
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
                    'Something went wrong while preparing the app. '
                    'Please try again.',
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
