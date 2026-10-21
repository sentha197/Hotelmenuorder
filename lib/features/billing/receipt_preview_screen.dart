import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/loaders.dart';
import '../../core/brand/brand_assets.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/billing.dart';
import '../../data/services/receipt_pdf.dart';
import '../../data/services/thermal_printer.dart';
import '../../state/billing_controller.dart';

/// Print-friendly receipt preview with print, save and share. Printing uses
/// the system print dialog; a thermal printer is used only when connected.
class ReceiptPreviewScreen extends StatefulWidget {
  const ReceiptPreviewScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  late final Future<Uint8List?> _logo = BrandAssets.logoPng();
  final DateTime _printedAt = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final invoice = context.select<BillingController, Invoice?>(
      (billing) => billing.byId(widget.invoiceId),
    );
    final printer = context.read<ThermalPrinter>();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Receipt preview'),
      ),
      body: invoice == null
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Bill not found',
              message: 'This bill is no longer on this device.',
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.surfaceSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.page,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        printer.isAvailable
                            ? Icons.print_rounded
                            : Icons.print_disabled_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          printer.isAvailable
                              ? 'Thermal printer: ${printer.description}'
                              : '${printer.description}. Print through your '
                                    'device or save the PDF.',
                          style: AppTypography.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<Uint8List?>(
                    future: _logo,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: QrPulseLoader(
                            size: 30,
                            color: AppColors.primary,
                            semanticLabel: 'Preparing receipt',
                          ),
                        );
                      }
                      return PdfPreview(
                        build: (format) => ReceiptPdf.build(
                          invoice,
                          format: format,
                          logoPng: snapshot.data,
                          printedAt: _printedAt,
                        ),
                        pageFormats: ReceiptPdf.pageFormats,
                        initialPageFormat: PdfPageFormat.roll80,
                        canChangeOrientation: false,
                        canDebug: false,
                        pdfFileName: ReceiptPdf.fileName(invoice),
                        loadingWidget: const QrPulseLoader(
                          size: 30,
                          color: AppColors.primary,
                          semanticLabel: 'Preparing receipt',
                        ),
                        pdfPreviewPageDecoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: AppShadows.card,
                        ),
                        previewPageMargin: const EdgeInsets.all(16),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
