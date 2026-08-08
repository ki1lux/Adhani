import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the "change city" pencil badge against a layout trap that the
/// analyzer cannot see.
///
/// A sized `Container` passes **tight** constraints to its child, and an
/// `Image` takes its size from its constraints — so `Image(width: 14)` inside
/// `Container(width: 26, height: 26)` renders at 26x26 and the `width` is
/// silently ignored. The badge looked full because the pen genuinely was
/// filling it.
///
/// `Icon` never had the problem: a glyph is sized by `fontSize`, not by
/// layout, so it ignores the tight constraint. That's why swapping
/// `Icon(size: 14)` for `Image.asset(width: 14)` changed the rendering
/// without changing a single number.
///
/// The fix is `alignment`, which is what makes `Container` loosen the
/// constraints it hands down.
void main() {
  const badge = 26.0;
  const icon = 14.0;

  Future<Size> renderedIconSize(
    WidgetTester tester, {
    required Alignment? alignment,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Container(
              width: badge,
              height: badge,
              alignment: alignment,
              color: const Color(0xFF102030),
              child: Image.asset(
                'assets/editIcon.png',
                width: icon,
                height: icon,
                key: const Key('pen'),
              ),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(const Key('pen')));
  }

  testWidgets('without an alignment the pen is stretched to fill the badge', (
    tester,
  ) async {
    final size = await renderedIconSize(tester, alignment: null);
    expect(
      size.width,
      badge,
      reason:
          'this is the bug: tight constraints override width, so the pen '
          'renders at the full badge size',
    );
  });

  testWidgets('with alignment.center the pen keeps its own size', (
    tester,
  ) async {
    final size = await renderedIconSize(tester, alignment: Alignment.center);
    expect(size.width, icon);
    expect(size.height, icon);
  });
}
