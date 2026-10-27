import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'demo_checkout_sheet.dart';

enum _PartStatus { planned, paid, failed, atCounter }

/// One part of the plan while it is edited and paid.
class _Part {
  _Part(this.option, Money amount)
    : amount = TextEditingController(text: CurrencyFormatter.plain(amount));

  PaymentOption option;
  final TextEditingController amount;
  _PartStatus status = _PartStatus.planned;

  /// This part's payment request. Kept when its result never arrived (a
  /// retry replays it); replaced after a final failure.
  String key = Ids.random();
  PaymentTransaction? payment;
  String? message;

  Money? get value => SettingsController.parseRupees(amount.text);

  SplitPart? get plan => switch (value) {
    final money? => SplitPart(option, money),
    null => null,
  };

  bool get done =>
      status == _PartStatus.paid || status == _PartStatus.atCounter;
}

/// Splits a bill across several payment options, e.g. part by UPI and the
/// rest in cash. Online parts are paid one by one (each confirmed in the
/// demo checkout in demo mode); at most one part is left to pay at the
/// counter, and staff are told about it once the online parts went
/// through. Each part is its own payment record, and the parts never add up
/// to more than the balance.
class SplitPaymentScreen extends StatefulWidget {
  const SplitPaymentScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<SplitPaymentScreen> createState() => _SplitPaymentScreenState();
}

