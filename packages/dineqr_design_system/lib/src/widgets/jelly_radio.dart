import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../motion/motion.dart';

/// A row of single-choice chips whose chosen chip swells with a jelly
/// wobble and nudges its neighbours aside (the web apps' JellyRadio).
///
/// Each app keeps its own look: [decorationOf] paints a chip's body (what
/// swells, so the label stays crisp) and [labelBuilder] its content. With
/// reduced motion only the colours change. When [scrollable], the row
/// scrolls sideways and a newly chosen chip is scrolled into view;
/// otherwise the chips wrap.
class JellyRadio<T> extends StatefulWidget {
  const JellyRadio({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.decorationOf,
    required this.labelBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    this.height,
    this.spacing = 8,
    this.runSpacing = 8,
    this.scrollable = true,
    this.pressScale = 0.95,
    this.swell = 0.12,
    this.barge = 4,
    this.shrink = 0.03,
    this.jelly = 1,
    this.bounce = 0.25,
    this.stagger = const Duration(milliseconds: 22),
    this.stiffness = 580,
  });

  final List<T> values;

  /// The chosen value (always controlled by the caller).
  final T selected;
  final ValueChanged<T> onSelected;

  /// The chip's body: colour, border, radius.
  final BoxDecoration Function(T value, bool selected) decorationOf;

  /// The chip's content (text, icon, count).
  final Widget Function(BuildContext context, T value, bool selected)
  labelBuilder;

  final EdgeInsetsGeometry padding;

  /// Fixed chip height, or null to fit the label and [padding].
  final double? height;

  /// Space between chips, and between wrapped lines.
  final double spacing;
  final double runSpacing;
  final bool scrollable;

  /// Press-down scale while a finger is on a chip.
  final double pressScale;

  /// How far the chosen chip swells (0.12 = 12%).
  final double swell;

  /// How far neighbours are pushed aside (logical pixels).
  final double barge;

  /// How far the other chips shrink back (0.03 = 3%).
  final double shrink;

  /// Wobble after the swell (0 = none, 1 = full).
  final double jelly;

  /// Overshoot as pushed chips come back (0 to 1).
  final double bounce;

  /// Delay per chip as the push travels outward.
  final Duration stagger;

  /// Spring stiffness: higher is quicker.
  final double stiffness;

  @override
  State<JellyRadio<T>> createState() => _JellyRadioState<T>();
}

