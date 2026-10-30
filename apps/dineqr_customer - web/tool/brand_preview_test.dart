// Renders the DineQR brand elements to PNGs for visual review.
// Run: flutter test tool/brand_preview_test.dart --dart-define=OUT=<dir>
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/brand_preview');

void main() {
  setUpAll(loadBrandFonts);

  testWidgets('brand sheet', (tester) async {
    debugDisableShadows = false;
    Widget tile(Color background, Widget child) => Container(
      color: background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: child,
    );
    await renderToPng(
      tester,
      Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: tile(
                    Colors.white,
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DineQrMark(size: 300),
                        SizedBox(height: 12),
                        DineQrWordmark(fontSize: 64),
                        SizedBox(height: 6),
                        DineQrTagline(fontSize: 14),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.nightGradient,
                    ),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DineQrMark(size: 300, tone: DineQrTone.inverted),
                        SizedBox(height: 12),
                        DineQrWordmark(fontSize: 64, onDark: true),
                        SizedBox(height: 6),
                        DineQrTagline(fontSize: 14, onDark: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final reveal in [0.2, 0.4, 0.6, 0.8])
                  Expanded(
                    child: tile(
                      Colors.white,
                      DineQrMark(size: 150, reveal: reveal),
                    ),
                  ),
                Expanded(
                  child: tile(
                    Colors.white,
                    const DineQrMark(size: 150, sheen: 0.45),
                  ),
                ),
                Expanded(
                  child: tile(
                    AppColors.charcoal,
                    const DineQrMark(size: 150, tone: DineQrTone.inverted),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: tile(Colors.white, const DineQrLockup(height: 48)),
                ),
                Expanded(
                  child: tile(
                    AppColors.primary,
                    const DineQrLockup(height: 48, onDark: true),
                  ),
                ),
                Expanded(
                  child: tile(
                    Colors.white,
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DineQrMark(size: 24),
                        SizedBox(width: 8),
                        DineQrMark(size: 40),
                        SizedBox(width: 8),
                        DineQrMark(
                          size: 40,
                          tone: DineQrTone.mono,
                          monoColor: AppColors.charcoal,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      size: const Size(1200, 1000),
      path: '$_out/brand_sheet.png',
    );
    debugDisableShadows = true;
  });
}
