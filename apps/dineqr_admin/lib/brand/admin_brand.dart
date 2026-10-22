import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

import '../app/admin_theme.dart';

/// The DineQR Admin app icon: the white DineQR symbol on the burgundy admin
/// frame, with a red-to-orange accent bar so it is easy to tell apart from
/// the customer app's red icon on a home screen.
class DineQrAdminIcon extends StatelessWidget {
  const DineQrAdminIcon({
    super.key,
    this.size = 96,
    this.cornerRadius,
    this.markScale = 0.6,
    this.showBar = true,
  });
  final double size;

  /// Defaults to a 22% radius; 0 for full-bleed icons the platform masks.
  final double? cornerRadius;

  /// Symbol width as a fraction of the icon size.
  final double markScale;

  /// The accent bar (left out of adaptive-icon layers, which add their own
  /// background).
  final bool showBar;

  @override
  Widget build(BuildContext context) {
    final radius = cornerRadius ?? size * 0.22;
    return Semantics(
      label: 'DineQR Admin app icon',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF5C1424),
                  AdminColors.frame,
                  AdminColors.navy,
                ],
                stops: [0, 0.55, 1],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.6, -0.7),
                        radius: 1.1,
                        colors: [
                          AppColors.accentRed.withValues(alpha: 0.22),
                          AppColors.accentRed.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: DineQrMark(
                    size: size * markScale,
                    tone: DineQrTone.inverted,
                    semanticLabel: null,
                  ),
                ),
                if (showBar)
                  AdminAccentBar(width: size * 0.34, size: size, y: 0.62),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The admin accent: a short red-to-orange bar under the symbol.
class AdminAccentBar extends StatelessWidget {
  const AdminAccentBar({
    super.key,
    required this.width,
    required this.size,
    this.y = 0.66,
  });

  final double width;

  /// Vertical position as an [Alignment] y value.
  final double y;

  /// Size of the icon the bar sits in (for its position and thickness).
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(0, y),
      child: Container(
        width: width,
        height: (size * 0.055).clamp(1.5, 60),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size),
          gradient: const LinearGradient(
            colors: [AppColors.accentRed, AppColors.vibrantOrange],
          ),
        ),
      ),
    );
  }
}

/// "DineQR" wordmark with an ADMIN tag, for the sign-in screen and the
/// navigation frame.
class DineQrAdminLockup extends StatelessWidget {
  const DineQrAdminLockup({
    super.key,
    this.height = 36,
    this.onDark = true,
    this.showMark = true,
  });

  final double height;
  final bool onDark;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final tagColor = onDark ? AdminColors.frameMuted : AppColors.textSecondary;
    return Semantics(
      label: 'DineQR Admin',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMark) ...[
            DineQrMark(
              size: height * DineQrMark.aspectRatio,
              tone: onDark ? DineQrTone.inverted : DineQrTone.color,
              semanticLabel: null,
            ),
            SizedBox(width: height * 0.24),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DineQrWordmark(fontSize: height * 0.6, onDark: onDark),
              Text(
                'ADMIN',
                style: AppTypography.overline.copyWith(
                  fontSize: (height * 0.2).clamp(8.0, 14.0),
                  letterSpacing: height * 0.09,
                  fontWeight: FontWeight.w700,
                  color: tagColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
