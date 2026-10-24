import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';

enum _Stage { form, processing, success, failed, cancelled }

/// Pays all or part of a bill through the configured payment provider.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountField = TextEditingController();
  _Stage _stage = _Stage.form;
  PaymentMethodType? _method;
  bool _payFull = true;
  String? _amountError;
  SimulatedOutcome _outcome = SimulatedOutcome.success;
  PaymentTransaction? _result;
  String? _message;

  @override
  void dispose() {
    _amountField.dispose();
    super.dispose();
  }

  Money? _amount(Invoice invoice) => _payFull
      ? invoice.payableNow
      : SettingsController.parseRupees(_amountField.text);

  Future<void> _pay(Invoice invoice) async {
    final billing = context.read<BillingController>();
    final method = _method ?? billing.onlineMethods.first;
    final amount = _amount(invoice);
    if (amount == null) {
      setState(() => _amountError = 'Enter an amount, e.g. 250 or 250.50.');
      return;
    }
    final problem = billing.validateAmount(
      invoice,
      amount,
      allowPartial: billing.allowPartialPayments,
    );
    if (problem != null) {
      setState(() => _amountError = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _Stage.processing;
      _amountError = null;
    });
    try {
      final transaction = await billing.payOnline(
        invoiceId: invoice.id,
        amount: amount,
        method: method,
        outcome: _outcome,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = transaction;
        _message = transaction.failureReason;
        _stage = switch (transaction.status) {
          PaymentStatus.succeeded => _Stage.success,
          PaymentStatus.cancelled => _Stage.cancelled,
          _ => _Stage.failed,
        };
      });
    } on PaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message = error.message;
      });
    }
  }

  void _retry() => setState(() {
    _stage = _Stage.form;
    _result = null;
    _message = null;
  });

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final invoice = billing.byId(widget.invoiceId);
    final processing = _stage == _Stage.processing;
    final canPay =
        invoice != null &&
        _stage == _Stage.form &&
        billing.onlinePaymentsAvailable &&
        !invoice.payableNow.isZero;
    return PopScope(
      // Leaving mid-payment could hide its result.
      canPop: !processing,
      child: Scaffold(
        appBar: AppBar(
          leading: processing ? const SizedBox.shrink() : const AppBackButton(),
          title: const Text('Payment'),
        ),
        // The pay button stays in reach however long the form is.
        bottomNavigationBar: canPay
            ? DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      AppSpacing.md,
                      AppSpacing.page,
                      AppSpacing.md,
                    ),
                    child: PrimaryButton(
                      label:
                          'Pay ${CurrencyFormatter.format(_amount(invoice) ?? invoice.payableNow)}',
                      icon: Icons.lock_rounded,
                      onPressed: () => _pay(invoice),
                    ),
                  ),
                ),
              )
            : null,
        body: invoice == null
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Bill not found',
                message: 'This bill is no longer on this device.',
              )
            : AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                child: switch (_stage) {
                  _Stage.form => _buildForm(invoice, billing),
                  _Stage.processing => _Processing(
                    key: const ValueKey('processing'),
                    simulated: billing.isSimulated,
                  ),
                  _Stage.success => _Result(
                    key: const ValueKey('success'),
                    success: true,
                    title: 'Payment successful',
                    invoice: invoice,
                    transaction: _result,
                    onPrimary: () => Navigator.of(context).pop(),
                    primaryLabel: 'Done',
                    onSecondary: () => AppNav.openReceipt(context, invoice.id),
                    secondaryLabel: 'View receipt',
                  ),
                  _Stage.failed => _Result(
                    key: const ValueKey('failed'),
                    success: false,
                    title: 'Payment failed',
                    message:
                        _message ??
                        'The payment did not go through. No money was taken.',
                    invoice: invoice,
                    transaction: _result,
                    onPrimary: _retry,
                    primaryLabel: 'Try again',
                    onSecondary: () => Navigator.of(context).pop(),
                    secondaryLabel: 'Back to bill',
                  ),
                  _Stage.cancelled => _Result(
                    key: const ValueKey('cancelled'),
                    success: false,
                    title: 'Payment cancelled',
                    message: 'Nothing was charged. You can try again any time.',
                    invoice: invoice,
                    transaction: _result,
                    onPrimary: _retry,
                    primaryLabel: 'Try again',
                    onSecondary: () => Navigator.of(context).pop(),
                    secondaryLabel: 'Back to bill',
                  ),
                },
              ),
      ),
    );
  }

  Widget _buildForm(Invoice invoice, BillingController billing) {
    final methods = billing.onlineMethods;
    final selected = _method ?? (methods.isEmpty ? null : methods.first);
    final payable = invoice.payableNow;
    final amount = _amount(invoice);
    if (methods.isEmpty || payable.isZero) {
      return EmptyState(
        key: const ValueKey('unavailable'),
        icon: payable.isZero
            ? Icons.check_circle_outline_rounded
            : Icons.storefront_rounded,
        title: payable.isZero ? 'Nothing to pay' : 'Pay at the counter',
        message: payable.isZero
            ? invoice.hasPendingPayment
                  ? 'A payment for this bill is still being confirmed.'
                  : 'This bill has no balance due.'
            : 'Online payment is not available. Staff will take your payment '
                  'and the bill will update automatically.',
      );
    }
    return ListView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        if (billing.isSimulated) ...[
          const FadeSlideIn(child: _DemoBanner()),
          const SizedBox(height: AppSpacing.lg),
        ],
        FadeSlideIn(
          index: 1,
          child: _AmountHeader(invoice: invoice, amount: amount ?? payable),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (billing.allowPartialPayments) ...[
          FadeSlideIn(
            index: 2,
            child: Text('Amount', style: AppTypography.sectionTitle),
          ),
          const SizedBox(height: AppSpacing.sm),
          FadeSlideIn(
            index: 2,
            child: _AmountChoice(
              payable: payable,
              payFull: _payFull,
              controller: _amountField,
              error: _amountError,
              onFull: (full) => setState(() {
                _payFull = full;
                _amountError = null;
              }),
              onChanged: () => setState(() => _amountError = null),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        FadeSlideIn(
          index: 3,
          child: Text('Pay with', style: AppTypography.sectionTitle),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final (index, method) in methods.indexed)
          FadeSlideIn(
            index: 3 + index,
            child: _MethodTile(
              method: method,
              selected: method == selected,
              simulated: billing.isSimulated,
              onTap: () => setState(() => _method = method),
            ),
          ),
        if (billing.isSimulated) ...[
          const SizedBox(height: AppSpacing.lg),
          FadeSlideIn(
            index: 8,
            child: _OutcomePicker(
              value: _outcome,
              onChanged: (outcome) => setState(() => _outcome = outcome),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          billing.isSimulated
              ? 'Demo mode: payments are simulated by DineQR and never reach a '
                    'bank. No money is charged.'
              : 'Payments are processed by ${billing.gateway.providerName}. '
                    'The bill updates only after the payment is verified.',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Demo payment: nothing will be charged. Use it to try the '
              'payment flow.',
              style: AppTypography.label.copyWith(color: AppColors.info),
            ),
          ),
          const DemoTag(),
        ],
      ),
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.invoice, required this.amount});

  final Invoice invoice;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          const BoxShadow(color: AppColors.panelLip, offset: Offset(0, 3)),
          BoxShadow(
            color: AppColors.deepRed.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: BrandPanel(
        watermark: true,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AMOUNT TO PAY',
              style: AppTypography.overline.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            LayeredGradientText(
              CurrencyFormatter.format(amount),
              style: AppTypography.display.copyWith(
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, AppColors.peach],
              ),
              baseColor: AppColors.depthOnRed,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bill ${invoice.billNumber} · ${invoice.tableLabel} · '
              'Total ${CurrencyFormatter.format(invoice.total)}',
              style: AppTypography.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            if (!invoice.amountPaid.isZero)
              Text(
                'Already paid ${CurrencyFormatter.format(invoice.amountPaid)}',
                style: AppTypography.caption.copyWith(color: AppColors.peach),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountChoice extends StatelessWidget {
  const _AmountChoice({
    required this.payable,
    required this.payFull,
    required this.controller,
    required this.error,
    required this.onFull,
    required this.onChanged,
  });

  final Money payable;
  final bool payFull;
  final TextEditingController controller;
  final String? error;
  final ValueChanged<bool> onFull;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(bool full, String title, String subtitle) => Expanded(
      child: Pressable(
        onTap: () => onFull(full),
        scale: 0.97,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: payFull == full ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: payFull == full ? AppColors.primary : AppColors.border,
              width: payFull == full ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.cardTitle),
              Text(subtitle, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            option(true, 'Full balance', CurrencyFormatter.format(payable)),
            const SizedBox(width: AppSpacing.md),
            option(false, 'Part payment', 'Pay the rest later'),
          ],
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.medium),
          child: payFull
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      hintText:
                          'Amount (up to ${CurrencyFormatter.format(payable)})',
                      errorText: error,
                    ),
                  ),
                ),
        ),
        if (payFull && error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              error!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.simulated,
    required this.onTap,
  });

  final PaymentMethodType method;
  final bool selected;
  final bool simulated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Pressable(
          onTap: onTap,
          scale: 0.98,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.medium),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadii.card,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected ? AppShadows.soft : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primarySoft
                        : AppColors.softWhite,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    method.icon,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(method.label, style: AppTypography.cardTitle),
                ),
                if (simulated) ...[
                  const DemoTag(label: 'SIMULATED'),
                  const SizedBox(width: AppSpacing.sm),
                ],
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.fast),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    key: ValueKey(selected),
                    color: selected ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomePicker extends StatelessWidget {
  const _OutcomePicker({required this.value, required this.onChanged});

  final SimulatedOutcome value;
  final ValueChanged<SimulatedOutcome> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.softWhite,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DemoTag(),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Simulated result',
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final outcome in SimulatedOutcome.values)
                ChoiceChip(
                  label: Text(outcome.label),
                  selected: value == outcome,
                  onSelected: (_) => onChanged(outcome),
                  selectedColor: AppColors.primarySoft,
                  labelStyle: AppTypography.label.copyWith(
                    color: value == outcome
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: value == outcome
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                  showCheckmark: false,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key, required this.simulated});

  final bool simulated;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DineQrMark(size: 96, sheen: 0.5),
            const SizedBox(height: AppSpacing.xl),
            const QrPulseLoader(
              size: 30,
              color: AppColors.primary,
              semanticLabel: 'Confirming payment',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Confirming your payment…', style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              simulated
                  ? 'The demo simulator is processing it. No money moves.'
                  : 'Please keep this screen open.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    super.key,
    required this.success,
    required this.title,
    required this.invoice,
    required this.transaction,
    required this.onPrimary,
    required this.primaryLabel,
    required this.onSecondary,
    required this.secondaryLabel,
    this.message,
  });

  final bool success;
  final String title;
  final String? message;
  final Invoice invoice;
  final PaymentTransaction? transaction;
  final VoidCallback onPrimary;
  final String primaryLabel;
  final VoidCallback onSecondary;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: success
              ? const SuccessEmblem(
                  size: 96,
                  semanticLabel: 'Payment successful',
                )
              : const IconHalo(icon: Icons.error_outline_rounded),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title, textAlign: TextAlign.center, style: AppTypography.headline),
        const SizedBox(height: AppSpacing.sm),
        if (message != null && message!.isNotEmpty)
          Text(
            message!,
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        if (success && t != null) ...[
          Text(
            '${CurrencyFormatter.format(t.amount)} paid by ${t.method.label}',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              children: [
                _Fact('Reference', t.reference.isEmpty ? '—' : t.reference),
                _Fact('Bill', invoice.billNumber),
                _Fact('Paid at', AppFormat.dateTime(t.updatedAt)),
                _Fact(
                  'Balance due',
                  CurrencyFormatter.format(invoice.outstanding),
                ),
                if (t.isSimulated) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Simulated demo payment. No money was charged.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.info,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Center(child: PaymentStatusBadge(status: invoice.status)),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: primaryLabel, onPressed: onPrimary),
        const SizedBox(height: AppSpacing.md),
        SecondaryButton(label: secondaryLabel, onPressed: onSecondary),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
