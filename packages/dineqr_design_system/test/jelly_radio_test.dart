import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _values = ['Today', 'Yesterday', 'Last 7 days', 'Last 30 days'];

BoxDecoration _decoration(String _, bool selected) => BoxDecoration(
  color: selected ? Colors.black : Colors.white,
  borderRadius: BorderRadius.circular(100),
  border: Border.all(color: Colors.grey),
);

Widget _host({
  required String selected,
  required ValueChanged<String> onSelected,
  bool reduced = false,
  double width = 800,
  List<String> values = _values,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 600), disableAnimations: reduced),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: JellyRadio<String>(
              values: values,
              selected: selected,
              onSelected: onSelected,
              decorationOf: _decoration,
              labelBuilder: (context, value, _) => Text(value),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A stateful host so taps change the selection like a real screen.
class _Harness extends StatefulWidget {
  const _Harness({
    this.reduced = false,
    this.width = 800,
    this.values = _values,
  });
  final bool reduced;
  final double width;
  final List<String> values;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late String selected = widget.values[2];
  final picked = <String>[];

  /// Changes the selection from outside, as a screen's state would.
  void select(String value) => setState(() => selected = value);

  @override
  Widget build(BuildContext context) => _host(
    selected: selected,
    values: widget.values,
    reduced: widget.reduced,
    width: widget.width,
    onSelected: (v) => setState(() {
      picked.add(v);
      selected = v;
    }),
  );
}

/// The scale/translation transforms painted for the chip labelled [label].
List<Matrix4> _transformsOf(WidgetTester tester, String label) =>
    tester
        .widgetList<Transform>(
          find.ancestor(of: find.text(label), matching: find.byType(Transform)),
        )
        .map((t) => t.transform)
        .toList()
      ..addAll(
        tester
            .widgetList<Transform>(
              find.descendant(
                of: find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Stack),
                    )
                    .first,
                matching: find.byType(Transform),
              ),
            )
            .map((t) => t.transform),
      );

bool _atRest(List<Matrix4> transforms) =>
    transforms.every((m) => m.isIdentity());

void main() {
  testWidgets('a chip is the size of a plain bordered chip with that padding', (
    tester,
  ) async {
    await tester.pumpWidget(_host(selected: 'Today', onSelected: (_) {}));
    final chip = tester.getSize(
      find
          .ancestor(of: find.text('Yesterday'), matching: find.byType(Stack))
          .first,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: _decoration('', false),
              child: const Text('Yesterday'),
            ),
          ),
        ),
      ),
    );
    expect(chip, tester.getSize(find.byType(Container).last));
  });

  testWidgets('tapping a chip selects it once, plays the jelly and settles', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(_atRest(_transformsOf(tester, 'Today')), isTrue);

    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(state.picked, ['Today']);
    expect(
      _atRest(_transformsOf(tester, 'Today')),
      isFalse,
      reason: 'chosen chip swells',
    );
    expect(
      _atRest(_transformsOf(tester, 'Yesterday')),
      isFalse,
      reason: 'neighbour is pushed',
    );

    await tester.pumpAndSettle();
    for (final v in _values) {
      expect(
        _atRest(_transformsOf(tester, v)),
        isTrue,
        reason: '$v back at rest',
      );
    }

    // Tapping the chosen chip again does not call onSelected.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(state.picked, ['Today']);
  });

  testWidgets('with reduced motion nothing moves', (tester) async {
    await tester.pumpWidget(const _Harness(reduced: true));
    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    for (final v in _values) {
      expect(_atRest(_transformsOf(tester, v)), isTrue);
    }
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a chosen chip off screen is scrolled into view', (tester) async {
    final many = [for (var i = 0; i < 12; i++) 'Category $i'];
    await tester.pumpWidget(_Harness(width: 300, values: many));
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.controller!.offset, 0);
    // Choose the last chip by changing the selection from outside.
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.select(many.last);
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final chip = tester.getRect(
      find
          .ancestor(of: find.text(many.last), matching: find.byType(Stack))
          .first,
    );
    expect(
      chip.left >= viewport.left - 0.5 && chip.right <= viewport.right + 0.5,
      isTrue,
      reason: 'chip $chip inside $viewport',
    );
  });

  testWidgets('chips are announced as a mutually exclusive choice', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(selected: 'Today', onSelected: (_) {}));
    expect(
      tester.getSemantics(find.text('Today')),
      matchesSemantics(
        label: 'Today',
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasSelectedState: true,
      ),
    );
    handle.dispose();
  });
}
