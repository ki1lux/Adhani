import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/view/QiblaScreen.dart';
import 'package:myadhan/view/PrayerTimeScreen.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:myadhan/view/SettingsScreen.dart';
import 'package:myadhan/view/adhan_screen.dart';
import 'package:myadhan/view/splash_screen.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/date_symbol_data_local.dart';

class FadeTransitionBuilder extends PageTransitionsBuilder {
  const FadeTransitionBuilder();

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
  tz.initializeTimeZones();
  await initializeDateFormatting();

  // Register native daily prayer worker (replaces Flutter WorkManager)
  const channel = MethodChannel('com.myadhan/notification');
  try {
    await channel.invokeMethod('registerDailyPrayerWorker');
  } catch (e) {
    debugPrint('Failed to register daily prayer worker: $e');
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _notificationsScheduled = false;
  String _lastFetchDate = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastFetchDate = _todayString();
    _initNotificationsSync();
    // Wait for widget tree to be built before requesting permissions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
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
        debugPrint(
          '📅 Date changed ($today != $_lastFetchDate) — refreshing prayer times',
        );
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

  void _initNotificationsSync() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Algiers'));

    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_stat_adhan',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    _notificationsPlugin.initialize(settings);
  }

  Future<void> _requestPermissions() async {
    debugPrint('Requesting permissions...');
    // Request all permissions at once - avoids race conditions
    final statuses =
        await [Permission.notification, Permission.locationWhenInUse].request();

    debugPrint('Permission results: $statuses');

    // Request exact alarm permission via native channel
    await PrayerAlarmScheduler.requestExactAlarmPermission();

    // Only fetch prayer times if location permission is granted
    final locationStatus = statuses[Permission.locationWhenInUse];
    if (locationStatus != null && locationStatus.isGranted) {
      debugPrint('Location granted - fetching prayer times...');
      ref.read(prayerTimesProvider.notifier).fetchPrayerTimes();
    } else {
      debugPrint('Location permission denied');
    }
  }

  Future<void> _scheduleNotifications(PrayerTimeModel data) async {
    // PrayerAlarmScheduler now handles standard local notifications
    await PrayerAlarmScheduler.scheduleAllPrayersWithData(data);
  }

  @override
  Widget build(BuildContext context) {
    // Schedule notifications when prayer times load
    ref.listen<AsyncValue<PrayerTimeModel>>(prayerTimesProvider, (
      previous,
      next,
    ) {
      if (previous?.isLoading == true &&
          next.hasValue &&
          !_notificationsScheduled) {
        _notificationsScheduled = true;
        _scheduleNotifications(next.value!);
      }
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'cairo',
        scaffoldBackgroundColor: const Color(0xff0A2239),
        canvasColor: const Color(0xff0A2239),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: FadeTransitionBuilder(),
            TargetPlatform.iOS: FadeTransitionBuilder(),
          },
        ),
      ),
      home: const SplashScreen(nextScreen: MainScreen()),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FadeIndexedStack(
        index: _selectedIndex,
        children: [
          AdhanScreen(),
          PrayerTimeScreen(),
          QiblaScreen(isActive: _selectedIndex == 2),
          SettingsScreen(),
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
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem('assets/h2.svg', 0),
                _buildNavItem('assets/h3.svg', 1),
                _buildNavItem('assets/h1.svg', 2),
                _buildNavItem('assets/settingsIcon.svg', 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(String asset, int index) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_selectedIndex != index) {
            setState(() => _selectedIndex = index);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: double.infinity,
          padding: const EdgeInsets.all(18),
          child: AnimatedScale(
            scale: isSelected ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ]
                        : null,
              ),
              child: SvgPicture.asset(
                asset,
                colorFilter: ColorFilter.mode(
                  isSelected ? Colors.white : Colors.white60,
                  BlendMode.srcIn,
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
class FadeIndexedStack extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Stack(
      children: List.generate(children.length, (i) {
        final isActive = i == index;
        return IgnorePointer(
          ignoring: !isActive,
          child: AnimatedOpacity(
            duration: duration,
            curve: Curves.easeInOut,
            opacity: isActive ? 1.0 : 0.0,
            child: children[i],
          ),
        );
      }),
    );
  }
}
