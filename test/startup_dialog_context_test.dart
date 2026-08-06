import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the mechanism behind a startup hang: `showDialog` needs a [Navigator]
/// *above* the context it is given, and the state object that builds
/// `MaterialApp` sits above its own Navigator, not below it.
///
/// `_MyAppState._requestPermissions` showed the Play-required location
/// disclosure with the bare `context` of the widget that builds `MaterialApp`.
/// On any install where the disclosure had not been shown before — i.e. every
/// fresh install — that call threw, `fetchPrayerTimes()` on the line after it
/// never ran, and `prayerTimesProvider` stayed on its initial
/// `AsyncValue.loading()` forever. The UI renders that as a shimmer that never
/// resolves and cannot be retried: "it keeps loading".
void main() {
  testWidgets('a context above MaterialApp cannot open a dialog', (
    tester,
  ) async {
    late BuildContext aboveMaterialApp;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          aboveMaterialApp = context;
          return const MaterialApp(home: Scaffold(body: Text('home')));
        },
      ),
    );

    // This is the shape of the original call.
    await expectLater(
      () => showDialog<bool>(
        context: aboveMaterialApp,
        builder: (_) => const AlertDialog(content: Text('disclosure')),
      ),
      throwsA(isA<FlutterError>()),
      reason:
          'no Navigator is an ancestor of the widget that builds MaterialApp',
    );
  });

  testWidgets('a navigatorKey gives that same caller a usable context', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home')),
      ),
    );

    // The fix: route the dialog through the app's own Navigator rather than
    // through a context that sits above it.
    final ctx = navigatorKey.currentContext;
    expect(ctx, isNotNull);

    final future = showDialog<bool>(
      context: ctx!,
      builder:
          (_) => AlertDialog(
            content: const Text('disclosure'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ok'),
              ),
            ],
          ),
    );
    await tester.pumpAndSettle();

    expect(find.text('disclosure'), findsOneWidget);
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });
}
