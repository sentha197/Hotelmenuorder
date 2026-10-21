import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/billing.dart';
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
        OrderStatus.accepted => (AppColors.orangeSoft, AppColors.orangeText),
        OrderStatus.preparing => (AppColors.warningSoft, AppColors.warning),
        OrderStatus.readyToServe => (AppColors.primarySoft, AppColors.primary),
        OrderStatus.served => (AppColors.successSoft, AppColors.success),
        OrderStatus.cancelled => (AppColors.softWhite, AppColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = colorsFor(status);
    return _Pill(
      label: status.shortLabel,
      background: background,
      foreground: foreground,
    );
  }
}

/// Coloured pill showing a bill's payment status.
class PaymentStatusBadge extends StatelessWidget {
  const PaymentStatusBadge({super.key, required this.status});

  final InvoiceStatus status;

  static (Color background, Color foreground) colorsFor(InvoiceStatus status) =>
      switch (status) {
        InvoiceStatus.unpaid => (AppColors.primarySoft, AppColors.primary),
        InvoiceStatus.pending => (AppColors.infoSoft, AppColors.info),
        InvoiceStatus.partiallyPaid => (
          AppColors.orangeSoft,
          AppColors.orangeText,
        ),
        InvoiceStatus.paid => (AppColors.successSoft, AppColors.success),
        InvoiceStatus.failed => (AppColors.primarySoft, AppColors.error),
        InvoiceStatus.partiallyRefunded ||
        InvoiceStatus.refunded => (AppColors.warningSoft, AppColors.warning),
        InvoiceStatus.voided => (AppColors.softWhite, AppColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = colorsFor(status);
    return _Pill(
      label: status.label,
      background: background,
      foreground: foreground,
      icon: switch (status) {
        InvoiceStatus.paid => Icons.check_circle_rounded,
        InvoiceStatus.pending => Icons.hourglass_top_rounded,
        InvoiceStatus.failed => Icons.error_rounded,
        _ => null,
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: AppRadii.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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

/// Subtotal, discount, charges, tax and total rows; optionally what was
/// paid and the balance due.
class BillSummary extends StatelessWidget {
  const BillSummary({
    super.key,
    required this.bill,
    this.showTotal = true,
    this.paid,
    this.refunded,
    this.outstanding,
  });

  final BillBreakdown bill;
  final bool showTotal;
  final Money? paid;
  final Money? refunded;
  final Money? outstanding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BillRow(label: 'Subtotal', amount: bill.subtotal),
        if (bill.hasDiscount) ...[
          const SizedBox(height: AppSpacing.sm),
          BillRow(
            label: bill.discountLabel ?? 'Discount',
            amount: bill.discount,
            negative: true,
            color: AppColors.success,
          ),
        ],
        if (bill.hasServiceCharge) ...[
          const SizedBox(height: AppSpacing.sm),
          BillRow(label: bill.serviceChargeLabel, amount: bill.serviceCharge),
        ],
        const SizedBox(height: AppSpacing.sm),
        BillRow(label: bill.taxLabel, amount: bill.tax),
        if (showTotal) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: DashedDivider(),
          ),
          BillRow(label: 'Total Amount', amount: bill.total, emphasized: true),
        ],
        if (paid != null) ...[
          const SizedBox(height: AppSpacing.sm),
          BillRow(label: 'Paid', amount: paid!, color: AppColors.success),
        ],
        if (refunded != null && !refunded!.isZero) ...[
          const SizedBox(height: AppSpacing.sm),
          BillRow(
            label: 'Refunded',
            amount: refunded!,
            negative: true,
            color: AppColors.warning,
          ),
        ],
        if (outstanding != null) ...[
          const SizedBox(height: AppSpacing.sm),
          BillRow(
            label: 'Balance due',
            amount: outstanding!,
            emphasized: !outstanding!.isZero,
            color: outstanding!.isZero ? AppColors.success : AppColors.primary,
          ),
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
    this.negative = false,
    this.color,
  });

  final String label;
  final Money amount;
  final bool emphasized;
  final bool negative;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final labelStyle = emphasized
        ? AppTypography.sectionTitle
        : AppTypography.bodySecondary.copyWith(fontSize: 13.5);
    var amountStyle = emphasized
        ? AppTypography.sectionTitle.copyWith(fontWeight: FontWeight.w700)
        : AppTypography.body.copyWith(fontSize: 13.5);
    if (color != null) amountStyle = amountStyle.copyWith(color: color);
    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        if (negative) Text('− ', style: amountStyle),
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
