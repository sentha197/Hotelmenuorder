import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _button({bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(
      backgroundColor: Colors.red,
      body: Center(
        child: SpecularEdge(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadii.pill,
            ),
            child: const Text('Order now'),
          ),
        ),
      ),
    ),
  ),
);

/// The light's position (0 to 1 round the edge) as painted now.
double _progress(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(SpecularEdge),
      matching: find.byType(CustomPaint),
    ),
  );
  // The painter repaints from the animation it was given.
  return ((paint.foregroundPainter! as dynamic).progress as Animation<double>)
      .value;
}

void main() {
  testWidgets('the light circles on its own, once every 2 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(_button());
    final start = _progress(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final quarter = _progress(tester);
    expect(quarter - start, closeTo(0.25, 0.02));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'keeps running');
    expect(tester.takeException(), isNull);
  });

  testWidgets('it does not change the button size or take touches', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GestureDetector(
            onTap: () => taps++,
            child: SpecularEdge(
              child: Container(width: 120, height: 32, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(SpecularEdge)), const Size(120, 32));
    await tester.tap(find.byType(SpecularEdge));
    expect(taps, 1);
  });

  testWidgets('with reduced motion the light holds still', (tester) async {
    await tester.pumpWidget(_button(reduced: true));
    final a = _progress(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_progress(tester), a);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('tests can hold every light still', (tester) async {
    SpecularEdge.debugAnimate = false;
    addTearDown(() => SpecularEdge.debugAnimate = true);
    await tester.pumpWidget(_button());
    await tester.pumpAndSettle();
    expect(find.text('Order now'), findsOneWidget);
  });
}
