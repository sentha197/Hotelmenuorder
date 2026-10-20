import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../animations/motion.dart';

/// `− 1 +` stepper. The number rolls up or down when it changes.
class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.min = 0,
    this.max = 20,
    this.compact = false,
    this.itemName = 'item',
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// The minus button is disabled at this value.
  final int min;
  final int max;
  final bool compact;
  final String itemName;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 32.0 : 38.0;
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            filled: false,
            size: height - 6,
            semanticLabel: 'Decrease $itemName quantity',
            onTap: quantity > min ? onDecrement : null,
          ),
          SizedBox(
            width: compact ? 26 : 32,
            child: Semantics(
              liveRegion: true,
              label: 'Quantity $quantity',
              excludeSemantics: true,
              child: AnimatedCountText(
                value: quantity,
                style: AppTypography.cardTitle.copyWith(
                  fontSize: compact ? 13.5 : 15,
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            filled: true,
            size: height - 6,
            semanticLabel: 'Increase $itemName quantity',
            onTap: quantity < max ? onIncrement : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.filled,
    required this.size,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final double size;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final background = filled
        ? (enabled
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.3))
        : AppColors.primarySoft;
    final foreground = filled
        ? Colors.white
        : (enabled ? AppColors.primary : AppColors.textMuted);
    return Pressable(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      semanticLabel: semanticLabel,
      scale: 0.85,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: size * 0.6, color: foreground),
      ),
    );
  }
}

/// Integer text that rolls vertically when its value changes.
class AnimatedCountText extends StatefulWidget {
  const AnimatedCountText({
    super.key,
    required this.value,
    required this.style,
  });

  final int value;
  final TextStyle style;

  @override
  State<AnimatedCountText> createState() => _AnimatedCountTextState();
}

class _AnimatedCountTextState extends State<AnimatedCountText> {
  bool _increasing = true;

  @override
  void didUpdateWidget(covariant AnimatedCountText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _increasing = widget.value > oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final direction = _increasing ? 1.0 : -1.0;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.fast),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(widget.value);
          final begin = Offset(
            0,
            incoming ? 0.7 * direction : -0.7 * direction,
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: begin,
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Text(
          '${widget.value}',
          key: ValueKey(widget.value),
          textAlign: TextAlign.center,
          style: widget.style,
        ),
      ),
    );
  }
}
