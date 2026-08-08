import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:myadhan/view/AnalogClockView.dart';
import 'package:myadhan/view/NextPrayerCard.dart';
import 'package:myadhan/view/OfflineBanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdhanScreen extends ConsumerStatefulWidget {
  const AdhanScreen({super.key});

  @override
  ConsumerState<AdhanScreen> createState() => _AdhanScreenState();
}

class _AdhanScreenState extends ConsumerState<AdhanScreen> {
  static const _contentColor = AppColors.heading;
  static const _mutedColor = AppColors.secondary;

  String _cachedHijri = '';
  String _city = '';
  String _country = '';

  /// The clock's current time, held in a notifier rather than in State.
  ///
  /// The analog clock ticks once a second, and its `onTick` used to call
  /// `setState` on this whole screen — so every second rebuilt the arch card,
  /// the next-prayer card, the location row and the offline banner in order to
  /// change one line of text. Only the text listens now, so a tick repaints
  /// exactly what changed.
  final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());

  /// Built once, not once a second.
  ///
  /// `DateFormat.jm(locale)` isn't a cheap accessor — it resolves the locale,
  /// looks up the symbol set and parses the skeleton into a pattern. The
  /// clock text below rebuilds every tick, so constructing it inline meant
  /// paying all of that 86,400 times a day to format a string that changes
  /// once a minute.
  ///
  /// Reads the actual device locale directly rather than
  /// Localizations.maybeLocaleOf(context): this app renders its own Arabic
  /// strings regardless of device language, so the point here is only to
  /// match the platform's 12/24-hour convention.
  static final _timeFormat = intl.DateFormat.jm(
    WidgetsBinding.instance.platformDispatcher.locale.toString(),
  );

  @override
  void dispose() {
    _now.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCachedHijri();
    _loadCachedLocation();
  }

  Future<void> _loadCachedHijri() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_hijri_date') ?? '';
    if (cached.isNotEmpty && mounted) {
      setState(() => _cachedHijri = cached);
    }
  }

  // Reads the same cached location PrayerTimeScreen already fetches/writes —
  // no new GPS/geocoding call, just displaying what's already known.
  Future<void> _loadCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final city = prefs.getString('city_name') ?? '';
    final country = prefs.getString('country_name') ?? '';
    if ((city.isNotEmpty || country.isNotEmpty) && mounted) {
      setState(() {
        _city = city;
        _country = country;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    // ClockPainter maps `size` directly to visible diameter (see
    // AnalogClockView.dart), so this is close to the actual on-screen size.
    //
    // Driven by the *shorter* side and capped: keyed to width alone, a
    // landscape phone or a tablet produced a clock taller than the viewport,
    // pushing the arch card past the bottom of the screen with an unbounded
    // Column above it — a guaranteed overflow rather than a scroll.
    final clockSize = (screenSize.shortestSide * 0.52).clamp(120.0, 260.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // Black icons on Android
        statusBarBrightness: Brightness.light, // Black icons on iOS
      ),
      child: Scaffold(
        // Shared navy glow + pattern, replacing the old flat fill and the
        // full-bleed Vector.svg this screen used to stack itself.
        body: AppBackground(
          child: Column(
              children: [
                // The card sizes itself to its own content (status-bar
                // clearance + clock + a little breathing room) instead of a
                // manually predicted height — it can't drift out of sync
                // with the clock's actual size on a given device.
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    // The "arch" gradient — light at the top easing down,
                    // instead of one flat near-white fill.
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.archTop,
                        AppColors.archMid,
                        AppColors.archBottom,
                      ],
                    ),
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.only(
                      bottomRight: Radius.circular(70),
                      bottomLeft: Radius.circular(70),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: statusBarHeight + 24),
                      Analogclockview(
                        size: clockSize,
                        onTick: (time) => _now.value = time,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Distribute some of the leftover space above the
                      // content instead of dumping all of it below — capped
                      // so it doesn't balloon into an equally-odd gap on
                      // very tall screens/tablets.
                      final topSpacing = (constraints.maxHeight * 0.12).clamp(
                        20.0,
                        56.0,
                      );
                      return SingleChildScrollView(
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Column(
                            children: [
                              SizedBox(height: topSpacing),
                              _buildTimeDateRow(context),
                              const SizedBox(height: 24),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                child: NextPrayerCard(),
                              ),
                              const SizedBox(height: 16),
                              _buildLocationRow(),
                              // The countdown above is driven by cached times
                              // when we're offline; this is what says so.
                              const OfflineBanner(),
                              // Clears the floating bottom nav bar
                              // (MainScreen's Scaffold uses extendBody: true).
                              const SizedBox(height: 100),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeDateRow(BuildContext context) {
    final hijri = ref
        .watch(prayerTimesProvider)
        .when(
          loading: () => _cachedHijri,
          error: (_, __) => _cachedHijri,
          data: (data) {
            if (data.dateOnHijri.isNotEmpty &&
                data.dateOnHijri != _cachedHijri) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _cachedHijri = data.dateOnHijri);
                }
              });
            }
            return data.dateOnHijri;
          },
        );

    return Column(
      children: [
        ValueListenableBuilder<DateTime>(
          valueListenable: _now,
          builder:
              (context, now, _) => Text(
                _timeFormat.format(now),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'cairo',
                  color: _contentColor,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
        ),
        if (hijri.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            hijri,
            style: const TextStyle(
              fontFamily: 'cairo',
              color: _mutedColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationRow() {
    if (_city.isEmpty && _country.isEmpty) return const SizedBox.shrink();
    final label = [_city, _country].where((s) => s.isNotEmpty).join('، ');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/locationIcon.png',
          width: 14,
          height: 14,
          color: _mutedColor,
          colorBlendMode: BlendMode.srcIn,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'cairo',
            color: _mutedColor,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
