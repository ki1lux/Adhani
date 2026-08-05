import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myadhan/main.dart';

/// The tab stack behind [MainScreen]'s bottom nav.
///
/// The regression these guard against: `FadeIndexedStack` disables
/// [TickerMode] for the tab being left *and* asks it to fade to zero in the
/// same frame — but `AnimatedOpacity` drives that fade with its own ticker,
/// which sits inside that very `TickerMode`. Muting it froze the outgoing tab
/// at full opacity forever, and since a later child paints over an earlier
/// one, every previously-visited tab stayed stacked on top of the one the
/// user had actually selected.
void main() {
  // Deliberately no MaterialApp: its own route machinery contributes
  // FadeTransitions, which the ancestor lookup below would pick up too.
  Widget harness(int index) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: FadeIndexedStack(
        index: index,
        children: const [Text('home'), Text('times'), Text('qibla')],
      ),
    );
  }

  /// The live opacity of the tab holding [label], as actually painted.
  double opacityOf(WidgetTester tester, String label) {
    final fade = tester.widgetList<FadeTransition>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(FadeTransition),
      ),
    ).first;
    return fade.opacity.value;
  }

  testWidgets('a tab left behind actually fades out', (tester) async {
    await tester.pumpWidget(harness(0));
    await tester.pumpWidget(harness(1));
    await tester.pumpAndSettle();

    expect(opacityOf(tester, 'times'), 1.0);
    expect(
      opacityOf(tester, 'home'),
      0.0,
      reason: 'the tab we navigated away from must not stay opaque',
    );
  });

  testWidgets('returning to an earlier tab uncovers it', (tester) async {
    // Forward through the tabs, then back to the first one — the order the
    // bug report followed (home → times → qibla, then back).
    await tester.pumpWidget(harness(0));
    await tester.pumpWidget(harness(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness(2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness(0));
    await tester.pumpAndSettle();

    expect(opacityOf(tester, 'home'), 1.0);
    // Both of these paint *after* 'home' in the stack, so either one left
    // opaque hides it completely.
    expect(opacityOf(tester, 'times'), 0.0);
    expect(opacityOf(tester, 'qibla'), 0.0);
  });

  testWidgets('the visible tab keeps its tickers running', (tester) async {
    await tester.pumpWidget(harness(0));
    await tester.pumpWidget(harness(1));
    await tester.pumpAndSettle();

    expect(TickerMode.valuesOf(tester.element(find.text('times'))).enabled, isTrue);
    expect(
      TickerMode.valuesOf(tester.element(find.text('home'))).enabled,
      isFalse,
      reason: 'a hidden tab should not be animating',
    );
  });
}
