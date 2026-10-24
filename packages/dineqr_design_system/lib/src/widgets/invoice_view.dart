import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';

import '../brand/dineqr_logo.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'app_buttons.dart';
import 'order_widgets.dart';

extension PaymentMethodIcon on PaymentMethodType {
  IconData get icon => switch (this) {
    PaymentMethodType.upi => Icons.phone_iphone_rounded,
    PaymentMethodType.card => Icons.credit_card_rounded,
    PaymentMethodType.netBanking => Icons.account_balance_rounded,
    PaymentMethodType.wallet => Icons.account_balance_wallet_rounded,
    PaymentMethodType.cash => Icons.payments_rounded,
  };
}

/// A bill laid out like a printed invoice. Used by guests and staff.
class InvoiceView extends StatelessWidget {
  const InvoiceView({
    super.key,
    required this.invoice,
    this.onCheckPending,
    this.paymentActions,
  });

  final Invoice invoice;

  /// Shown on pending payments ("Check status").
  final VoidCallback? onCheckPending;

  /// Extra trailing widget per payment (e.g. staff refund button).
  final Widget? Function(PaymentTransaction payment)? paymentActions;

  @override
  Widget build(BuildContext context) {
    final r = invoice.restaurant;
    final contact = [r.phone, r.email].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 6,
            decoration: const BoxDecoration(gradient: AppColors.emberGradient),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const DineQrLockup(height: 26),
                          const SizedBox(height: AppSpacing.sm),
                          Text(r.name, style: AppTypography.cardTitle),
                          if (r.address.isNotEmpty)
                            Text(r.address, style: AppTypography.caption),
                          if (contact.isNotEmpty)
                            Text(contact, style: AppTypography.caption),
                          if (r.taxRegistration.isNotEmpty)
                            Text(
                              'Tax registration: ${r.taxRegistration}',
                              style: AppTypography.caption,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          invoice.status == InvoiceStatus.paid
                              ? 'RECEIPT'
                              : 'BILL',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        PaymentStatusBadge(status: invoice.status),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _MetaGrid(
                  entries: [
                    ('Bill no.', invoice.billNumber),
                    ('Order', AppFormat.orderNumber(invoice.orderId)),
                    if (invoice.isTakeaway)
                      ('Type', 'Takeaway')
                    else
                      ('Table', AppFormat.table(invoice.tableNumber)),
                    ('Date', AppFormat.dateTime(invoice.createdAt)),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: DashedDivider(),
                ),
                for (final line in invoice.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.name,
                                style: AppTypography.label.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  '${line.quantity} × '
                                      '${CurrencyFormatter.format(line.unitPrice)}',
                                  ...line.options,
                                ].join(' · '),
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(line.lineTotal),
                          style: AppTypography.label.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: DashedDivider(),
                ),
                BillSummary(
                  bill: invoice.amounts,
                  paid: invoice.amountPaid,
                  refunded: invoice.amountRefunded,
                  outstanding: invoice.outstanding,
                ),
                if (invoice.payments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text('Payments', style: AppTypography.cardTitle),
                  const SizedBox(height: AppSpacing.sm),
                  for (final payment in invoice.payments.reversed)
                    PaymentRow(
                      payment: payment,
                      onCheckStatus: payment.status == PaymentStatus.pending
                          ? onCheckPending
                          : null,
                      trailing: paymentActions?.call(payment),
                    ),
                ],
                if (invoice.refunds.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Refunds', style: AppTypography.cardTitle),
                  const SizedBox(height: AppSpacing.sm),
                  for (final refund in invoice.refunds)
                    _RefundRow(refund: refund),
                ],
                if (invoice.isVoid) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Notice(
                    icon: Icons.block_rounded,
                    text:
                        'Void: the order was cancelled'
                        '${invoice.voidReason.isEmpty ? '' : ' (${invoice.voidReason})'}.'
                        '${invoice.refundDue ? ' A refund is due.' : ''}',
                  ),
                ],
                if (invoice.demoNotice case final notice?) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _Notice(
                    icon: Icons.science_outlined,
                    text: notice,
                    demo: true,
                  ),
                ],
                if (r.footer.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    r.footer,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySecondary,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: AppSpacing.sm,
      children: [
        for (final (label, value) in entries)
          FractionallySizedBox(
            widthFactor: 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption),
                Text(
                  value,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One payment attempt with status, method, time and reference.
class PaymentRow extends StatelessWidget {
  const PaymentRow({
    super.key,
    required this.payment,
    this.onCheckStatus,
    this.trailing,
  });

  final PaymentTransaction payment;
  final VoidCallback? onCheckStatus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (payment.status) {
      PaymentStatus.succeeded => (AppColors.success, 'Successful'),
      PaymentStatus.pending => (AppColors.info, 'Awaiting confirmation'),
      PaymentStatus.failed => (AppColors.error, 'Failed'),
      PaymentStatus.cancelled => (AppColors.textSecondary, 'Cancelled'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(payment.method.icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${payment.method.label} · $label',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: payment.status == PaymentStatus.succeeded
                        ? AppColors.textPrimary
                        : color,
                  ),
                ),
                Text(
                  [
                    AppFormat.dateTime(payment.updatedAt),
                    if (payment.reference.isNotEmpty)
                      'Ref ${payment.reference}',
                    if (payment.recordedBy.isNotEmpty)
                      'Recorded by ${payment.recordedBy}',
                    if (payment.isSimulated) 'Simulated',
                  ].join(' · '),
                  style: AppTypography.caption,
                ),
                if (payment.failureReason.isNotEmpty &&
                    payment.status != PaymentStatus.succeeded)
                  Text(
                    payment.failureReason,
                    style: AppTypography.caption.copyWith(color: color),
                  ),
                if (onCheckStatus != null)
                  TextButton.icon(
                    onPressed: onCheckStatus,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: AppColors.primary,
                      textStyle: AppTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check status'),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.format(payment.amount),
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration:
                      payment.status == PaymentStatus.succeeded ||
                          payment.status == PaymentStatus.pending
                      ? null
                      : TextDecoration.lineThrough,
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow({required this.refund});

  final RefundRecord refund;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.undo_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${refund.status.label}${refund.isSimulated ? ' (simulated)' : ''}',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    AppFormat.dateTime(refund.createdAt),
                    refund.reason,
                    if (refund.processedBy.isNotEmpty)
                      'By ${refund.processedBy}',
                  ].join(' · '),
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Text(
            '− ${CurrencyFormatter.format(refund.amount)}',
            style: AppTypography.label.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.demo = false});

  final IconData icon;
  final String text;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final color = demo ? AppColors.info : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: demo ? AppColors.infoSoft : AppColors.softWhite,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(color: color),
            ),
          ),
          if (demo) const DemoTag(),
        ],
      ),
    );
  }
}