class _SplitPaymentScreenState extends State<SplitPaymentScreen> {
  final List<_Part> _parts = [];
  bool _started = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final billing = context.read<BillingController>();
    final invoice = billing.byId(widget.invoiceId);
    if (invoice == null) return;
    final due = invoice.payableNow;
    final online = billing.splitOptions.firstWhere(
      (o) => o.isOnline,
      orElse: () => PaymentOption.card,
    );
    // Half online (whole rupees), the rest in cash.
    final half = Money((due.paise ~/ 200) * 100);
    _parts
      ..add(_Part(online, half))
      ..add(_Part(PaymentOption.cash, due - half));
  }

  @override
  void dispose() {
    for (final part in _parts) {
      part.amount.dispose();
    }
    super.dispose();
  }

  List<SplitPart>? get _plan {
    final plan = [for (final p in _parts) p.plan];
    return plan.contains(null) ? null : plan.cast<SplitPart>();
  }

  String? _problem(BillingController billing, Invoice invoice) {
    final plan = _plan;
    if (plan == null) return 'Enter an amount for every part, e.g. 250.50.';
    return SplitPlan.validate(
      plan,
      payable: invoice.payableNow,
      available: billing.splitOptions.toSet(),
      allowPartial: billing.allowPartialPayments,
    );
  }

  /// Keeps the last part covering whatever the others leave.
  void _rebalance(Invoice invoice, int changed) {
    if (changed == _parts.length - 1) return;
    var others = Money.zero;
    for (final part in _parts.take(_parts.length - 1)) {
      others += part.value ?? Money.zero;
    }
    final rest = invoice.payableNow - others;
    if (rest.paise >= 0) {
      _parts.last.amount.text = CurrencyFormatter.plain(rest);
    }
  }

  void _add(BillingController billing, Invoice invoice) => setState(() {
    final used = {for (final p in _parts) p.option};
    final option = billing.splitOptions.firstWhere(
      (o) => o.isOnline && !used.contains(o),
      orElse: () => billing.splitOptions.first,
    );
    _parts.insert(_parts.length - 1, _Part(option, Money.zero));
  });

  void _remove(Invoice invoice, _Part part) => setState(() {
    _parts.remove(part);
    part.amount.dispose();
    _rebalance(invoice, 0);
  });

  /// Locks the plan: online parts first (in the guest's order), the counter
  /// part last, as [SplitPlan.ordered].
  void _start(Invoice invoice) {
    FocusScope.of(context).unfocus();
    setState(() {
      _started = true;
      final online = _parts.where((p) => p.option.isOnline).toList();
      final counter = _parts.where((p) => !p.option.isOnline).toList();
      _parts
        ..clear()
        ..addAll([...online, ...counter]);
    });
  }

  _Part? get _next =>
      _parts.where((p) => p.option.isOnline && !p.done).firstOrNull ??
      _parts.where((p) => !p.option.isOnline && !p.done).firstOrNull;

  Future<void> _payNext(Invoice invoice) async {
    final part = _next;
    if (part == null) return;
    if (part.option.isOnline) {
      await _payOnline(invoice, part);
    } else {
      await _payAtCounter(invoice, part);
    }
  }

  Future<void> _payOnline(Invoice invoice, _Part part) async {
    final billing = context.read<BillingController>();
    final amount = part.value!;
    var outcome = SimulatedOutcome.success;
    var detail = part.option.detail;
    if (billing.isSimulated) {
      final checkout = await showDemoCheckout(
        context,
        option: part.option,
        amount: amount,
        invoice: invoice,
      );
      if (checkout == null || !mounted) return;
      outcome = checkout.outcome;
      detail = checkout.detail;
    }
    setState(() => _busy = true);
    try {
      final payment = await billing.payOnline(
        invoiceId: invoice.id,
        amount: amount,
        method: part.option.method!,
        methodDetail: detail,
        idempotencyKey: part.key,
        outcome: outcome,
      );
      part.payment = payment;
      if (payment.status == PaymentStatus.succeeded) {
        part
          ..status = _PartStatus.paid
          ..message = null;
        HapticFeedback.mediumImpact();
      } else {
        part
          ..status = _PartStatus.failed
          ..message = payment.status == PaymentStatus.cancelled
              ? 'Cancelled. Nothing was charged.'
              : (payment.failureReason.isEmpty
                    ? 'Declined. Nothing was charged.'
                    : payment.failureReason)
          // A final result: trying again is a new payment.
          ..key = Ids.random();
      }
    } on PaymentException catch (error) {
      part
        ..status = _PartStatus.failed
        ..message = error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payAtCounter(Invoice invoice, _Part part) async {
    setState(() => _busy = true);
    try {
      await context.read<BillingController>().requestCounterPayment(
        invoiceId: invoice.id,
        kind: part.option.counter!,
        amount: part.value,
      );
      part
        ..status = _PartStatus.atCounter
        ..message = null;
    } on PaymentException catch (error) {
      part
        ..status = _PartStatus.failed
        ..message = error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final invoice = billing.byId(widget.invoiceId);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: _busy ? const SizedBox.shrink() : const AppBackButton(),
          title: const Text('Split payment'),
        ),
        bottomNavigationBar: invoice == null ? null : _bar(billing, invoice),
        body: invoice == null
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Bill not found',
                message: 'This bill is no longer on this device.',
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _started
                      ? _progress(billing, invoice)
                      : _planner(billing, invoice),
                ),
              ),
      ),
    );
  }

  Widget? _bar(BillingController billing, Invoice invoice) {
    final Widget button;
    if (!_started) {
      final problem = _problem(billing, invoice);
      button = PrimaryButton(
        label: 'Start split payment',
        icon: Icons.call_split_rounded,
        onPressed: problem == null ? () => _start(invoice) : null,
      );
    } else if (_next case final next?) {
      final amount = CurrencyFormatter.format(next.value!);
      final number = _parts.indexOf(next) + 1;
      button = PrimaryButton(
        label: next.option.isOnline
            ? '${next.status == _PartStatus.failed ? 'Retry' : 'Pay'} part '
                  '$number: $amount by ${next.option.label}'
            : next.option == PaymentOption.cash
            ? 'Pay $amount in cash at the counter'
            : 'Pay $amount at the counter',
        icon: next.option.isOnline
            ? Icons.lock_rounded
            : Icons.storefront_rounded,
        isLoading: _busy,
        onPressed: _busy ? null : () => _payNext(invoice),
      );
    } else {
      button = PrimaryButton(
        label: 'Back to bill',
        onPressed: () => Navigator.of(context).pop(),
      );
    }
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
              child: button,
            ),
          ),
        ),
      ),
    );
  }

  Widget _planner(BillingController billing, Invoice invoice) {
    final options = billing.splitOptions;
    final plan = _plan;
    final assigned = plan == null ? null : Money.sum(plan.map((p) => p.amount));
    final problem = _problem(billing, invoice);
    return ListView(
      key: const ValueKey('split-plan'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        _Header(invoice: invoice, simulated: billing.isSimulated),
        const SizedBox(height: AppSpacing.xl),
        for (final (index, part) in _parts.indexed) ...[
          _PartEditor(
            number: index + 1,
            part: part,
            options: options,
            onOption: (option) => setState(() => part.option = option),
            onAmount: () => setState(() => _rebalance(invoice, index)),
            onRemove: _parts.length > 2 ? () => _remove(invoice, part) : null,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_parts.length < SplitPlan.maxParts)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _add(billing, invoice),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a method'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Assigned ${assigned == null ? '—' : CurrencyFormatter.format(assigned)}'
          ' of ${CurrencyFormatter.format(invoice.payableNow)}',
          style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
        ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              problem,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Online parts are paid first, one by one. A cash or counter part is '
          'paid at the counter afterwards; the bill updates when staff record '
          'it.',
          style: AppTypography.caption,
        ),
      ],
    );
  }

  Widget _progress(BillingController billing, Invoice invoice) {
    final finished = _next == null;
    final counter = _parts.where((p) => !p.option.isOnline).firstOrNull;
    return ListView(
      key: const ValueKey('split-progress'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        _Header(invoice: invoice, simulated: billing.isSimulated),
        const SizedBox(height: AppSpacing.xl),
        for (final (index, part) in _parts.indexed)
          _PartProgress(number: index + 1, part: part),
        if (finished) ...[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: invoice.status == InvoiceStatus.paid
                ? const SuccessEmblem(size: 80, semanticLabel: 'Bill paid')
                : const IconHalo(icon: Icons.storefront_rounded),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            invoice.status == InvoiceStatus.paid
                ? 'Bill paid in full'
                : 'Online parts paid',
            textAlign: TextAlign.center,
            style: AppTypography.headline,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            counter == null
                ? 'Every part went through.'
                : 'Please pay ${CurrencyFormatter.format(counter.value!)} '
                      '${counter.option == PaymentOption.cash ? 'in cash ' : ''}'
                      'at the counter. Staff have been told, and the bill '
                      'updates when they record it.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Center(child: PaymentStatusBadge(status: invoice.status)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.invoice, required this.simulated});

  final Invoice invoice;
  final bool simulated;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.call_split_rounded, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance due ${CurrencyFormatter.format(invoice.payableNow)}',
                  style: AppTypography.cardTitle,
                ),
                Text(
                  'Bill ${invoice.billNumber} · ${invoice.tableLabel}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          if (simulated) const DemoTag(),
        ],
      ),
    );
  }
}

