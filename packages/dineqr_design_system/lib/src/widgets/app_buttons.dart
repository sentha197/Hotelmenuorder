import 'package:flutter/material.dart';

import '../motion/loaders.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Primary call-to-action with the DineQR double-layer treatment: a deep red
/// lip under a red-orange gradient face with a faint top highlight. Shows the
/// QR pulse loader while [isLoading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
    this.height = 54,
    this.color,
    this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool expand;
  final double height;

  /// Solid fill instead of the brand gradient (e.g. success green).
  final Color? color;

  /// Optional custom content (replaces label and icons).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final active = enabled || isLoading;
    final solid = color;
    final lip = solid == null
        ? AppColors.lip
        : Color.lerp(solid, Colors.black, 0.32)!;
    final glow = solid ?? AppColors.primary;
    final compact = height < 50;
    return Pressable(
      onTap: enabled ? onPressed : null,
      scale: 0.97,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medium),
        curve: Motion.standard,
        height: height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.md : AppSpacing.xxl,
        ),
        decoration: BoxDecoration(
          color: active ? solid : const Color(0xFFE9C9C9),
          gradient: active && solid == null ? AppColors.ctaGradient : null,
          borderRadius: AppRadii.button,
          boxShadow: active
              ? [
                  BoxShadow(color: lip, offset: Offset(0, compact ? 2 : 3)),
                  BoxShadow(
                    color: glow.withValues(alpha: enabled ? 0.28 : 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 9),
                  ),
                ]
              : null,
        ),
        foregroundDecoration: active
            ? BoxDecoration(
                borderRadius: AppRadii.button,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Colors.white.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              )
            : null,
        child: Center(
          widthFactor: 1,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: isLoading
                ? QrPulseLoader(
                    key: const ValueKey('loading'),
                    size: compact ? 18 : 22,
                    semanticLabel: '$label, in progress',
                  )
                : KeyedSubtree(
                    key: const ValueKey('content'),
                    child:
                        child ??
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: Colors.white, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.button.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (trailingIcon != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Icon(trailingIcon, color: Colors.white, size: 20),
                            ],
                          ],
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Outlined variant for secondary actions.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? AppColors.primary : AppColors.textMuted;
    return Pressable(
      onTap: onPressed,
      scale: 0.97,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: height < 50 ? AppSpacing.md : AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadii.button,
          border: Border.all(color: color, width: 1.4),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.button.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round icon button, used over images and in headers.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 40,
    this.iconSize = 20,
    this.backgroundColor = Colors.white,
    this.iconColor = AppColors.textPrimary,
    this.shadow = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color iconColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      semanticLabel: tooltip,
      scale: 0.9,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          boxShadow: shadow ? AppShadows.soft : null,
        ),
        child: Icon(icon, size: iconSize, color: iconColor),
      ),
    );
  }
}

/// Chevron back button used in app bars.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.color});

  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      icon: Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 20,
        color: color ?? AppColors.textPrimary,
      ),
    );
  }
}

/// Section title with an optional trailing action ("View All").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.xl,
      AppSpacing.page - 8,
      AppSpacing.sm,
    ),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.sectionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: AppTypography.label,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(48, 40),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// White rounded card with the standard shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color = AppColors.card,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadii.card,
        border: border ? Border.all(color: AppColors.border) : null,
        boxShadow: AppShadows.soft,
      ),
      child: child,
    );
  }
}

/// Small pill marking demo-only behaviour.
class DemoTag extends StatelessWidget {
  const DemoTag({super.key, this.label = 'DEMO', this.onDark = false});

  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.infoSoft,
        borderRadius: AppRadii.pill,
      ),
      child: Text(
        label,
        style: AppTypography.overline.copyWith(
          fontSize: 9.5,
          letterSpacing: 1.1,
          color: onDark ? Colors.white : AppColors.info,
        ),
      ),
    );
  }
}
