import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../widgets/admin_widgets.dart';
import 'upi_verification.dart';

/// One bill for staff: invoice, counter payments, UPI payments waiting for
/// confirmation, refunds, reconciliation and receipt output.
class AdminBillDetailScreen extends StatelessWidget {
  const AdminBillDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  Future<void> _recordPayment(BuildContext context, Invoice invoice) async {
    final result = await showDialog<_PaymentEntry>(
      context: context,
      builder: (_) => _RecordPaymentDialog(max: invoice.payableNow),
    );
    if (result == null || !context.mounted) return;
    await runAdminAction(
      context,
      () => context.read<BillingController>().recordCounterPayment(
        invoiceId: invoice.id,
        amount: result.amount,
        method: result.method,
        reference: result.reference,
      ),
      success: 'Payment of ${CurrencyFormatter.format(result.amount)} recorded',
    );
  }

  Future<void> _refund(
    BuildContext context,
    Invoice invoice,
    PaymentTransaction payment,
  ) async {
    final max = invoice.refundableOn(payment.id);
    final result = await showDialog<({Money amount, String reason})>(
      context: context,
      builder: (_) => _RefundDialog(
        max: max,
        payment: payment,
        simulated: payment.isSimulated,
      ),
    );
    if (result == null || !context.mounted) return;
    await runAdminAction(
      context,
      () => context.read<BillingController>().refund(
        invoiceId: invoice.id,
        paymentId: payment.id,
        amount: result.amount,
        reason: result.reason,
      ),
      success: payment.isSimulated
          ? 'Simulated refund recorded (no money moved)'
          : 'Refund recorded',
    );
  }

  Future<void> _share(BuildContext context, Invoice invoice) =>
      runAdminAction(context, () async {
        final bytes = await ReceiptPdf.build(
          invoice,
          logoPng: await BrandAssets.logoPng(),
          printedAt: DateTime.now(),
        );
        await FileExport.sharePdf(bytes, ReceiptPdf.fileName(invoice));
      });

