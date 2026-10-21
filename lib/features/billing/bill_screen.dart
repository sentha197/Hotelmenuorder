import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/loaders.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/brand_assets.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/file_export.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/billing.dart';
import '../../data/services/receipt_pdf.dart';
import '../../state/billing_controller.dart';
import 'invoice_view.dart';

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
    final payable = invoice.payableNow;
    final canPayOnline = !payable.isZero && billing.onlinePaymentsAvailable;
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxl,
        ),
        children: [
          FadeSlideIn(
            child: InvoiceView(invoice: invoice, onCheckPending: _checkPending),
          ),
        ],
      ),
      bottomNavigationBar: invoice.outstanding.isZero
          ? null
          : _PayBar(
              invoice: invoice,
              canPayOnline: canPayOnline,
              onPay: () => AppNav.openPayment(context, invoice.id),
            ),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.invoice,
    required this.canPayOnline,
    required this.onPay,
  });

  final Invoice invoice;
  final bool canPayOnline;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final pending = invoice.hasPendingPayment;
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
              if (pending)
                Text(
                  'A payment is being confirmed. You will not be charged twice.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(color: AppColors.info),
                )
              else if (canPayOnline)
                PrimaryButton(
                  label: 'Pay ${CurrencyFormatter.format(invoice.payableNow)}',
                  icon: Icons.lock_rounded,
                  onPressed: onPay,
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Please pay at the counter. Staff will record your '
                        'payment and the bill will update here.',
                        style: AppTypography.caption,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
