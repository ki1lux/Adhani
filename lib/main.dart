import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/services/app_logger.dart';
import 'package:myadhan/services/local_timezone.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/LocationDisclosure.dart';
import 'package:myadhan/view/PrayerTimeScreen.dart';
import 'package:myadhan/view/QiblaScreen.dart';
import 'package:myadhan/view/SettingsScreen.dart';
import 'package:myadhan/view/adhan_screen.dart';
import 'package:myadhan/view/splash_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class FadeTransitionBuilder extends PageTransitionsBuilder {
  const FadeTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: child,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve the device's real timezone before anything schedules a
  // notification against `tz.local` (see LocalTimezone for why this used to be
  // hardcoded to Africa/Algiers, and what that broke).
  LocalTimezone.configure();

  // Only the locales the app formats dates in, rather than every locale the
  // `intl` package ships — the full set is a noticeable chunk of startup.
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');

  // Portrait-first, but not portrait-locked: large screens and foldables are
  // free to rotate, and every screen's content is scrollable.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Draw behind the system bars — the app's gradient runs edge to edge, and
  // from Android 15 this is the enforced default anyway.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  String _lastFetchDate = '';

  /// Identifies the times we last armed alarms for, so an identical re-emit
  /// (a cache read followed by a network fetch that agreed with it) doesn't
  /// tear down and rebuild five alarms for nothing.
  String? _scheduledSignature;

  static String _signatureOf(PrayerTimeModel d) =>
      '${d.fajer.toIso8601String()}|${d.dhuhr.toIso8601String()}|'
      '${d.asr.toIso8601String()}|${d.maghrib.toIso8601String()}|'
      '${d.isha.toIso8601String()}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastFetchDate = _todayString();
    // Wait for the widget tree to be built before requesting permissions or
    // touching platform channels — a MethodChannel round trip before runApp
    // is time the user spends looking at a blank window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startUpTasks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Detect when the app resumes from the background.
  /// If the date has changed (e.g. midnight crossed while backgrounded),
  /// re-fetch prayer times so the Hijri date updates immediately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final today = _todayString();
      if (today != _lastFetchDate) {
        logDebug('📅 Date changed — refreshing prayer times');
        _lastFetchDate = today;
        ref.read(prayerTimesProvider.notifier).fetchPrayerTimes();
      }
    }
  }

  /// Returns today's date as "yyyy-MM-dd".
  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Everything that has to happen once, after the first frame.
  Future<void> _startUpTasks() async {
    // Off the critical path: the daily worker only matters tomorrow, so
    // blocking the first frame on a platform channel to register it (which is
    // what `main()` used to do) bought nothing.
    unawaited(_registerDailyWorker());

    await PrayerAlarmScheduler.ensureInitialised();
    await _requestPermissions();
  }

  Future<void> _registerDailyWorker() async {
    const channel = MethodChannel('com.myadhan/notification');
    try {
      await channel.invokeMethod('registerDailyPrayerWorker');
    } catch (e) {
      logWarning('Failed to register daily prayer worker', e);
    }
  }

  Future<void> _requestPermissions() async {
    // Notifications first, and on their own: this is what the prayer alerts
    // are for, and asking for it alongside location made the two prompts
    // indistinguishable from each other.
    await Permission.notification.request();

    // Location is only requested after the prominent disclosure Play requires
    // (see LocationDisclosure). A user who declines still gets prayer times —
    // from the cache, the last known coordinates, or a city they pick by hand.
    var mayAskForLocation = true;
    final alreadyGranted = await Permission.locationWhenInUse.isGranted;
    if (!alreadyGranted && mounted) {
      final seen = await LocationDisclosure.hasBeenShown();
      if (!seen) {
        if (!mounted) return;
        mayAskForLocation = await LocationDisclosure.show(context);
      }
      if (mayAskForLocation) {
        await Permission.locationWhenInUse.request();
      } else {
        logDebug('Location declined at disclosure — using cached data');
      }
    }

    // Exact alarms: only prompt when we don't already have the permission, so
    // returning users aren't bounced into system settings on every launch.
    if (!await PrayerAlarmScheduler.checkExactAlarmPermission()) {
      await PrayerAlarmScheduler.requestExactAlarmPermission();
    }

    // Fetch unconditionally, even when location was denied. The provider falls
    // back to the cached month, the last known coordinates and finally the
    // stored prayer_*_time prefs — and when it truly has nothing it produces
    // an error state with a retry button. Gating this call on the permission
    // left the provider in its initial loading() forever, which the UI
    // rendered as a shimmer that never resolved and could not be retried.
    if (!mounted) return;
    ref.read(prayerTimesProvider.notifier).fetchPrayerTimes();
  }

  Future<void> _scheduleNotifications(PrayerTimeModel data) async {
    await PrayerAlarmScheduler.scheduleAllPrayersWithData(data);
  }

  @override
  Widget build(BuildContext context) {
    // Reschedule alarms whenever a genuinely different day's times arrive.
    ref.listen<AsyncValue<PrayerTimeModel>>(prayerTimesProvider, (
      previous,
      next,
    ) {
      final data = next.value;
      if (data == null) return;

      final signature = _signatureOf(data);
      if (signature == _scheduledSignature) return;

      _scheduledSignature = signature;
      _scheduleNotifications(data);
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Adhani',
      // The UI is written in Arabic and lays itself out RTL, but nothing ever
      // told Flutter that — so Material's own strings (dialog semantics, the
      // text-field context menu, screen-reader announcements) came out in
      // English, and `DateFormat.jm(locale)` had no locale data to resolve
      // against.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      theme: ThemeData(
        fontFamily: 'cairo',
        scaffoldBackgroundColor: AppColors.surface,
        canvasColor: AppColors.surface,
        // A tap target smaller than 48dp is an accessibility failure; this
        // makes Material's own controls honour that by default.
        materialTapTargetSize: MaterialTapTargetSize.padded,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: FadeTransitionBuilder(),
            TargetPlatform.iOS: FadeTransitionBuilder(),
          },
        ),
      ),
      builder: (context, child) {
        // Honour the system font-size setting, but bound it. Every size in
        // this app is a hardcoded logical pixel value inside fixed-height
        // rows and cards; at the 2.0x the platform allows, the prayer rows,
        // the countdown and the nav bar all overflow. Clamping keeps large
        // text genuinely larger while staying inside the layouts.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(nextScreen: MainScreen()),
    );
  }
}