class _PartEditor extends StatelessWidget {
  const _PartEditor({
    required this.number,
    required this.part,
    required this.options,
    required this.onOption,
    required this.onAmount,
    required this.onRemove,
  });

  final int number;
  final _Part part;
  final List<PaymentOption> options;
  final ValueChanged<PaymentOption> onOption;
  final VoidCallback onAmount;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final method = DropdownButtonFormField<PaymentOption>(
      initialValue: options.contains(part.option) ? part.option : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Method'),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(option.icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (option) {
        if (option != null) onOption(option);
      },
    );
    final amount = TextField(
      controller: part.amount,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onAmount(),
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixText: '${CurrencyFormatter.symbol} ',
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Part $number', style: AppTypography.cardTitle),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove part $number',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 420
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: method),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: 2, child: amount),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      method,
                      const SizedBox(height: AppSpacing.md),
                      amount,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PartProgress extends StatelessWidget {
  const _PartProgress({required this.number, required this.part});

  final int number;
  final _Part part;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (part.status) {
      _PartStatus.paid => (
        AppColors.success,
        part.payment?.isSimulated ?? false ? 'Paid (demo)' : 'Paid',
        Icons.check_circle_rounded,
      ),
      _PartStatus.failed => (
        AppColors.error,
        'Not paid',
        Icons.error_outline_rounded,
      ),
      _PartStatus.atCounter => (
        AppColors.info,
        'Pay at the counter',
        Icons.storefront_rounded,
      ),
      _PartStatus.planned => (
        AppColors.textSecondary,
        'To pay',
        Icons.radio_button_unchecked_rounded,
      ),
    };
    final reference = part.payment?.reference ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(part.option.icon, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Part $number · ${part.payment?.methodLabel ?? part.option.label}',
                    style: AppTypography.cardTitle,
                  ),
                  Text(
                    [
                      CurrencyFormatter.format(part.value ?? Money.zero),
                      label,
                      if (part.status == _PartStatus.paid &&
                          reference.isNotEmpty)
                        'Ref $reference',
                    ].join(' · '),
                    style: AppTypography.caption.copyWith(color: color),
                  ),
                  if (part.message case final message?)
                    Text(message, style: AppTypography.caption),
                ],
              ),
            ),
            Icon(icon, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