class _JellyRadioState<T> extends State<JellyRadio<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];
  int _from = -1;
  int _to = -1;

  /// Length of one chip's movement, in seconds (a spring's rough settle
  /// time for [JellyRadio.stiffness]).
  double get _move =>
      (14 / math.sqrt(widget.stiffness)).clamp(0.32, 1.1).toDouble();
  double get _staggerSeconds => widget.stagger.inMicroseconds / 1e6;
  double get _total => _move + 3 * _staggerSeconds;

  int _indexOf(T value) => widget.values.indexOf(value);

  @override
  void didUpdateWidget(covariant JellyRadio<T> old) {
    super.didUpdateWidget(old);
    final from = old.values.indexOf(old.selected);
    final to = _indexOf(widget.selected);
    if (from == to || to < 0) return;
    _reveal(to);
    if (Motion.reduced(context)) return;
    _from = from;
    _to = to;
    _controller.duration = Duration(microseconds: (_total * 1e6).round());
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the row just enough to show chip [index].
  void _reveal(int index) {
    if (!widget.scrollable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || index >= _keys.length) return;
      final box = _keys[index].currentContext?.findRenderObject();
      if (box == null) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final atStart = viewport.getOffsetToReveal(box, 0).offset;
      final atEnd = viewport.getOffsetToReveal(box, 1).offset;
      final position = _scroll.position;
      double? target;
      if (position.pixels > atStart) target = atStart;
      if (position.pixels < atEnd) target = atEnd;
      if (target == null) return;
      _scroll.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: Motion.of(context, Motion.medium),
        curve: Motion.standard,
      );
    });
  }

  /// [values] at [times] (0 to 1), eased within each segment, at [t].
  static double _keyframes(List<double> values, List<double> times, double t) {
    if (t <= 0) return values.first;
    if (t >= 1) return values.last;
    for (var i = 1; i < times.length; i++) {
      if (t <= times[i]) {
        final local = (t - times[i - 1]) / (times[i] - times[i - 1]);
        final eased = Curves.easeOut.transform(local);
        return values[i - 1] + (values[i] - values[i - 1]) * eased;
      }
    }
    return values.last;
  }

  /// Progress (0 to 1) of a movement of [length] seconds starting after
  /// [delay] seconds, at the controller's current time.
  double _phase(double delay, double length) {
    final now = _controller.value * _total;
    return ((now - delay) / length).clamp(0.0, 1.0);
  }

  /// The skin's scale (x, y) and the chip's offset for chip [i].
  (double, double, double) _motionOf(int i) {
    if (!_controller.isAnimating || _to < 0) return (1, 1, 0);
    final s = widget.swell;
    final j = widget.jelly;
    if (i == _to) {
      final t = _phase(0, _move);
      const times = [0.0, 0.22, 0.5, 0.75, 1.0];
      return (
        _keyframes([1, 1 + s, 1 - s * 0.45 * j, 1 + s * 0.2 * j, 1], times, t),
        _keyframes(
          [1, 1 - s * 0.55, 1 + s * 0.35 * j, 1 - s * 0.12 * j, 1],
          times,
          t,
        ),
        0,
      );
    }
    final distance = (i - _to).abs();
    final delay = distance * _staggerSeconds;
    var dx = 0.0;
    if (distance <= 3 && widget.barge > 0) {
      final push = (i - _to).sign * widget.barge / distance;
      dx = _keyframes(
        [0, push, -push * widget.bounce, 0],
        const [0, 0.25, 0.6, 1],
        _phase(delay, _move * 0.9),
      );
    }
    var scale = 1.0;
    if (widget.shrink > 0) {
      final dip = i == _from ? widget.shrink * 2 : widget.shrink;
      scale = _keyframes(
        [1, 1 - dip, 1],
        const [0, 0.5, 1],
        _phase(delay, _move * 0.7),
      );
    }
    return (scale, scale, dx);
  }

  @override
  Widget build(BuildContext context) {
    while (_keys.length < widget.values.length) {
      _keys.add(GlobalKey());
    }
    final chosen = _indexOf(widget.selected);
    final duration = Motion.of(context, Motion.medium);
    final chips = [
      for (var i = 0; i < widget.values.length; i++)
        _chip(context, i, i == chosen, duration),
    ];
    final Widget row = widget.scrollable
        ? SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) SizedBox(width: widget.spacing),
                  chips[i],
                ],
              ],
            ),
          )
        : Wrap(
            spacing: widget.spacing,
            runSpacing: widget.runSpacing,
            children: chips,
          );
    return row;
  }

  Widget _chip(BuildContext context, int i, bool selected, Duration duration) {
    final value = widget.values[i];
    final decoration = widget.decorationOf(value, selected);
    // The border is drawn by the skin, behind the label; keep room for it so
    // a chip is the size of a plain bordered container with this padding.
    final border = decoration.border?.dimensions ?? EdgeInsets.zero;
    return KeyedSubtree(
      key: _keys[i],
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Pressable(
          onTap: () {
            if (!selected) widget.onSelected(value);
          },
          scale: widget.pressScale,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, label) {
              final (sx, sy, dx) = _motionOf(i);
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(sx, sy, 1),
                        child: AnimatedContainer(
                          duration: duration,
                          curve: Motion.standard,
                          decoration: decoration,
                        ),
                      ),
                    ),
                    label!,
                  ],
                ),
              );
            },
            child: Container(
              height: widget.height,
              padding: widget.padding.add(border),
              alignment: widget.height == null ? null : Alignment.center,
              child: widget.labelBuilder(context, value, selected),
            ),
          ),
        ),
      ),
    );
  }
}
