import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myadhan/services/app_config.dart';
import 'package:myadhan/services/local_timezone.dart';
import 'package:myadhan/view/AppToast.dart';
import 'package:myadhan/view/OfflineBanner.dart';
import 'package:timezone/timezone.dart' as tz;

/// This file shipped as the unmodified `flutter create` counter template: it
/// pumped `MyApp()`, looked for a '0', and tapped an `Icons.add` that has
/// never existed in this app. `flutter test` therefore failed on a clean
/// checkout, which is why nothing in the project ran it.
void main() {
  group('LocalTimezone', () {
    test('resolves tz.local to a zone matching the device offset', () {
      LocalTimezone.configure();

      final now = DateTime.now();
      final resolved = tz.TZDateTime.from(now, tz.local);

      // The whole point of the fix: whatever zone we land on must agree with
      // the device about what time it is. Pinning Africa/Algiers, as the app
      // used to, fails this on every device outside UTC+1.
      expect(
        resolved.timeZoneOffset,
        now.timeZoneOffset,
        reason:
            'tz.local (${tz.local.name}) disagrees with the device offset — '
            'every scheduled reminder would fire at the wrong time',
      );
    });

    test('is idempotent', () {
      LocalTimezone.configure();
      final first = tz.local.name;
      LocalTimezone.configure();
      expect(tz.local.name, first);
    });
  });

  group('AppConfig', () {
    test('store URLs are built from the real application id', () {
      // A mismatch here ships a "rate this app" row that opens a Play page for
      // an app that doesn't exist.
      expect(AppConfig.packageName, 'com.ki1lux.adhani');
      expect(AppConfig.playStoreUrl, contains(AppConfig.packageName));
      expect(AppConfig.playStoreMarketUri, contains(AppConfig.packageName));
      expect(AppConfig.packageName, isNot(contains('com.example')));
    });

    test('privacy policy URL is absolute and https', () {
      final uri = Uri.parse(AppConfig.privacyPolicyUrl);
      expect(uri.hasScheme, isTrue);
      expect(uri.scheme, 'https');
    });
  });

  group('OfflineBanner', () {
    testWidgets('stays out of the way when the data is fresh', (tester) async {
      await tester.pumpWidget(
        const _TestHarness(child: Scaffold(body: OfflineBanner())),
      );
      await tester.pump();

      expect(find.text('وضع دون اتصال'), findsNothing);
      expect(find.text('المواقيت قد لا تكون محدّثة'), findsNothing);
    });
  });

  group('AppToast', () {
    testWidgets('shows a message and replaces the previous one', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _TestHarness(
          child: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      AppToast.success(ctx, 'تم الحفظ');
      await tester.pump();
      expect(find.text('تم الحفظ'), findsOneWidget);

      // Replace rather than queue — the toast is a confirmation, and three
      // stacked confirmations for one action is noise.
      AppToast.success(ctx, 'تم التحديث');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('تم الحفظ'), findsNothing);
      expect(find.text('تم التحديث'), findsOneWidget);
    });
  });
}

/// The minimum app shell the widgets under test need: a Riverpod scope (the
/// offline banner reads a provider) inside a MaterialApp.
class _TestHarness extends StatelessWidget {
  final Widget child;
  const _TestHarness({required this.child});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: MaterialApp(home: child));
  }
}
