import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

import '../../app/routes.dart';

void openLegalDocument(BuildContext context, LegalDocumentKind kind) =>
    Navigator.of(context).pushNamed(Routes.legal, arguments: kind);

/// "Terms & Conditions · Privacy Policy" as links to the full documents.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.intro, this.color});

  /// A line shown above the links.
  final String? intro;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.caption.copyWith(
      color: color ?? AppColors.textSecondary,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (intro != null)
          Text(intro!, textAlign: TextAlign.center, style: style),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, kind) in LegalDocumentKind.values.indexed) ...[
              if (index > 0) Text('·', style: style),
              TextButton(
                onPressed: () => openLegalDocument(context, kind),
                style: TextButton.styleFrom(
                  foregroundColor: color ?? AppColors.primary,
                  textStyle: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: const Size(48, 40),
                ),
                child: Text(kind.label),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The checkboxes a guest ticks before their first order (and after a
/// material change): one per document still to accept, each with a link to
/// its full text. Nothing is ticked in advance.
class LegalConsent extends StatelessWidget {
  const LegalConsent({
    super.key,
    required this.pending,
    required this.ticked,
    required this.onChanged,
    this.enabled = true,
  });

  final List<LegalRequirement> pending;
  final Set<LegalDocumentKind> ticked;
  final void Function(LegalDocumentKind kind, bool ticked) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final updated = pending.any((d) => d.isUpdate);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xxs),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    updated ? 'We have updated our terms' : 'Before you order',
                    style: AppTypography.cardTitle,
                  ),
                ),
              ],
            ),
          ),
          for (final document in pending)
            _ConsentRow(
              document: document,
              ticked: ticked.contains(document.kind),
              enabled: enabled,
              onChanged: (value) => onChanged(document.kind, value),
            ),
        ],
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.document,
    required this.ticked,
    required this.enabled,
    required this.onChanged,
  });

  final LegalRequirement document;
  final bool ticked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final kind = document.kind;
    final statement = switch (kind) {
      LegalDocumentKind.terms => 'I have read and accept the ${kind.label}.',
      LegalDocumentKind.privacy =>
        'I have read and acknowledge the ${kind.label}.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: ticked,
            onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            activeColor: AppColors.primary,
            semanticLabel: statement,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: enabled ? () => onChanged(!ticked) : null,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ExcludeSemantics(
                      child: Text(statement, style: AppTypography.body),
                    ),
                  ),
                ),
                if (document.isUpdate && document.changeSummary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      'What changed: ${document.changeSummary}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.orangeText,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => openLegalDocument(context, kind),
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: Text('Read the ${kind.label} (v${document.version})'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 40),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