  Future<void> _thermal(BuildContext context, Invoice invoice) =>
      runAdminAction(context, () async {
        final printer = context.read<ThermalPrinter>();
        await printer.printBytes(EscPosReceipt.encode(invoice, columns: 48));
      }, success: 'Sent to the thermal printer');

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final billing = context.watch<BillingController>();
    final printer = context.read<ThermalPrinter>();
    final invoice = billing.byId(invoiceId);
    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: const AdminEmpty(
          icon: Icons.request_quote_outlined,
          title: 'Bill not found',
          message: 'It may have been removed by a demo reset.',
        ),
      );
    }
    final canCollect =
        admin.can(Permission.collectPayments) && !invoice.payableNow.isZero;
    final canReconcile =
        admin.can(Permission.reconcilePayments) && invoice.hasPendingPayment;
    final canRefund = admin.can(Permission.issueRefunds);
    final canConfirmUpi = admin.can(Permission.collectPayments);
    return Scaffold(
      backgroundColor: adminBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(invoice.billNumber),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Receipt preview and print',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AdminGuard(
                  permission: Permission.viewBills,
                  child: ReceiptPreviewScreen(
                    invoice: invoice,
                    printer: context.read<ThermalPrinter>(),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Share receipt PDF',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => _share(context, invoice),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (invoice.refundDue)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: DemoDataBanner(
                        text:
                            'The order was cancelled after a payment of '
                            '${CurrencyFormatter.format(invoice.netPaid)}. '
                            'Refund it below.',
                      ),
                    ),
                  if (canCollect || canReconcile || printer.isAvailable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        children: [
                          if (canCollect)
                            PrimaryButton(
                              label: 'Record payment',
                              icon: Icons.point_of_sale_rounded,
                              expand: false,
                              height: 46,
                              onPressed: () => _recordPayment(context, invoice),
                            ),
                          if (canReconcile)
                            SecondaryButton(
                              label: 'Reconcile pending',
                              icon: Icons.sync_rounded,
                              expand: false,
                              height: 46,
                              onPressed: () => runAdminAction(
                                context,
                                () => billing.reconcile(invoice.id),
                                success: 'Pending payments checked',
                              ),
                            ),
                          if (printer.isAvailable)
                            SecondaryButton(
                              label: 'Thermal print',
                              icon: Icons.print_rounded,
                              expand: false,
                              height: 46,
                              onPressed: () => _thermal(context, invoice),
                            ),
                        ],
                      ),
                    ),
                  InvoiceView(
                    invoice: invoice,
                    onCheckPending: canReconcile
                        ? () => runAdminAction(
                            context,
                            () => billing.reconcile(invoice.id),
                          )
                        : null,
                    paymentActions: (payment) {
                      // A UPI payment to the restaurant waits for someone to
                      // check the money arrived.
                      if (canConfirmUpi && awaitsUpiVerification(payment)) {
                        return UpiPaymentActions(
                          invoice: invoice,
                          payment: payment,
                        );
                      }
                      if (!canRefund ||
                          invoice.refundableOn(payment.id).isZero) {
                        return null;
                      }
                      return TextButton(
                        onPressed: () => _refund(context, invoice, payment),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 32),
                        ),
                        child: const Text('Refund'),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    printer.isAvailable
                        ? 'Thermal printer: ${printer.description}.'
                        : '${printer.description}. Use the print button to '
                              'print through the device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentEntry {
  const _PaymentEntry(this.amount, this.method, this.reference);

  final Money amount;
  final PaymentMethodType method;
  final String reference;
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.max});

  final Money max;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: _plain(widget.max),
  );
  final _reference = TextEditingController();
  PaymentMethodType _method = PaymentMethodType.cash;
  String? _error;

  static String _plain(Money m) => m.paise % 100 == 0
      ? '${m.paise ~/ 100}'
      : (m.paise / 100).toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = SettingsController.parseRupees(_amount.text);
    if (amount == null || amount.paise <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    if (amount.compareTo(widget.max) > 0) {
      setState(
        () =>
            _error = 'At most ${CurrencyFormatter.format(widget.max)} is due.',
      );
      return;
    }
    Navigator.pop(context, _PaymentEntry(amount, _method, _reference.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record payment', style: AppTypography.sectionTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For money taken at the counter. Balance due: '
              '${CurrencyFormatter.format(widget.max)}.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '₹ ',
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<PaymentMethodType>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [
                for (final method in const [
                  PaymentMethodType.cash,
                  PaymentMethodType.card,
                  PaymentMethodType.upi,
                ])
                  DropdownMenuItem(
                    value: method,
                    child: Text(
                      method == PaymentMethodType.cash
                          ? 'Cash'
                          : '${method.label} (counter terminal)',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _method = value ?? _method),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reference,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                hintText: 'Terminal slip or UPI id',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Record'),
        ),
      ],
    );
  }
}

class _RefundDialog extends StatefulWidget {
  const _RefundDialog({
    required this.max,
    required this.payment,
    required this.simulated,
  });

  final Money max;
  final PaymentTransaction payment;
  final bool simulated;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.max.paise % 100 == 0
        ? '${widget.max.paise ~/ 100}'
        : (widget.max.paise / 100).toStringAsFixed(2),
  );
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = SettingsController.parseRupees(_amount.text);
    if (amount == null || amount.paise <= 0) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    if (amount.compareTo(widget.max) > 0) {
      setState(
        () => _error =
            'At most ${CurrencyFormatter.format(widget.max)} can be refunded.',
      );
      return;
    }
    if (_reason.text.trim().length < 3) {
      setState(() => _error = 'Enter a reason.');
      return;
    }
    Navigator.pop(context, (amount: amount, reason: _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    return AlertDialog(
      title: Text('Refund payment', style: AppTypography.sectionTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.method.label} payment of ${CurrencyFormatter.format(p.amount)}'
              '${p.reference.isEmpty ? '' : ' (ref ${p.reference})'}. '
              'Refundable: ${CurrencyFormatter.format(widget.max)}.',
              style: AppTypography.bodySecondary,
            ),
            if (widget.simulated) ...[
              const SizedBox(height: AppSpacing.sm),
              const DemoDataBanner(
                text:
                    'Simulated payment: the refund is simulated too. No money '
                    'moves.',
              ),
            ] else if (p.method == PaymentMethodType.cash) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Return the cash at the counter; this records it.',
                style: AppTypography.caption,
              ),
            ] else if (p.isUpiDirect) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This UPI payment went straight to your account. Send the '
                'money back from your own UPI app; this only records it.',
                style: AppTypography.caption,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Refund amount',
                prefixText: '₹ ',
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reason'),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Refund'),
        ),
      ],
    );
  }
}
