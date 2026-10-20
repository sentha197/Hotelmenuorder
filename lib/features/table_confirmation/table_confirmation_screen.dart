import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/dineqr_logo.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/illustrations.dart';
import '../../state/session_controller.dart';
import '../../state/shell_controller.dart';

/// Screen 3: confirms the scanned table before the guest starts ordering.
class TableConfirmationScreen extends StatefulWidget {
  const TableConfirmationScreen({super.key, required this.tableNumber});

  final int tableNumber;

  @override
  State<TableConfirmationScreen> createState() =>
      _TableConfirmationScreenState();
}

class _TableConfirmationScreenState extends State<TableConfirmationScreen> {
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    HapticFeedback.lightImpact();
    final navigator = Navigator.of(context);
    context.read<ShellController>().select(ShellTab.home);
    await context.read<SessionController>().startSession(widget.tableNumber);
    navigator.pushNamedAndRemoveUntil(Routes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final label = AppFormat.table(widget.tableNumber);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            // Warm wash behind the top half.
            Positioned(
              left: -80,
              right: -80,
              top: -260,
              child: Container(
                height: 560,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.orangeSoft,
                      AppColors.paleWarm,
                      Colors.white,
                    ],
                    stops: [0.2, 0.6, 1],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: ConfettiBurst()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: AppSpacing.lg),
                            const FadeSlideIn(
                              offset: Offset(0, -0.3),
                              child: DineQrLockup(height: 30),
                            ),
                            const Spacer(flex: 2),
                            _TableBadge(label: label),
                            const SizedBox(height: AppSpacing.xxl),
                            FadeSlideIn(
                              index: 1,
                              child: Text(
                                'Welcome to',
                                style: AppTypography.screenTitle.copyWith(
                                  fontSize: 20,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const FadeSlideIn(
                              index: 2,
                              child: DineQrWordmark(fontSize: 38),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FadeSlideIn(
                              index: 3,
                              child: _TableChip(table: widget.tableNumber),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FadeSlideIn(
                              index: 4,
                              child: Text(
                                "You're all set. Browse the menu and order "
                                'straight from your table.',
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            const FadeSlideIn(index: 5, child: _Steps()),
                            const Spacer(flex: 3),
                            FadeSlideIn(
                              index: 6,
                              child: PrimaryButton(
                                label: 'Start Ordering',
                                trailingIcon: Icons.arrow_forward_rounded,
                                isLoading: _starting,
                                onPressed: _start,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextButton.icon(
                              onPressed: _starting
                                  ? null
                                  : () => Navigator.of(
                                      context,
                                    ).pushReplacementNamed(Routes.scan),
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 18,
                              ),
                              label: const Text('Not your table? Scan again'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                textStyle: AppTypography.label,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Table illustration inside a red-orange ring that springs in.
class _TableBadge extends StatelessWidget {
  const _TableBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: Motion.reduced(context) ? 1 : 0.6, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 178,
        height: 178,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              AppColors.primary,
              AppColors.vibrantOrange,
              AppColors.warmOrange,
              AppColors.accentRed,
              AppColors.primary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.paleWarm,
            ),
            alignment: Alignment.center,
            child: TableIllustration(label: label, width: 108),
          ),
        ),
      ),
    );
  }
}

/// "Table 12" with the number counting up from 00.
class _TableChip extends StatelessWidget {
  const _TableChip({required this.table});

  final int table;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.pill,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.table_restaurant_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          TweenAnimationBuilder<int>(
            tween: IntTween(
              begin: Motion.reduced(context) ? table : 0,
              end: table,
            ),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              'Table ${AppFormat.table(value)}',
              style: AppTypography.cardTitle.copyWith(
                color: AppColors.primary,
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.menu_book_rounded, 'Browse'),
      (Icons.touch_app_rounded, 'Order'),
      (Icons.room_service_rounded, 'Enjoy'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (index, (icon, label)) in steps.indexed) ...[
          if (index > 0)
            Container(
              width: 22,
              height: 2,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                gradient: AppColors.emberGradient,
                borderRadius: AppRadii.pill,
              ),
            ),
          SizedBox(
            width: 74,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const SizedBox(height: 6),
                Text(label, style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
