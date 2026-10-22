import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'app_buttons.dart';

/// Friendly empty / error placeholder with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.illustration,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Replaces the default icon halo (e.g. the branded empty cart).
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeSlideIn(child: illustration ?? IconHalo(icon: icon)),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              index: 1,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.sectionTitle.copyWith(fontSize: 18),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FadeSlideIn(
              index: 2,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              FadeSlideIn(
                index: 3,
                child: PrimaryButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  expand: false,
                  height: 50,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Brand icon badge: a gradient icon on a white disc inside a warm halo, with
/// two small QR modules as accents.
class IconHalo extends StatelessWidget {
  const IconHalo({super.key, required this.icon, this.size = 120});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final module = size * 0.075;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.orangeSoft, AppColors.paleWarm],
                  stops: [0.55, 1],
                ),
              ),
            ),
            Container(
              width: size * 0.68,
              height: size * 0.68,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: size * 0.14,
                    offset: Offset(0, size * 0.05),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: AppColors.emberGradient.createShader,
                child: Icon(icon, size: size * 0.32, color: Colors.white),
              ),
            ),
            Positioned(
              right: size * 0.12,
              top: size * 0.1,
              child: _Module(size: module, color: AppColors.vibrantOrange),
            ),
            Positioned(
              right: size * 0.04,
              top: size * 0.22,
              child: _Module(size: module * 0.7, color: AppColors.primary),
            ),
            Positioned(
              left: size * 0.08,
              bottom: size * 0.16,
              child: _Module(size: module * 0.8, color: AppColors.warmOrange),
            ),
          ],
        ),
      ),
    );
  }
}

class _Module extends StatelessWidget {
  const _Module({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
    );
  }
}
