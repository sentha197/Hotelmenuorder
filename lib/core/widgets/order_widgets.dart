import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/order_status.dart';
import '../../data/models/pricing.dart';
import '../animations/motion.dart';
import '../utils/currency.dart';

/// Coloured pill showing an order's kitchen status.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({super.key, required this.status});

  final OrderStatus status;

  static (Color background, Color foreground) colorsFor(OrderStatus status) =>
      switch (status) {
        OrderStatus.placed => (AppColors.infoSoft, AppColors.info),
        OrderStatus.preparing => (AppColors.warningSoft, AppColors.warning),
        OrderStatus.readyToServe => (AppColors.primarySoft, AppColors.primary),
        OrderStatus.served => (AppColors.successSoft, AppColors.success),
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = colorsFor(status);
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: AppRadii.pill),
      child: Text(
        status.shortLabel,
        style: AppTypography.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Currency text that counts smoothly to its new value.
class AnimatedMoneyText extends StatelessWidget {
  const AnimatedMoneyText(this.amount, {super.key, required this.style});

  final Money amount;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: amount.paise, end: amount.paise),
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      builder: (context, value, _) {
        // Show whole rupees while counting so decimals don't flicker.
        final shown = value == amount.paise
            ? amount
            : Money((value / 100).round() * 100);
        return Text(
          CurrencyFormatter.format(shown),
          style: style,
          semanticsLabel: CurrencyFormatter.format(amount),
        );
      },
    );
  }
}

/// Subtotal, tax and total rows.
class BillSummary extends StatelessWidget {
  const BillSummary({super.key, required this.bill, this.showTotal = true});

  final BillBreakdown bill;
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BillRow(label: 'Subtotal', amount: bill.subtotal),
        const SizedBox(height: AppSpacing.sm),
        BillRow(label: bill.taxLabel, amount: bill.tax),
        if (showTotal) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: DashedDivider(),
          ),
          BillRow(label: 'Total Amount', amount: bill.total, emphasized: true),
        ],
      ],
    );
  }
}

class BillRow extends StatelessWidget {
  const BillRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final Money amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final labelStyle = emphasized
        ? AppTypography.sectionTitle
        : AppTypography.bodySecondary.copyWith(fontSize: 13.5);
    final amountStyle = emphasized
        ? AppTypography.sectionTitle.copyWith(fontWeight: FontWeight.w700)
        : AppTypography.body.copyWith(fontSize: 13.5);
    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        AnimatedMoneyText(amount, style: amountStyle),
      ],
    );
  }
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color = const Color(0xFFE2E2E2)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 5.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: dash,
              height: 1.2,
              child: ColoredBox(color: color),
            ),
          ),
        );
      },
    );
  }
}
