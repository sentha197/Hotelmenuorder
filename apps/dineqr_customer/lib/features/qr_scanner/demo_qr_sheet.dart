import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

class DemoQrCode {
  const DemoQrCode({
    required this.title,
    required this.subtitle,
    required this.payload,
    this.valid = true,
  });

  final String title;
  final String subtitle;
  final String payload;
  final bool valid;
}

final demoQrCodes = <DemoQrCode>[
  DemoQrCode(
    title: 'Table 05',
    subtitle: TableQrParser.payloadFor(5),
    payload: TableQrParser.payloadFor(5),
  ),
  DemoQrCode(
    title: 'Table 12',
    subtitle: TableQrParser.payloadFor(12),
    payload: TableQrParser.payloadFor(12),
  ),
  const DemoQrCode(
    title: 'Parcel order',
    subtitle: TableQrParser.parcelPayload,
    payload: TableQrParser.parcelPayload,
  ),
  const DemoQrCode(
    title: 'Invalid code',
    subtitle: 'A website link, to see validation',
    payload: 'https://example.com/menu',
    valid: false,
  ),
  const DemoQrCode(
    title: 'Unknown table',
    subtitle: 'DINEQR:TABLE:99',
    payload: 'DINEQR:TABLE:99',
    valid: false,
  ),
];

/// Lists the demo table codes. With [onSelect] the tiles simulate a scan;
/// without it the sheet shows large scannable codes so another device can
/// scan them.
Future<void> showDemoQrSheet(
  BuildContext context, {
  ValueChanged<String>? onSelect,
}) {
  return showBrandSheet<void>(
    context,
    builder: (sheetContext) {
      final codes = onSelect == null
          ? demoQrCodes.where((code) => code.valid).toList()
          : demoQrCodes;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    'Demo QR codes',
                    style: AppTypography.screenTitle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const DemoTag(),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              onSelect == null
                  ? 'Show these on this screen and scan them with the app on '
                        'another phone to test the real camera flow.'
                  : 'No table code nearby? Pick one to simulate a scan. Each '
                        'payload goes through the same validation as the camera.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final (index, code) in codes.indexed)
              FadeSlideIn(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: onSelect == null
                      ? _LargeQrTile(code: code)
                      : _QrChoiceTile(
                          code: code,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onSelect(code.payload);
                          },
                        ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _QrChoiceTile extends StatelessWidget {
  const _QrChoiceTile({required this.code, required this.onTap});

  final DemoQrCode code;
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
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: code.valid ? Colors.white : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: code.valid
                  ? TableQrCode(
                      payload: code.payload,
                      size: 56,
                      showLogo: false,
                    )
                  : const Icon(
                      Icons.qr_code_2_rounded,
                      color: AppColors.error,
                      size: 30,
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(code.title, style: AppTypography.cardTitle),
                  const SizedBox(height: 2),
                  Text(
                    code.subtitle,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              code.valid
                  ? Icons.chevron_right_rounded
                  : Icons.error_outline_rounded,
              color: code.valid ? AppColors.textMuted : AppColors.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeQrTile extends StatelessWidget {
  const _LargeQrTile({required this.code});

  final DemoQrCode code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          TableQrCode(
            payload: code.payload,
            size: 136,
            semanticLabel: '${code.title} QR code',
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code.title, style: AppTypography.sectionTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(code.payload, style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
