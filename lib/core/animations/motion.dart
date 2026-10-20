import 'package:flutter/material.dart';

/// Shared motion tokens and helpers: the single animation language of
/// DineQR. Screens use these durations and curves rather than their own.
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 400);
  static const page = Duration(milliseconds: 320);
  static const sheet = Duration(milliseconds: 420);

  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
  static const bounce = Curves.elasticOut;

  /// Signature curve for brand moments: quick start, long soft landing.
  static const brand = Cubic(0.16, 0.84, 0.24, 1);

  /// Whether the user asked the platform to reduce motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Returns [duration], or zero when reduced motion is requested.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Subtle fade + horizontal slide used for page transitions on Android,
/// Windows and Linux. iOS keeps the native Cupertino transition (and its
/// swipe-back gesture).
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    final inCurve = CurvedAnimation(
      parent: animation,
      curve: Motion.standard,
      reverseCurve: Curves.easeInCubic,
    );
    final outCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Motion.standard,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.04, 0),
      ).animate(outCurve),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(inCurve),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(inCurve),
          child: child,
        ),
      ),
    );
  }
}

/// Opens a modal bottom sheet with the shared DineQR entrance: a slightly
/// longer rise on the brand curve.
Future<T?> showBrandSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
}) {
  final reduced = Motion.reduced(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    showDragHandle: showDragHandle,
    sheetAnimationStyle: AnimationStyle(
      duration: reduced ? Duration.zero : Motion.sheet,
      reverseDuration: reduced ? Duration.zero : Motion.medium,
      curve: Motion.brand,
    ),
    builder: builder,
  );
}

/// One-shot entrance animation: fades the child in while sliding it up.
/// Use [index] to stagger items in a list.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.duration = Motion.slow,
    this.offset = const Offset(0, 0.12),
    this.staggerStep = const Duration(milliseconds: 45),
    this.maxStaggerIndex = 8,
  });

  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final Duration staggerStep;
  final int maxStaggerIndex;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // Items beyond the first few (e.g. scrolled into view later) appear
  // without a stagger delay.
  late final Duration _wait =
      widget.delay +
      (widget.index <= widget.maxStaggerIndex
          ? widget.staggerStep * widget.index
          : Duration.zero);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _wait + widget.duration,
  );
  // The delay is folded into the curve so no timers are left pending if the
  // widget is disposed early.
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _wait.inMicroseconds / (_wait + widget.duration).inMicroseconds,
      1,
      curve: Motion.standard,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.offset,
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Wraps a tappable widget with a gentle press-down scale.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.semanticLabel,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _active ? (_) => _setPressed(true) : null,
        onTapUp: _active ? (_) => _setPressed(false) : null,
        onTapCancel: _active ? () => _setPressed(false) : null,
        onTap: _active ? widget.onTap : null,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1,
          duration: Motion.of(context, const Duration(milliseconds: 120)),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Plays a quick "pop" whenever [trigger] changes (e.g. cart badge count).
class BounceOnChange extends StatefulWidget {
  const BounceOnChange({
    super.key,
    required this.trigger,
    required this.child,
    this.scale = 1.3,
  });

  final Object? trigger;
  final Widget child;
  final double scale;

  @override
  State<BounceOnChange> createState() => _BounceOnChangeState();
}

class _BounceOnChangeState extends State<BounceOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant BounceOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Up quickly, settle back with a small overshoot.
        final s = t < 0.35
            ? 1 + (widget.scale - 1) * Curves.easeOut.transform(t / 0.35)
            : 1 +
                  (widget.scale - 1) *
                      (1 - Curves.elasticOut.transform((t - 0.35) / 0.65));
        return Transform.scale(scale: s, child: child);
      },
      child: widget.child,
    );
  }
}

/// A short horizontal shake, used for validation errors.
class ShakeOnChange extends StatefulWidget {
  const ShakeOnChange({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<ShakeOnChange> createState() => _ShakeOnChangeState();
}

class _ShakeOnChangeState extends State<ShakeOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(covariant ShakeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !Motion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final dx = (1 - t) * 8 * _wave(t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }

  static double _wave(double t) {
    // Three quick oscillations.
    const cycles = 3;
    final x = t * cycles * 2;
    final phase = x - x.floorToDouble();
    final sign = x.floor().isEven ? 1 : -1;
    return sign * (1 - (2 * phase - 1).abs());
  }
}
