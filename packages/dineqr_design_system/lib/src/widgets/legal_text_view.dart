import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// A Terms & Conditions or Privacy Policy body ([LegalText] Markdown) as
/// readable text: headings, paragraphs and bullets that wrap to any width
/// and follow the guest's text size. The guest and staff apps both use it,
/// so staff preview exactly what guests read.
class LegalTextView extends StatelessWidget {
  const LegalTextView(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final blocks = LegalText.parse(source);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, block) in blocks.indexed)
            Padding(
              padding: EdgeInsets.only(
                top: index == 0
                    ? 0
                    : block is LegalHeading
                    ? AppSpacing.xl
                    : block is LegalBullet && blocks[index - 1] is LegalBullet
                    ? AppSpacing.xxs
                    : AppSpacing.md,
              ),
              child: switch (block) {
                LegalHeading(:final level) => Semantics(
                  header: true,
                  child: _rich(
                    block.spans,
                    level <= 1
                        ? AppTypography.screenTitle
                        : AppTypography.sectionTitle,
                  ),
                ),
                LegalBullet() => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 8,
                        right: AppSpacing.sm,
                        left: AppSpacing.xxs,
                      ),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(child: _rich(block.spans, _bodyStyle)),
                  ],
                ),
                LegalParagraph() => _rich(block.spans, _bodyStyle),
              },
            ),
        ],
      ),
    );
  }

  static final _bodyStyle = AppTypography.body.copyWith(height: 1.5);

  static Widget _rich(List<LegalSpan> spans, TextStyle style) => Text.rich(
    TextSpan(
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: span.bold
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
      ],
    ),
    style: style,
  );
}
