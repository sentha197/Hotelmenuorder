import 'dart:math' as math;

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

/// One bar group of [DailyBarChart].
class ChartDay {
  const ChartDay({
    required this.label,
    required this.detail,
    required this.billed,
    required this.collected,
  });

  /// Short axis label, e.g. `Sat` or `17`.
  final String label;

  /// Full label for the selected-day readout, e.g. `Sat 17 Oct`.
  final String detail;
  final Money billed;
  final Money collected;
}

/// Billed vs collected per day. Tap a day to read its exact values.
class DailyBarChart extends StatefulWidget {
  const DailyBarChart({super.key, required this.days, this.height = 180});

  final List<ChartDay> days;
  final double height;

  @override
  State<DailyBarChart> createState() => _DailyBarChartState();
}

class _DailyBarChartState extends State<DailyBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final selected = _selected != null && _selected! < days.length
        ? days[_selected!]
        : (days.isEmpty ? null : days.last);
    final maxPaise = days.fold<int>(
      1,
      (m, d) => math.max(m, math.max(d.billed.paise, d.collected.paise)),
    );
    return Semantics(
      label:
          'Daily sales chart. ${days.length} days. '
          'Highest day ${CurrencyFormatter.format(Money(maxPaise))}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected != null)
            // Wraps onto two lines on phones.
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  selected.detail,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _Legend(
                  color: AppColors.primarySoft,
                  border: AppColors.primary.withValues(alpha: 0.3),
                  label: 'Billed ${CurrencyFormatter.format(selected.billed)}',
                ),
                _Legend(
                  color: AppColors.primary,
                  label:
                      'Collected ${CurrencyFormatter.format(selected.collected)}',
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: widget.height,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Motion.brand,
              builder: (context, grow, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / math.max(1, days.length);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => setState(
                      () => _selected = (details.localPosition.dx / slot)
                          .floor()
                          .clamp(0, days.length - 1),
                    ),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, widget.height),
                      painter: _BarsPainter(
                        days: days,
                        maxPaise: maxPaise,
                        grow: grow,
                        selected: _selected ?? days.length - 1,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.days,
    required this.maxPaise,
    required this.grow,
    required this.selected,
  });

  final List<ChartDay> days;
  final int maxPaise;
  final double grow;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const labelHeight = 18.0;
    final chartHeight = size.height - labelHeight;
    final slot = size.width / days.length;
    final barWidth = math.min(26.0, slot * 0.62);
    // Grid lines.
    final grid = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final labelStyle = AppTypography.caption.copyWith(fontSize: 10);
    // Only label every n-th day when crowded.
    final every = math.max(1, (days.length / 10).ceil());
    for (final (i, day) in days.indexed) {
      final cx = slot * i + slot / 2;
      final billedH = chartHeight * (day.billed.paise / maxPaise) * grow;
      final collectedH = chartHeight * (day.collected.paise / maxPaise) * grow;
      final isSelected = i == selected;
      final billedRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          cx - barWidth / 2,
          chartHeight - billedH,
          barWidth,
          billedH,
        ),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      );
      canvas.drawRRect(
        billedRect,
        Paint()
          ..color = isSelected
              ? AppColors.primary.withValues(alpha: 0.22)
              : AppColors.primarySoft,
      );
      final inner = barWidth * 0.56;
      final collectedRect = Rect.fromLTWH(
        cx - inner / 2,
        chartHeight - collectedH,
        inner,
        collectedH,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          collectedRect,
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.vibrantOrange, AppColors.primary],
          ).createShader(collectedRect.inflate(1)),
      );
      if (i % every == 0 || isSelected) {
        final painter = TextPainter(
          text: TextSpan(
            text: day.label,
            style: labelStyle.copyWith(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(cx - painter.width / 2, chartHeight + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.grow != grow ||
      oldDelegate.selected != selected ||
      oldDelegate.days != days;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.border});

  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: border == null ? null : Border.all(color: border!),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}

/// One row of a [RankedBars] list.
class RankedValue {
  const RankedValue({
    required this.label,
    required this.value,
    required this.amountLabel,
    this.detail = '',
  });

  final String label;
  final String detail;

  /// Used for bar length.
  final int value;
  final String amountLabel;
}

/// Labelled horizontal bars (best sellers, categories, tables).
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.values, this.maxRows = 8});

  final List<RankedValue> values;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final shown = values.take(maxRows).toList();
    final max = shown.fold<int>(1, (m, v) => math.max(m, v.value));
    return Column(
      children: [
        for (final (index, row) in shown.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Semantics(
              label: '${row.label}, ${row.amountLabel}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${index + 1}',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: index < 3
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.detail.isEmpty
                              ? row.label
                              : '${row.label} · ${row.detail}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label,
                        ),
                      ),
                      Text(
                        row.amountLabel,
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: Motion.reduced(context) ? row.value / max : 0,
                        end: row.value / max,
                      ),
                      duration: Duration(milliseconds: 500 + index * 60),
                      curve: Motion.brand,
                      builder: (context, fraction, _) => ClipRRect(
                        borderRadius: AppRadii.pill,
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: ColoredBox(color: AppColors.skeleton),
                              ),
                              FractionallySizedBox(
                                widthFactor: fraction.clamp(0.0, 1.0),
                                child: const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.emberGradient,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One slice of [DonutChart].
class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final Money amount;
  final Color color;
}

/// Share of a total by category (e.g. payment methods), with a legend.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.size = 132});

  final List<DonutSlice> slices;
  final double size;

  static const palette = [
    AppColors.primary,
    AppColors.vibrantOrange,
    AppColors.gold,
    AppColors.deepRed,
    AppColors.warmOrange,
    AppColors.charcoal,
  ];

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (s, slice) => s + slice.amount.paise);
    return Semantics(
      label: [
        for (final s in slices)
          '${s.label} ${CurrencyFormatter.format(s.amount)}',
      ].join(', '),
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Motion.brand,
            builder: (context, sweep, _) => CustomPaint(
              size: Size.square(size),
              painter: _DonutPainter(slices, total, sweep),
              child: SizedBox.square(
                dimension: size,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Collected', style: AppTypography.caption),
                      FittedBox(
                        child: Text(
                          CurrencyFormatter.format(Money(total)),
                          style: AppTypography.cardTitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final slice in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: slice.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          slice.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        CurrencyFormatter.format(slice.amount),
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        total == 0
                            ? ''
                            : '  ${(slice.amount.paise * 100 / total).round()}%',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.total, this.sweep);

  final List<DonutSlice> slices;
  final int total;
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.14;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.skeleton;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (final slice in slices) {
      final angle = math.pi * 2 * slice.amount.paise / total * sweep;
      canvas.drawArc(
        arcRect,
        start,
        math.max(0, angle - 0.03),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = slice.color,
      );
      start += angle;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.sweep != sweep || oldDelegate.total != total;
}
