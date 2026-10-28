import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';

/// Cashier actions for a UPI payment the guest is making straight to the
/// restaurant's own account.
///
/// The app cannot see that money, so it never settles a bill on its own: the
/// cashier looks for the credit in the restaurant's bank or UPI app and
/// confirms it here with the bank's transaction ID (or rejects it).

/// Whether [payment] is waiting for a cashier.
bool awaitsUpiVerification(PaymentTransaction payment) =>
    payment.isUpiDirect && payment.status == PaymentStatus.pending;

/// Asks the cashier to confirm that the money arrived, then records it.
Future<void> confirmUpiPayment(
  BuildContext context,
  Invoice invoice,
  PaymentTransaction payment,
) async {
  final upiId = context.read<PaymentSettingsController>().upi.upiId;
  final reference = await showDialog<String>(
    context: context,
    builder: (_) => ConfirmUpiPaymentDialog(
      invoice: invoice,
      payment: payment,
      upiId: upiId,
    ),
  );
  if (reference == null || !context.mounted) return;
  await runAdminAction(
    context,
    () => context.read<BillingController>().verifyUpiPayment(
      payment.id,
      reference: reference,
    ),
    success: 'Payment of ${CurrencyFormatter.format(payment.amount)} confirmed',
  );
}

/// The cashier did not receive the money.
Future<void> rejectUpiPayment(
  BuildContext context,
  Invoice invoice,
  PaymentTransaction payment,
) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => RejectUpiPaymentDialog(amount: payment.amount),
  );
  if (reason == null || !context.mounted) return;
  await runAdminAction(
    context,
    () => context.read<BillingController>().rejectUpiPayment(
      payment.id,
      reason: reason,
    ),
    success: 'Payment rejected. The bill is unpaid again.',
  );
}

/// The guest started a payment but never said they paid: close it so the
/// bill is free again.
Future<void> cancelUpiPayment(
  BuildContext context,
  Invoice invoice,
  PaymentTransaction payment,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Cancel this UPI payment?',
    message:
        'The guest started paying ${CurrencyFormatter.format(payment.amount)} '
        'by UPI but has not said they paid. Cancel it if they decided to pay '
        'another way; they can start again.',
    confirmLabel: 'Cancel payment',
    icon: Icons.block_rounded,
  );
  if (!confirmed || !context.mounted) return;
  await runAdminAction(
    context,
    () => context.read<BillingController>().cancelUpiPayment(payment.id),
    success: 'UPI payment cancelled',
  );
}

/// The buttons shown next to a UPI payment that waits for a cashier: confirm
/// it, or turn it down (a payment the guest never claimed is "cancelled").
class UpiPaymentActions extends StatelessWidget {
  const UpiPaymentActions({
    super.key,
    required this.invoice,
    required this.payment,
  });

  final Invoice invoice;
  final PaymentTransaction payment;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 32),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextButton(
          key: ValueKey('confirm-${payment.id}'),
          style: style,
          onPressed: () => confirmUpiPayment(context, invoice, payment),
          child: const Text('Confirm'),
        ),
        TextButton(
          key: ValueKey('reject-${payment.id}'),
          style: style.merge(
            TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
          onPressed: () => payment.isClaimed
              ? rejectUpiPayment(context, invoice, payment)
              : cancelUpiPayment(context, invoice, payment),
          child: Text(payment.isClaimed ? 'Not received' : 'Cancel'),
        ),
      ],
    );
  }
}

/// Collects the bank's transaction ID, after the cashier has checked the
/// credit. Pops the normalised ID, or null.
class ConfirmUpiPaymentDialog extends StatefulWidget {
  const ConfirmUpiPaymentDialog({
    super.key,
    required this.invoice,
    required this.payment,
    required this.upiId,
  });

  final Invoice invoice;
  final PaymentTransaction payment;

  /// The restaurant's UPI ID the guest was told to pay (may be empty).
  final String upiId;

  @override
  State<ConfirmUpiPaymentDialog> createState() =>
      _ConfirmUpiPaymentDialogState();
}

class _ConfirmUpiPaymentDialogState extends State<ConfirmUpiPaymentDialog> {
  // The guest's own note of the ID, when they gave one: a hint to search the
  // statement for, not something to trust.
  late final _reference = TextEditingController(text: widget.payment.reference);
  bool _seen = false;
  bool _tried = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  String get _normalised => UpiReference.normalize(_reference.text);

  String? get _problem {
    final value = _normalised;
    if (value.isEmpty) return 'Enter the UPI transaction ID from your bank.';
    if (!UpiReference.isValid(value)) return UpiReference.rule;
    return null;
  }

  void _submit() {
    setState(() => _tried = true);
    if (!_seen || _problem != null) return;
    Navigator.pop(context, _normalised);
  }

  @override
  Widget build(BuildContext context) {
    final payment = widget.payment;
    final amount = CurrencyFormatter.format(payment.amount);
    final claimed = payment.claimedAt;
    return AlertDialog(
      title: Text('Confirm UPI payment', style: AppTypography.sectionTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$amount · Bill ${widget.invoice.billNumber} · '
              '${widget.invoice.tableLabel}',
              style: AppTypography.cardTitle,
            ),
            const SizedBox(height: 2),
            Text(
              claimed == null
                  ? 'The guest started this payment but has not said they '
                        'paid yet.'
                  : 'The guest says they paid at ${AppFormat.dateTime(claimed)}.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Open your bank or UPI app and look for a credit of $amount'
              '${widget.upiId.isEmpty ? '' : ' to ${widget.upiId}'}, usually '
              'with the note "${UpiPaymentLink.noteFor(widget.invoice.billNumber, payment.id)}". '
              'Only confirm once you can see it there: the guest\'s screen '
              'proves nothing.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('upi-reference'),
              controller: _reference,
              autofocus: true,
              maxLength: 40,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'UPI transaction ID',
                helperText: payment.reference.isEmpty
                    ? 'In the credit alert or statement (often 12 digits).'
                    : 'Typed by the guest. Check it against your statement.',
                helperMaxLines: 3,
                counterText: '',
                errorText: _tried ? _problem : null,
                errorMaxLines: 3,
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('upi-seen'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              activeColor: AppColors.primary,
              value: _seen,
              onChanged: (value) => setState(() => _seen = value ?? false),
              title: Text(
                'I can see $amount received in our account.',
                style: AppTypography.label,
              ),
            ),
            if (_tried && !_seen)
              Text(
                'Tick the box once you have checked the credit.',
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const ValueKey('upi-confirm'),
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Confirm payment'),
        ),
      ],
    );
  }
}

/// Asks why the money did not arrive (optional), then pops the reason, or
/// null if the cashier backs out. Owns its field, so closing it is clean.
class RejectUpiPaymentDialog extends StatefulWidget {
  const RejectUpiPaymentDialog({super.key, required this.amount});

  final Money amount;

  @override
  State<RejectUpiPaymentDialog> createState() => _RejectUpiPaymentDialogState();
}

class _RejectUpiPaymentDialogState extends State<RejectUpiPaymentDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Payment not received?', style: AppTypography.sectionTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use this when ${CurrencyFormatter.format(widget.amount)} did '
              'not reach your account. The bill stays unpaid and the guest '
              'can pay again or pay at the counter.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('upi-reject-reason'),
              controller: _reason,
              autofocus: true,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const ValueKey('upi-reject-confirm'),
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Reject payment'),
        ),
      ],
    );
  }
}
