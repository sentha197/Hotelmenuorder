import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order_status.dart';
import '../../data/models/restaurant_order.dart';

enum _StepState { done, current, upcoming }

extension OrderStatusIcon on OrderStatus {
  IconData get icon => switch (this) {
    OrderStatus.placed => Icons.receipt_long_rounded,
    OrderStatus.preparing => Icons.soup_kitchen_rounded,
    OrderStatus.readyToServe => Icons.room_service_rounded,
    OrderStatus.served => Icons.restaurant_rounded,
  };
}

/// Vertical order timeline: completed, current and upcoming stages.
class TrackingTimeline extends StatelessWidget {
  const TrackingTimeline({super.key, required this.order});

  final RestaurantOrder order;

  String _subtitle(OrderStatus status) {
    final time = order.statusTimes[status];
    if (time != null) return AppFormat.time(time);
    return switch (status) {
      OrderStatus.readyToServe =>
        'Expected around ${AppFormat.time(order.estimatedReadyAt)}',
      OrderStatus.served => 'Your server will bring it to your table',
      OrderStatus.preparing => 'The kitchen will start shortly',
      OrderStatus.placed => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final steps = OrderStatus.values;
    return Column(
      children: [
        for (final (index, status) in steps.indexed)
          _TimelineStep(
            status: status,
            state: status.index < order.status.index
                ? _StepState.done
                : status == order.status
                ? (status == OrderStatus.served
                      ? _StepState.done
                      : _StepState.current)
                : _StepState.upcoming,
            subtitle: _subtitle(status),
            isLast: index == steps.length - 1,
            nextReached:
                index < steps.length - 1 &&
                steps[index + 1].index <= order.status.index,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.status,
    required this.state,
    required this.subtitle,
    required this.isLast,
    required this.nextReached,
  });

  final OrderStatus status;
  final _StepState state;
  final String subtitle;
  final bool isLast;
  final bool nextReached;

  @override
  Widget build(BuildContext context) {
    final upcoming = state == _StepState.upcoming;
    final current = state == _StepState.current;
    return Semantics(
      label:
          '${status.label}, ${switch (state) {
            _StepState.done => 'completed',
            _StepState.current => 'in progress',
            _StepState.upcoming => 'upcoming',
          }}. $subtitle',
      excludeSemantics: true,
      // The connector is painted behind the row so it always spans the
      // step's full height, however tall the text gets.
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: nextReached ? 1 : 0),
        duration: Motion.of(context, const Duration(milliseconds: 600)),
        curve: Motion.standard,
        builder: (context, fill, child) => CustomPaint(
          painter: isLast ? null : _ConnectorPainter(fill),
          child: child,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _dotColumnWidth,
              child: Center(
                heightFactor: 1,
                child: _StepDot(state: state, icon: status.icon),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 6, bottom: isLast ? 0 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.of(context, Motion.medium),
                            style: AppTypography.cardTitle.copyWith(
                              color: upcoming
                                  ? AppColors.textMuted
                                  : AppColors.textPrimary,
                              fontWeight: current
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                            child: Text(status.label),
                          ),
                        ),
                        if (current) ...[
                          const SizedBox(width: 8),
                          const _NowChip(),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.caption.copyWith(
                          color: current
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowChip extends StatelessWidget {
  const _NowChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        gradient: AppColors.emberGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'NOW',
        style: AppTypography.overline.copyWith(
          color: Colors.white,
          fontSize: 9,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Stage marker. The current stage pulses gently while it is on screen.
class _StepDot extends StatefulWidget {
  const _StepDot({required this.state, required this.icon});

  final _StepState state;
  final IconData icon;

  @override
  State<_StepDot> createState() => _StepDotState();
}

class _StepDotState extends State<_StepDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _StepDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    final shouldPulse =
        widget.state == _StepState.current && !Motion.reduced(context);
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!shouldPulse) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final decoration = switch (state) {
      _StepState.done => const BoxDecoration(
        color: AppColors.charcoal,
        shape: BoxShape.circle,
      ),
      _StepState.current => const BoxDecoration(
        gradient: AppColors.emberGradient,
        shape: BoxShape.circle,
      ),
      _StepState.upcoming => BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border, width: 2),
      ),
    };
    return SizedBox.square(
      dimension: _dotColumnWidth,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (state == _StepState.current)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_pulse.value);
                return Container(
                  width: _dotSize + 16 * t,
                  height: _dotSize + 16 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.vibrantOrange.withValues(
                      alpha: 0.28 * (1 - t),
                    ),
                  ),
                );
              },
            ),
          TweenAnimationBuilder<double>(
            key: ValueKey(state),
            tween: Tween(begin: Motion.reduced(context) ? 1 : 0.6, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: _dotSize,
              height: _dotSize,
              decoration: decoration,
              child: Icon(
                state == _StepState.done ? Icons.check_rounded : widget.icon,
                size: 17,
                color: state == _StepState.upcoming
                    ? AppColors.textMuted
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _dotColumnWidth = 36.0;
const _dotSize = 32.0;

/// Vertical line from below a step's dot to the bottom of the step. [fill]
/// (0-1) is how much of it is coloured as completed.
class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter(this.fill);

  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    const x = _dotColumnWidth / 2;
    const top = _dotColumnWidth / 2 + _dotSize / 2 + 4;
    final bottom = size.height + 2;
    if (bottom <= top) return;
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(x, top),
      Offset(x, bottom),
      paint..color = AppColors.border,
    );
    if (fill > 0) {
      final end = top + (bottom - top) * fill;
      canvas.drawLine(
        const Offset(x, top),
        Offset(x, end),
        paint
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.charcoal, AppColors.accentRed],
          ).createShader(Rect.fromLTRB(x - 2, top, x + 2, end)),
      );
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter oldDelegate) => oldDelegate.fill != fill;
}