/// Fire-and-forget, spelled out so the intent is obvious at the call site.
void unawaited(Future<void> future) {}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  static const _tabs = <({String asset, String label})>[
    (asset: 'assets/h2.svg', label: 'الرئيسية'),
    (asset: 'assets/h3.svg', label: 'المواقيت'),
    (asset: 'assets/h1.svg', label: 'القبلة'),
    (asset: 'assets/settingsIcon.svg', label: 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FadeIndexedStack(
        index: _selectedIndex,
        children: [
          const AdhanScreen(),
          const PrayerTimeScreen(),
          QiblaScreen(isActive: _selectedIndex == 2),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 12, left: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            // 64 rather than 58: with the 6dp of vertical padding each item
            // needs to sit inside the pill, the old height left a 42dp tap
            // target — under the 48dp accessibility minimum.
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.barFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _buildNavItem(_tabs[i].asset, _tabs[i].label, i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(String asset, String label, int index) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      // The bar was four unlabelled SVGs: TalkBack read "button, button,
      // button, button" with no way to tell which tab was current.
      child: Semantics(
        label: label,
        button: true,
        selected: isSelected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_selectedIndex != index) {
              setState(() => _selectedIndex = index);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient:
                    isSelected
                        ? const LinearGradient(
                          colors: [
                            AppColors.archTop,
                            AppColors.archMid,
                            AppColors.archBottom,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                        : null,
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: AppColors.archTop.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                        : null,
              ),
              child: Center(
                child: ExcludeSemantics(
                  child: SvgPicture.asset(
                    asset,
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(
                      isSelected ? AppColors.surface : AppColors.faint,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A cross-fading stack that preserves the state of its children, achieving
/// an efficient transition similar to IndexedStack with fading children.
///
/// Children are built lazily and then kept. The previous version built all
/// four screens during the first frame, so opening the app paid for the Qibla
/// screen's compass subscription and audio players, and the prayer screen's
/// reverse-geocode, before the user had chosen to visit either of them.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 350),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> {
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(widget.children.length, (i) {
        if (!_visited.contains(i)) return const SizedBox.shrink();
        final isActive = i == widget.index;
        return IgnorePointer(
          ignoring: !isActive,
          // Off-screen tabs shouldn't be describing themselves to a screen
          // reader — without this, TalkBack walks all four at once.
          child: ExcludeSemantics(
            excluding: !isActive,
            // Animations in a fully faded-out child are invisible work.
            child: TickerMode(
              enabled: isActive,
              child: AnimatedOpacity(
                duration: widget.duration,
                curve: Curves.easeInOut,
                opacity: isActive ? 1.0 : 0.0,
                child: widget.children[i],
              ),
            ),
          ),
        );
      }),
    );
  }
}
