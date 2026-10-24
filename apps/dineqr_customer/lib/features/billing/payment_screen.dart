import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import 'demo_checkout_sheet.dart';

enum _Stage { choose, processing, success, failed, cancelled, counter }

/// Pays all or part of a bill: online (through the payment provider, or
/// the simulator in demo mode), in cash or at the counter, or split across
/// several of them.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountField = TextEditingController();
  _Stage _stage = _Stage.choose;
  PaymentOption? _option;
  bool _payFull = true;
  String? _amountError;
  PaymentTransaction? _result;
  String? _message;

  /// Reused when an attempt is retried after its result never arrived, so
  /// the server returns that attempt instead of charging again. Cleared
  /// once an attempt has a final result or the request changes.
  String? _attemptKey;

  @override
  void dispose() {
    _amountField.dispose();
    super.dispose();
  }

  Money? _amount(Invoice invoice) => _payFull
      ? invoice.payableNow
      : SettingsController.parseRupees(_amountField.text);

  void _select(PaymentOption option) => setState(() {
    _option = option;
    _attemptKey = null;
    _amountError = null;
  });

  Future<void> _pay(Invoice invoice, PaymentOption option) async {
    final billing = context.read<BillingController>();
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
    if (!option.isOnline) return _payAtCounter(invoice, option, amount);

    var outcome = SimulatedOutcome.success;
    var detail = option.detail;
    if (billing.isSimulated) {
      // The demo checkout: the payment is made only once the guest confirms.
      final checkout = await showDemoCheckout(
        context,
        option: option,
        amount: amount,
        invoice: invoice,
      );
      if (checkout == null || !mounted) return;
      outcome = checkout.outcome;
      detail = checkout.detail;
    }
    setState(() {
      _stage = _Stage.processing;
      _amountError = null;
    });
    try {
      final transaction = await billing.payOnline(
        invoiceId: invoice.id,
        amount: amount,
        method: option.method!,
        methodDetail: detail,
        idempotencyKey: _attemptKey ??= Ids.random(),
        outcome: outcome,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _attemptKey = null;
        _result = transaction;
        _message = transaction.failureReason;
        _stage = switch (transaction.status) {
          PaymentStatus.succeeded => _Stage.success,
          PaymentStatus.cancelled => _Stage.cancelled,
          _ => _Stage.failed,
        };
      });
    } on PaymentException catch (error) {
      // The key is kept: trying again replays this attempt.
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _result = null;
        _message = error.message;
      });
    }
  }

  Future<void> _payAtCounter(
    Invoice invoice,
    PaymentOption option,
    Money amount,
  ) async {
    final billing = context.read<BillingController>();
    setState(() => _stage = _Stage.processing);
    try {
      await billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: option.counter!,
        amount: amount,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _stage = _Stage.counter);
    } on PaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.choose;
        _amountError = error.message;
      });
    }
  }

  Future<void> _payOnlineInstead(Invoice invoice) async {
    try {
      await context.read<BillingController>().cancelCounterRequest(invoice.id);
    } on PaymentException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
    }
    if (mounted) _retry();
  }

  void _retry() => setState(() {
    _stage = _Stage.choose;
    _result = null;
    _message = null;
  });

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final invoice = billing.byId(widget.invoiceId);
    final processing = _stage == _Stage.processing;
    final options = billing.paymentOptions;
    final selected = options.contains(_option) ? _option : null;
    final canPay =
        invoice != null &&
        _stage == _Stage.choose &&
        !invoice.payableNow.isZero &&
        selected != null;
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
            ? _PayButtonBar(
                label: _payLabel(selected, _amount(invoice)),
                icon: selected.isOnline
                    ? Icons.lock_rounded
                    : Icons.storefront_rounded,
                onPressed: () => _pay(invoice, selected),
              )
            : null,
        body: invoice == null
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Bill not found',
                message: 'This bill is no longer on this device.',
              )
            : _Constrained(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  child: switch (_stage) {
                    _Stage.choose => _buildChoose(invoice, billing),
                    _Stage.processing => _Processing(
                      key: const ValueKey('processing'),
                      simulated: billing.isSimulated,
                      counter: !(selected?.isOnline ?? true),
                    ),
                    _Stage.success => _Result(
                      key: const ValueKey('success'),
                      success: true,
                      title: _result?.isSimulated ?? false
                          ? 'Demo payment successful'
                          : 'Payment successful',
                      invoice: invoice,
                      transaction: _result,
                      onPrimary: () => Navigator.of(context).pop(),
                      primaryLabel: 'Done',
                      onSecondary: () =>
                          AppNav.openReceipt(context, invoice.id),
                      secondaryLabel: 'View, print or share receipt',
                    ),
                    _Stage.failed => _Result(
                      key: const ValueKey('failed'),
                      success: false,
                      title: 'Payment failed',
                      // Server reasons say whether money moved; an
                      // unconfirmed attempt says it will not charge twice.
                      message: _message?.isNotEmpty ?? false
                          ? _message
                          : 'The payment did not go through. No money was '
                                'taken.',
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
                      message:
                          'Nothing was charged. You can try again any time.',
                      invoice: invoice,
                      transaction: _result,
                      onPrimary: _retry,
                      primaryLabel: 'Try again',
                      onSecondary: () => Navigator.of(context).pop(),
                      secondaryLabel: 'Back to bill',
                    ),
                    _Stage.counter => _CounterResult(
                      key: const ValueKey('counter'),
                      invoice: invoice,
                      simulated: billing.isSimulated,
                      onDone: () => Navigator.of(context).pop(),
                      onPayOnline: billing.onlinePaymentsAvailable
                          ? () => _payOnlineInstead(invoice)
                          : null,
                    ),
                  },
                ),
              ),
      ),
    );
  }

  static String _payLabel(PaymentOption option, Money? amount) {
    final value = amount == null ? '' : ' ${CurrencyFormatter.format(amount)}';
    return switch (option) {
      PaymentOption.cash => 'Pay$value in cash',
      PaymentOption.payAtCounter => 'Pay$value at the counter',
      _ => 'Pay$value with ${option.label}',
    };
  }

  Widget _buildChoose(Invoice invoice, BillingController billing) {
    final payable = invoice.payableNow;
    if (payable.isZero) {
      return EmptyState(
        key: const ValueKey('nothing'),
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing to pay',
        message: invoice.hasPendingPayment
            ? 'A payment for this bill is still being confirmed.'
            : 'This bill has no balance due.',
      );
    }
    final options = billing.paymentOptions;
    final amount = _amount(invoice);
    var index = 0;
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
          FadeSlideIn(index: index++, child: const _DemoBanner()),
          const SizedBox(height: AppSpacing.lg),
        ],
        FadeSlideIn(
          index: index++,
          child: _AmountHeader(invoice: invoice, amount: amount ?? payable),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (billing.allowPartialPayments) ...[
          Text('Amount', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          _AmountChoice(
            payable: payable,
            payFull: _payFull,
            controller: _amountField,
            error: _amountError,
            onFull: (full) => setState(() {
              _payFull = full;
              _amountError = null;
              _attemptKey = null;
            }),
            onChanged: () => setState(() {
              _amountError = null;
              _attemptKey = null;
            }),
          ),
          const SizedBox(height: AppSpacing.xl),
        ] else if (_amountError != null) ...[
          Text(
            _amountError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Choose how to pay', style: AppTypography.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        if (!billing.onlinePaymentsAvailable) ...[
          Text(
            'Online payment is not available right now. Pay in cash or at '
            'the counter; staff record it and this bill updates.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _OptionGrid(
          options: options,
          selected: _option,
          simulated: billing.isSimulated,
          onSelect: _select,
        ),
        if (billing.canSplit && billing.onlinePaymentsAvailable) ...[
          const SizedBox(height: AppSpacing.md),
          _SplitCard(onTap: () => AppNav.openSplitPayment(context, invoice.id)),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          billing.isSimulated
              ? 'Demo mode: payments are simulated by DineQR and never reach a '
                    'bank. No money is charged, and every payment is labelled '
                    'as a demo.'
              : 'Payments are processed by ${billing.gateway.providerName}. '
                    'The bill updates only after the payment is verified.',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

/// Keeps content readable on tablets and desktops: centred, at most 640
/// wide, never scrolling sideways.
class _Constrained extends StatelessWidget {
  const _Constrained({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}

class _PayButtonBar extends StatelessWidget {
  const _PayButtonBar({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.md,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: PrimaryButton(
                label: label,
                icon: icon,
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
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
                'Already paid ${CurrencyFormatter.format(invoice.amountPaid)}'
                '${invoice.hasDemoPayments ? ' (demo)' : ''}',
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
                      prefixText: '${CurrencyFormatter.symbol} ',
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

/// The payment options as cards: two columns on phones, more on wider
/// screens.
class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.options,
    required this.selected,
    required this.simulated,
    required this.onSelect,
  });

  final List<PaymentOption> options;
  final PaymentOption? selected;
  final bool simulated;
  final ValueChanged<PaymentOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Semantics(
          container: true,
          label: 'Payment options',
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (index, option) in options.indexed)
                SizedBox(
                  width: width,
                  child: FadeSlideIn(
                    index: index,
                    child: _OptionCard(
                      option: option,
                      selected: option == selected,
                      demo: simulated && option.isOnline,
                      onTap: () => onSelect(option),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selected,
    required this.demo,
    required this.onTap,
  });

  final PaymentOption option;
  final bool selected;
  final bool demo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : Colors.white,
            borderRadius: AppRadii.card,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected ? AppShadows.soft : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : AppColors.softWhite,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(
                      option.icon,
                      size: 20,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 20,
                    color: selected ? AppColors.primary : AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(option.label, style: AppTypography.cardTitle),
              Text(
                option.description,
                style: AppTypography.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (demo) ...[
                const SizedBox(height: AppSpacing.xs),
                const DemoTag(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.card,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: const Icon(
                Icons.call_split_rounded,
                size: 20,
                color: AppColors.orangeText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Split payment', style: AppTypography.cardTitle),
                  Text(
                    'Pay with two or more methods, e.g. cash + UPI',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key, required this.simulated, this.counter = false});

  final bool simulated;
  final bool counter;

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
            QrPulseLoader(
              size: 30,
              color: AppColors.primary,
              semanticLabel: counter
                  ? 'Letting staff know'
                  : 'Confirming payment',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              counter
                  ? 'Letting the staff know…'
                  : simulated
                  ? 'Confirming your demo payment…'
                  : 'Confirming your payment…',
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              counter
                  ? 'Nothing is charged here.'
                  : simulated
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
              ? SuccessEmblem(size: 96, semanticLabel: title)
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
            '${CurrencyFormatter.format(t.amount)} paid by ${t.methodLabel}',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.isSimulated) ...[
                  const DemoTag(label: 'DEMO PAYMENT'),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _Fact(
                  t.isSimulated ? 'Demo transaction ref' : 'Reference',
                  t.reference.isEmpty ? '—' : t.reference,
                ),
                _Fact('Method', t.methodLabel),
                _Fact('Amount', CurrencyFormatter.format(t.amount)),
                _Fact('Bill', invoice.billNumber),
                _Fact('Paid at', AppFormat.dateTime(t.updatedAt)),
                _Fact(
                  'Balance due',
                  CurrencyFormatter.format(invoice.outstanding),
                ),
                if (t.isSimulated) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Simulated demo payment, not verified by any bank or '
                    'payment provider. No money was charged or transferred.',
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

/// After choosing cash or the counter: what happens next.
class _CounterResult extends StatelessWidget {
  const _CounterResult({
    super.key,
    required this.invoice,
    required this.simulated,
    required this.onDone,
    required this.onPayOnline,
  });

  final Invoice invoice;
  final bool simulated;
  final VoidCallback onDone;
  final VoidCallback? onPayOnline;

  @override
  Widget build(BuildContext context) {
    final request = invoice.openCounterRequest;
    final cash = request?.kind == CounterRequestKind.cash;
    final amount = CurrencyFormatter.format(
      request?.amount ?? invoice.payableNow,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: IconHalo(
            icon: cash ? Icons.payments_rounded : Icons.storefront_rounded,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          cash ? 'Pay $amount in cash' : 'Pay $amount at the counter',
          textAlign: TextAlign.center,
          style: AppTypography.headline,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          cash
              ? 'Hand the cash to your server or pay at the counter. Staff '
                    'have been told.'
              : 'Pay at the counter by any method they take. Staff have been '
                    'told.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact('Bill', invoice.billNumber),
              _Fact('To pay at the counter', amount),
              _Fact('Status', invoice.status.label),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Nothing has been paid yet. The bill updates here as soon as '
                'the cashier records your payment.'
                '${simulated ? ' In demo mode their record is a demo payment '
                          'too.' : ''}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(child: PaymentStatusBadge(status: invoice.status)),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: 'Back to bill', onPressed: onDone),
        if (onPayOnline != null) ...[
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(label: 'Pay online instead', onPressed: onPayOnline),
        ],
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
