import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The restaurant's Terms & Conditions or Privacy Policy, as published on
/// the server (the app holds no copy of the text).
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  @override
  void initState() {
    super.initState();
    // Always the current version: staff may have published a new one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LegalController>().loadDocuments(force: true).ignore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final legal = context.watch<LegalController>();
    final document = legal.document(widget.kind);
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(widget.kind.label),
      ),
      body: switch ((document, legal.documentsState)) {
        (final LegalDocument document, _) => _Document(document: document),
        (_, LoadState.loading || null) => const Center(
          child: QrPulseLoader(
            size: 34,
            color: AppColors.primary,
            semanticLabel: 'Loading',
          ),
        ),
        (_, LoadState.error) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load the ${widget.kind.label}',
          message: legal.documentsError ?? 'Please try again.',
          actionLabel: 'Try Again',
          onAction: () => legal.loadDocuments(force: true),
        ),
        (_, LoadState.ready) => EmptyState(
          icon: Icons.description_outlined,
          title: 'Not published',
          message: legal.isAvailable
              ? 'The restaurant has not published a ${widget.kind.label}. '
                    'Please ask a staff member.'
              : 'This offline demo is not connected to a restaurant, so '
                    'there is no ${widget.kind.label} to show.',
        ),
      },
    );
  }
}

class _Document extends StatelessWidget {
  const _Document({required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final published = document.publishedAt;
    return Center(
      child: ConstrainedBox(
        // A readable line length on tablets and in a browser.
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xxxl,
          ),
          children: [
            Text(document.title, style: AppTypography.headline),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Version ${document.version}'
              '${published == null ? '' : ' · Effective ${AppFormat.date(published)}'}',
              style: AppTypography.caption,
            ),
            if (document.changeSummary.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: AppColors.orangeSoft,
                border: false,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.update_rounded,
                      size: 18,
                      color: AppColors.orangeText,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'What changed: ${document.changeSummary}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.orangeText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            LegalTextView(document.body),
          ],
        ),
      ),
    );
  }
}
