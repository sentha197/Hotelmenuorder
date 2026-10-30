// Close-up of the logo's smile signature at evenly spaced progress values.
// Run: flutter test tool/smile_sheet_test.dart --dart-define=OUT=<dir>
import 'dart:math' as math;

import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/splash');

void main() {
  testWidgets('smile sheet', (tester) async {
    const steps = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];
    await renderToPng(
      tester,
      ColoredBox(
        color: AppColors.deepRed,
        child: Wrap(
          children: [
            for (final s in steps)
              SizedBox(
                width: 260,
                height: 240,
                child: Center(
                  child: DineQrMark(
                    size: 220,
                    tone: DineQrTone.inverted,
                    smile: s,
                    smileGlow: math.sin(
                      math.pi * ((s - 0.6) / 0.4).clamp(0, 1),
                    ),
                  ),
                ),
              ),
            for (final s in steps)
              SizedBox(
                width: 260,
                height: 240,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: DineQrMark(size: 220, smile: s)),
                ),
              ),
          ],
        ),
      ),
      size: const Size(260 * 6, 240 * 4),
      path: '$_out/smile_sheet.png',
    );
  });
}
