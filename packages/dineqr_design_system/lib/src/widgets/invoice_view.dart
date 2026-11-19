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
    this.paymentActions,
  });

  final Invoice invoice;

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
                          // Shrinks rather than overflows beside a long
                          // status such as "Pending verification".
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: DineQrLockup(height: 26),
                          ),
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
                              ? (invoice.hasDemoPayments
                                    ? 'TEST RECEIPT'
                                    : 'RECEIPT')
                              : 'BILL',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        PaymentStatusBadge(status: invoice.status),
                        // Never shown as a verified payment.
                        if (invoice.hasDemoPayments) ...[
                          const SizedBox(height: 4),
                          const DemoTag(label: 'TEST PAYMENT'),
                        ],
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
                    tag: invoice.isDemoSample ? 'DEMO' : 'TEST',
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
    this.trailing,
  });

  final PaymentTransaction payment;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (payment.status) {
      PaymentStatus.succeeded => (AppColors.success, 'Successful'),
      PaymentStatus.pending => (AppColors.info, 'Pending'),
      PaymentStatus.failed => (AppColors.error, 'Failed'),
      PaymentStatus.cancelled => (AppColors.textSecondary, 'Cancelled'),
    };
    final handledBy = payment.recordedBy.isEmpty
        ? null
        : 'Recorded by ${payment.recordedBy}';
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
                  '${payment.methodLabel} · $label',
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
                      // Typed by the guest and not checked by anyone yet.
                      'Ref ${payment.reference}',
                    ?handledBy,
                    if (payment.isSimulated) 'Test payment (no money moved)',
                  ].join(' · '),
                  style: AppTypography.caption,
                ),
                if (payment.failureReason.isNotEmpty &&
                    payment.status != PaymentStatus.succeeded)
                  Text(
                    payment.failureReason,
                    style: AppTypography.caption.copyWith(color: color),
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
                  '${refund.status.label}${refund.isSimulated ? ' (test)' : ''}',
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
  const _Notice({
    required this.icon,
    required this.text,
    this.demo = false,
    this.tag = 'DEMO',
  });

  final IconData icon;
  final String text;
  final bool demo;

  /// The pill shown with a [demo] notice.
  final String tag;

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
          if (demo) DemoTag(label: tag),
        ],
      ),
    );
  }
}
