import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';

import '../brand/dineqr_logo.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Bundled food photo with a fade-in and a graceful fallback if the asset is
/// missing or fails to decode.
class FoodImage extends StatelessWidget {
  const FoodImage(
    this.asset, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.semanticLabel,
    this.appAsset = false,
  });

  final String asset;

  /// The photo is bundled with the app itself, not with dineqr_core.
  final bool appAsset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = width != null && width!.isFinite
        ? (width! * dpr).round()
        : null;
    Widget frame(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) {
      if (wasSynchronouslyLoaded) return child;
      return AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: Motion.of(context, Motion.medium),
        curve: Curves.easeOut,
        child: child,
      );
    }

    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        const _ImageFallback();

    final Widget image;
    if (asset.isEmpty) {
      image = const _ImageFallback();
    } else if (DineQrAssets.isNetwork(asset)) {
      // Menu photos served by a backend. Decoded at display size and kept
      // in Flutter's image cache like bundled photos.
      image = Image.network(
        asset,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        frameBuilder: frame,
        errorBuilder: fallback,
      );
    } else {
      image = Image.asset(
        asset,
        package: appAsset ? null : DineQrAssets.packageFor(asset),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        frameBuilder: frame,
        errorBuilder: fallback,
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        // Warm gradient placeholder that the photo fades in over.
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.paleWarm, AppColors.orangeSoft],
            ),
          ),
          child: image,
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primarySoft, AppColors.surfaceSoft],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          final size = side.isFinite ? (side * 0.5).clamp(20.0, 84.0) : 40.0;
          return Center(
            child: Opacity(
              opacity: 0.3,
              child: DineQrMark(
                size: size,
                tone: DineQrTone.mono,
                monoColor: AppColors.primary,
                semanticLabel: null,
              ),
            ),
          );
        },
      ),
    );
  }
}

const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// Greys out the photo of a dish that cannot be ordered right now and labels
/// it "Sold out".
class SoldOutVeil extends StatelessWidget {
  const SoldOutVeil({
    super.key,
    required this.soldOut,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final bool soldOut;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!soldOut) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        ColorFiltered(colorFilter: _greyscale, child: child),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: borderRadius,
            ),
          ),
        ),
        const SoldOutTag(),
      ],
    );
  }
}

/// Small "Sold out" pill.
class SoldOutTag extends StatelessWidget {
  const SoldOutTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.charcoal.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'SOLD OUT',
        style: AppTypography.overline.copyWith(
          color: Colors.white,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Small offer pill, e.g. `20% OFF` or `COMBO`.
class OfferTag extends StatelessWidget {
  const OfferTag(this.text, {super.key, this.icon = Icons.local_offer_rounded});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            text.toUpperCase(),
            style: AppTypography.overline.copyWith(
              color: Colors.white,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// A price after an offer, with the full price struck through beside it
/// (just the price when nothing is taken off).
class OfferPrice extends StatelessWidget {
  const OfferPrice({
    super.key,
    required this.price,
    this.original,
    this.style = AppTypography.price,
  });

  /// What is paid.
  final Money price;

  /// The price before the offer; ignored unless higher than [price].
  final Money? original;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final before = original;
    final reduced = before != null && before.compareTo(price) > 0;
    return Semantics(
      label: reduced
          ? '${CurrencyFormatter.format(price)}, was '
                '${CurrencyFormatter.format(before)}'
          : CurrencyFormatter.format(price),
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(CurrencyFormatter.format(price), style: style),
          if (reduced)
            Text(
              CurrencyFormatter.format(before),
              style: style.copyWith(
                color: AppColors.textMuted,
                fontSize: (style.fontSize ?? 14) * 0.8,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Indian food-labelling mark: green dot for veg, red triangle for non-veg.
class VegIndicator extends StatelessWidget {
  const VegIndicator({super.key, required this.isVeg, this.size = 14});

  final bool isVeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? AppColors.veg : AppColors.nonVeg;
    return Semantics(
      label: isVeg ? 'Vegetarian' : 'Non-vegetarian',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color, width: 1.3),
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: isVeg
            ? Container(
                width: size * 0.48,
                height: size * 0.48,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              )
            : CustomPaint(
                size: Size.square(size * 0.52),
                painter: _TrianglePainter(color),
              ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height * 0.05)
      ..lineTo(size.width, size.height * 0.92)
      ..lineTo(0, size.height * 0.92)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// `★ 4.5 (120)`
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.rating,
    this.reviewCount,
    this.size = 15,
    this.onDark = false,
  });

  final double rating;
  final int? reviewCount;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? Colors.white : AppColors.textPrimary;
    return Semantics(
      label:
          'Rated ${rating.toStringAsFixed(1)} out of 5'
          '${reviewCount == null ? '' : ' from $reviewCount reviews'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: AppColors.gold, size: size + 2),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: AppTypography.label.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: size - 2.5,
            ),
          ),
          if (reviewCount != null) ...[
            const SizedBox(width: 3),
            Text(
              '($reviewCount)',
              style: AppTypography.caption.copyWith(
                color: onDark ? Colors.white70 : AppColors.textSecondary,
                fontSize: size - 3.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
