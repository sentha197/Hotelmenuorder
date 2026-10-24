import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';

/// Bill details for one order: invoice, payments and receipt actions.
class BillScreen extends StatefulWidget {
  const BillScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  bool _sharing = false;

  Future<void> _share(Invoice invoice) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await ReceiptPdf.build(
        invoice,
        logoPng: await BrandAssets.logoPng(),
        printedAt: DateTime.now(),
      );
      await FileExport.sharePdf(bytes, ReceiptPdf.fileName(invoice));
    } on Object {
      if (mounted) {
        showAppSnackBar(
          context,
          'The receipt could not be shared. Please try again.',
          icon: Icons.error_outline_rounded,
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _checkPending() async {
    final billing = context.read<BillingController>();
    await billing.checkPending(widget.invoiceId);
    if (!mounted) return;
    final invoice = billing.byId(widget.invoiceId);
    showAppSnackBar(
      context,
      invoice?.hasPendingPayment ?? false
          ? 'Still waiting for confirmation from the payment provider.'
          : 'Payment status updated.',
      icon: Icons.info_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final invoice = billing.byId(widget.invoiceId);
    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Bill'),
        ),
        body: const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Bill not found',
          message: 'This bill is no longer on this device.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(invoice.status == InvoiceStatus.paid ? 'Receipt' : 'Bill'),
        actions: [
          IconButton(
            tooltip: 'Print or save receipt',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => AppNav.openReceipt(context, invoice.id),
          ),
          IconButton(
            tooltip: 'Share receipt PDF',
            icon: _sharing
                ? const QrPulseLoader(
                    size: 18,
                    color: AppColors.primary,
                    semanticLabel: 'Preparing the receipt',
                  )
                : const Icon(Icons.ios_share_rounded),
            onPressed: _sharing ? null : () => _share(invoice),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // Readable on tablets and desktops, never wider than the screen.
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.xxl,
            ),
            children: [
              FadeSlideIn(
                child: InvoiceView(
                  invoice: invoice,
                  onCheckPending: _checkPending,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: invoice.outstanding.isZero
          ? null
          : _PayBar(
              invoice: invoice,
              onPay: () => AppNav.openPayment(context, invoice.id),
              onCheckPending: _checkPending,
              onCancelRequest: _cancelCounterRequest,
            ),
    );
  }

  Future<void> _cancelCounterRequest() async {
    try {
      await context.read<BillingController>().cancelCounterRequest(
        widget.invoiceId,
      );
    } on PaymentException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, icon: Icons.error_outline);
      }
    }
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.invoice,
    required this.onPay,
    required this.onCheckPending,
    required this.onCancelRequest,
  });

  final Invoice invoice;
  final VoidCallback onPay;
  final VoidCallback onCheckPending;
  final VoidCallback onCancelRequest;

  @override
  Widget build(BuildContext context) {
    final pending = invoice.hasPendingPayment;
    final request = invoice.openCounterRequest;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
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
                AppSpacing.lg,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Balance due',
                          style: AppTypography.sectionTitle,
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(invoice.outstanding),
                        style: AppTypography.headline.copyWith(fontSize: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (pending) ...[
                    Text(
                      'A payment is being confirmed. You will not be charged '
                      'twice.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.info,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onCheckPending,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Check status'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ] else if (request != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          request.kind == CounterRequestKind.cash
                              ? Icons.payments_outlined
                              : Icons.storefront_rounded,
                          color: AppColors.info,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${request.kind == CounterRequestKind.cash ? 'Pay in cash' : 'Pay'} '
                            '${CurrencyFormatter.format(request.amount)} at '
                            'the counter. Staff will record your payment and '
                            'the bill will update here.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Pay another way',
                            height: 46,
                            onPressed: onPay,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(
                          onPressed: onCancelRequest,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ] else
                    PrimaryButton(
                      label: 'Pay Now',
                      icon: Icons.lock_rounded,
                      onPressed: onPay,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
