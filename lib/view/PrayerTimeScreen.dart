import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:myadhan/services/app_config.dart';
import 'package:myadhan/services/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' as intl;
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:myadhan/view/AppErrorView.dart';
import 'package:myadhan/view/AppShimmer.dart';
import 'package:myadhan/view/AppToast.dart';
import 'package:myadhan/view/AccentCard.dart';
import 'package:myadhan/view/CountDown.dart';
import 'package:myadhan/view/OfflineBanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The same asymmetric shape on every prayer row (not just the next one) —
/// "only some corners rounded, and by a lot," echoing the Home screen's clock
/// card and NextPrayerCard. The next row is still distinguished by its accent
/// edge + glow + color, not by having a different silhouette from its
/// siblings.
///
/// File-level rather than private to `_AnimatedPrayerCardState` so the
/// loading skeleton can draw placeholders in the exact shape of the rows they
/// stand in for — one definition, so the two can't drift apart.
const _rowRadius = BorderRadius.only(
  topLeft: Radius.circular(24),
  topRight: Radius.circular(12),
  bottomLeft: Radius.circular(12),
  bottomRight: Radius.circular(24),
);

/// Shared scale+fade entrance used by both dialogs on this screen — was
/// previously duplicated verbatim in each `showGeneralDialog` call.
Widget _dialogTransitionBuilder(
  BuildContext context,
  Animation<double> primaryAnimation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curve = CurvedAnimation(
    parent: primaryAnimation,
    curve: Curves.easeInOutCubic,
  );
  return ScaleTransition(
    scale: Tween<double>(begin: 0.85, end: 1.0).animate(curve),
    child: FadeTransition(opacity: curve, child: child),
  );
}

/// Same scale+opacity tap feedback used by the prayer rows (0.96 scale,
/// 70% opacity, 150ms easeOutCubic) — used here to replace stock Material
/// ripple/ink effects in the dialogs, which read as harsh/generic against
/// the app's flat, dark palette. One tactile language app-wide.
class _TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _TapScale({required this.child, this.onTap});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp:
          widget.onTap == null
              ? null
              : (_) {
                setState(() => _pressed = false);
                widget.onTap!();
              },
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.82 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Disables Material's ink/splash system for everything inside.
///
/// The stock ripple is a pale overlay designed for light Material surfaces;
/// on this app's dark navy it reads as a harsh white flash. Killing it at
/// the theme level (rather than per-widget) also covers the splashes baked
/// into stock widgets we don't build ourselves — the `TextField`, the
/// `Switch`, and `AlertDialog`'s own internals — which is why setting
/// `splashColor: transparent` on individual widgets wasn't enough.
Widget _noInk(BuildContext context, Widget child) {
  return Theme(
    data: Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
    ),
    child: child,
  );
}

/// Dialog shape/background shared by both dialogs on this screen — was
/// previously only the background color; different primary-action styling
/// (a bright white pill on one, plain text on the other) made the two
/// dialogs feel like they belonged to different apps.
const _dialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(24)),
);

/// Lowest-emphasis dialog action (e.g. "إلغاء").
Widget _dialogTextAction({
  required String label,
  required VoidCallback onTap,
  Color color = AppColors.secondary,
  FontWeight weight = FontWeight.w500,
}) {
  return _TapScale(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'cairo',
          color: color,
          fontSize: 14,
          fontWeight: weight,
        ),
      ),
    ),
  );
}

/// The one filled action per dialog (GPS / Save) — shared "this is the
/// primary action" language both dialogs now use. Deliberately near-white
/// (`#F0F8FF`), not the accent blue: blue is reserved for "this is the
/// selected/active state" (a switch that's on, a chosen radio) — reusing it
/// again here for an unrelated "primary button" role diluted that meaning
/// and, with 3-4 blue elements in one small dialog, read as repetitive
/// rather than intentional.
Widget _dialogPrimaryButton({
  required String label,
  required VoidCallback onTap,
  IconData? icon,
}) {
  return _TapScale(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.body,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.surface, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'cairo',
              color: AppColors.surface,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

class PrayerTimeScreen extends ConsumerStatefulWidget {
  const PrayerTimeScreen({super.key});

  @override
  ConsumerState<PrayerTimeScreen> createState() => _PrayerTimeState();
}

/// The five prayers, in order, under the Arabic names used as the
/// `adhan_enabled_*` / `adhan_sound_*` preference-key suffixes.
const _prayerNames = ['الفجر', 'الظهر', 'العصر', 'المغرب', 'العشاء'];

/// How a prayer announces itself: the Adhan, a vibration, or nothing.
///
/// Stored as **two** booleans rather than one three-valued key, and the split
/// is deliberate. `adhan_enabled_*` already gates whether an alarm is armed at
/// all (`AlarmSchedulerHelper.rescheduleAllFromPrefs` on the native side skips
/// disabled prayers entirely), so [vibrate] has to keep it `true` — otherwise
/// there'd be no alarm left to vibrate from. `adhan_vibrate_*` then chooses
/// what happens once it fires.
///
/// The split also means installs that predate this feature carry no
/// `adhan_vibrate_*` key at all, read `false`, and behave exactly as before.
///
/// **`PrayerAlarmReceiver.kt` reads both keys by these exact names.** Nothing
/// checks that across the language boundary — see CLAUDE.md.
enum _AdhanAlertMode {
  sound,
  vibrate,
  silent;

  static _AdhanAlertMode from({required bool enabled, required bool vibrate}) {
    if (!enabled) return _AdhanAlertMode.silent;
    return vibrate ? _AdhanAlertMode.vibrate : _AdhanAlertMode.sound;
  }

  bool get enabled => this != _AdhanAlertMode.silent;

  /// Named to avoid colliding with the [vibrate] enum value itself, and to
  /// match `vibrateOnly` in PrayerAlarmReceiver.kt.
  bool get vibrateOnly => this == _AdhanAlertMode.vibrate;

  /// Tapping the row's icon walks sound → vibrate → silent → sound, the same
  /// order (and the same direction) as a phone's own ringer-mode key, so the
  /// control behaves the way the gesture already implies.
  _AdhanAlertMode get next => switch (this) {
    _AdhanAlertMode.sound => _AdhanAlertMode.vibrate,
    _AdhanAlertMode.vibrate => _AdhanAlertMode.silent,
    _AdhanAlertMode.silent => _AdhanAlertMode.sound,
  };

  String get iconAsset => switch (this) {
    _AdhanAlertMode.sound => 'assets/audioOnIcon.png',
    _AdhanAlertMode.vibrate => 'assets/vibrationIcon.png',
    _AdhanAlertMode.silent => 'assets/audioOffIcon.png',
  };

  /// Spoken by TalkBack, and the reason the row is more than a mute toggle —
  /// it has to say which of the three states is current, not just on/off.
  String semanticsLabel(String prayerName) => switch (this) {
    _AdhanAlertMode.sound => 'أذان $prayerName: صوت. اضغط للاهتزاز',
    _AdhanAlertMode.vibrate => 'أذان $prayerName: اهتزاز. اضغط للكتم',
    _AdhanAlertMode.silent => 'أذان $prayerName: صامت. اضغط للصوت',
  };

  /// Confirmation toast copy, so the change is legible without the user
  /// having to interpret a small glyph that just swapped.
  String toastFor(String prayerName) => switch (this) {
    _AdhanAlertMode.sound => 'سيؤذّن $prayerName بالصوت',
    _AdhanAlertMode.vibrate => 'سينبّه $prayerName بالاهتزاز',
    _AdhanAlertMode.silent => 'تم كتم أذان $prayerName',
  };
}

class _PrayerTimeState extends ConsumerState<PrayerTimeScreen> {
  static const _nativeChannel = MethodChannel('com.myadhan/notification');

  String _countryText = 'الموقع...';
  String _cityText = '';

  /// Per-prayer alert mode (sound / vibrate / silent), mirrored into state.
  ///
  /// This used to be five `Future<bool>`s handed to five `FutureBuilder`s —
  /// but they were *created inside `build`*, so every rebuild of this screen
  /// (a countdown rolling over, a row toggling, a refresh landing) produced
  /// five brand-new futures. A `FutureBuilder` handed a new future resets to
  /// `ConnectionState.waiting` with no data, so each mute icon fell back to
  /// its `?? true` default and visibly flickered from muted to unmuted and
  /// back on every one of those rebuilds. Reading once and keeping the answer
  /// removes both the flicker and the repeated async platform reads.
  Map<String, _AdhanAlertMode> _alertModes = const {};

  @override
  void initState() {
    super.initState();
    _loadSavedLocation();
    _refreshAdhanFlags();
  }

  /// Re-reads every `adhan_enabled_*` / `adhan_vibrate_*` pair and rebuilds
  /// with the result. Called on entry and after anything that writes them.
  Future<void> _refreshAdhanFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final modes = {
      for (final name in _prayerNames)
        name: _AdhanAlertMode.from(
          enabled: prefs.getBool('adhan_enabled_$name') ?? true,
          vibrate: prefs.getBool('adhan_vibrate_$name') ?? false,
        ),
    };
    if (!mounted) return;
    setState(() => _alertModes = modes);
  }

  /// Writes both halves of [mode] for [prayerName] and re-arms the alarms.
  ///
  /// Both keys are always written, never just the one that changed: leaving a
  /// stale `adhan_vibrate_*` behind is how "silent" would come back as
  /// "vibrate" the next time the prayer was re-enabled.
  Future<void> _setAlertMode(String prayerName, _AdhanAlertMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('adhan_enabled_$prayerName', mode.enabled);
    await prefs.setBool('adhan_vibrate_$prayerName', mode.vibrateOnly);

    await _refreshAdhanFlags();

    // Re-arm so the native side picks the change up immediately rather than
    // at the next day rollover.
    final prayerTimesAsync = ref.read(prayerTimesProvider);
    if (prayerTimesAsync.hasValue) {
      await PrayerAlarmScheduler.scheduleAllPrayersWithData(
        prayerTimesAsync.value!,
      );
    }

    if (!mounted) return;
    AppToast.success(context, mode.toastFor(prayerName));
  }

  /// Nominatim's usage policy asks every client for a User-Agent that
  /// identifies the application *and* carries a contact address, so they can
  /// reach someone before blocking a misbehaving client. The two call sites
  /// here sent two different strings ('Adhani-App/1.0' and 'AdhanUK-App/1.0'),
  /// neither with a contact.
  static const _nominatimHeaders = {
    'User-Agent': 'Adhani/${AppConfig.version} (${AppConfig.supportEmail})',
  };

  /// How long any of the name-lookup services get before we stop waiting.
  ///
  /// None of these calls had a timeout. On a device with Wi-Fi associated but
  /// no route they hang until the OS gives up, which is long enough that the
  /// user assumes the app is broken.
  static const _geocodeTimeout = Duration(seconds: 8);

  Future<void> _loadLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();

      // save location (same keys the rest of the app uses)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_latitude', position.latitude);
      await prefs.setDouble('last_longitude', position.longitude);

      // Naming the place is a nicety; having the times is the point. So the
      // lookup gets its own try/catch and the fetch below runs either way —
      // previously a failed reverse geocode threw past the fetch entirely, so
      // an offline first run never even asked for prayer times.
      await _resolvePlaceName(prefs, position.latitude, position.longitude);

      // Refresh prayer times with GPS coordinates
      ref
          .read(prayerTimesProvider.notifier)
          .fetchPrayerTimes(lat: position.latitude, lng: position.longitude);
    } catch (e) {
      logDebug("Error: $e");
    }
  }

  /// Best-effort city/country name for the header. Never throws: the caller's
  /// job (fetching prayer times) does not depend on it succeeding.
  Future<void> _resolvePlaceName(
    SharedPreferences prefs,
    double latitude,
    double longitude,
  ) async {
    // Get Arabic location names via Nominatim reverse geocoding
    try {
      final geoUri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1&accept-language=ar',
      );
      final geoResponse = await http
          .get(geoUri, headers: _nominatimHeaders)
          .timeout(_geocodeTimeout);
      if (geoResponse.statusCode == 200) {
        final geoData = json.decode(geoResponse.body);
        final address = geoData['address'] as Map<String, dynamic>?;
        if (address != null) {
          String country = address['country'] as String? ?? '';
          String city =
              address['city'] as String? ??
              address['town'] as String? ??
              address['village'] as String? ??
              address['state'] as String? ??
              '';

          await prefs.setString('country_name', country);
          await prefs.setString('city_name', city);
          _updateLocation(country, city);
          return;
        }
      }
    } catch (e) {
      logDebug('⚠️ Nominatim reverse geocode failed: $e');
    }

    // Fallback to geocoding package if Nominatim fails. Note this is also
    // network-backed on Android, so offline it fails too — hence the final
    // fallback to whatever name we stored last time.
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(_geocodeTimeout);
      if (placemarks.isNotEmpty) {
        String country = placemarks[0].country ?? '';
        String city = placemarks[0].locality ?? '';
        await prefs.setString('country_name', country);
        await prefs.setString('city_name', city);
        _updateLocation(country, city);
        return;
      }
    } catch (e) {
      logDebug('⚠️ Platform geocoder failed: $e');
    }

    // Keep the last known name rather than leaving the header on 'الموقع...'
    final savedCountry = prefs.getString('country_name');
    if (savedCountry != null) {
      _updateLocation(savedCountry, prefs.getString('city_name') ?? '');
    }
  }

  // set saved location if it exist
  Future<void> _loadSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedCountry = prefs.getString('country_name');
    String? savedCity = prefs.getString('city_name');

    if (savedCountry != null) {
      _updateLocation(savedCountry, savedCity ?? '');
    } else {
      // if location not available , search for it
      _loadLocation();
    }
  }

  void _updateLocation(String country, String city) {
    if (mounted) {
      setState(() {
        _countryText = country;
        _cityText = city;
      });
    }
  }

  int _getNextPrayerIndex(List<({String name, String time})> prayers) {
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;

    for (int i = 0; i < prayers.length; i++) {
      final parts = prayers[i].time.split(':');
      final prayerMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);

      int iqamaDelay = prayers[i].name == 'المغرب' ? 15 : 30;
      final iqamaLimitMinutes = prayerMinutes + iqamaDelay;

      if (nowMinutes < iqamaLimitMinutes) {
        return i;
      }
    }
    return 0;
  }

  List<({String name, String time})> _buildPrayersList(PrayerTimeModel data) {
    final fmt = intl.DateFormat('HH:mm');
    return [
      (name: 'الفجر', time: fmt.format(data.fajer)),
      (name: 'الظهر', time: fmt.format(data.dhuhr)),
      (name: 'العصر', time: fmt.format(data.asr)),
      (name: 'المغرب', time: fmt.format(data.maghrib)),
      (name: 'العشاء', time: fmt.format(data.isha)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final prayerTimesAsync = ref.watch(prayerTimesProvider);

    return Scaffold(
      body: prayerTimesAsync.when(
        // A refresh that's happening over times we already have must not blank
        // them out — offline, that refresh is going to fail, and the user would
        // watch correct times turn into a skeleton and then an error screen.
        // The provider keeps the previous value on the loading state so this
        // hands it straight back to `data`.
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => _buildLoadingState(),
        error: (error, _) => _buildErrorState(error),
        data: (data) => _buildSuccessState(data),
      ),
    );
  }

  /// A skeleton of the real list rather than a centred spinner.
  ///
  /// This wait isn't instant — the provider starts in `loading` and has to
  /// resolve GPS, reverse-geocode it and hit the Aladhan API before any row
  /// exists — so showing the shape of what's coming beats a spinner that
  /// says nothing about it. Metrics deliberately mirror `_buildSuccessState`
  /// (same top spacing, same 16/20 gaps, same row height, same `_rowRadius`,
  /// same 12/16 margins) so nothing jumps when the real content swaps in.
  Widget _buildLoadingState() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // The old loading state painted a flat navy Container, so entering
        // this tab flashed a solid colour before the gradient and pattern
        // appeared behind the loaded list.
        body: AppBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final topSpacing = (constraints.maxHeight * 0.04).clamp(
                  16.0,
                  36.0,
                );
                return AppShimmer(
                  child: Column(
                    children: [
                      SizedBox(height: topSpacing),
                      // Mirrors _buildLocationHeader's own structure — same
                      // 20 outer / 4x8 inner padding, same RTL direction, so
                      // the pin lands on the right and the city/country
                      // column starts exactly where the real text does.
                      // (It used to be a centred Row, which is why the
                      // placeholders jumped sideways on load.)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                // The 32px location pin.
                                const ShimmerBox(
                                  width: 32,
                                  height: 32,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(10),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // City — 28sp bold.
                                        ShimmerBox(width: 140, height: 26),
                                        SizedBox(width: 8),
                                        // The 17px edit affordance.
                                        ShimmerBox(
                                          width: 17,
                                          height: 17,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(5),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 6),
                                    // Country — 16sp.
                                    ShimmerBox(width: 96, height: 15),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDivider(),
                      const SizedBox(height: 20),
                      ...List.generate(
                        5,
                        // 80, not 72: the row's 48px mute-icon touch target
                        // plus its 16px vertical padding top and bottom is
                        // what actually sets the height.
                        (_) => const Padding(
                          padding: EdgeInsets.only(
                            bottom: 16,
                            right: 12,
                            left: 12,
                          ),
                          child: ShimmerBox(
                            height: 80,
                            borderRadius: _rowRadius,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    // Was `Text('$error')` — the raw exception object, so a failed request
    // surfaced to the user as "Exception: API request failed: 500".
    // AppErrorView classifies it and says something actionable instead.
    return AppErrorView(
      error: error,
      onRetry: () => ref.read(prayerTimesProvider.notifier).refresh(),
    );
  }

  Widget _buildSuccessState(PrayerTimeModel data) {
    final prayers = _buildPrayersList(data);
    final nextIndex = _getNextPrayerIndex(prayers);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // White icons on Android
        statusBarBrightness: Brightness.dark, // White icons on iOS
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // AppBackground replaces the old flat-color + Vector.svg pair with
        // the shared navy glow gradient and diagonal pattern overlay.
        body: AppBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Same reasoning as the Home screen: give some of the
                // leftover space to the top instead of dumping all of it
                // below the last row — capped so it doesn't overcorrect
                // into an odd gap on very tall screens/tablets.
                final topSpacing = (constraints.maxHeight * 0.04).clamp(
                  16.0,
                  36.0,
                );
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(height: topSpacing),
                      _buildLocationHeader(),
                      // Says these times came from the cache, without
                      // hiding them. Collapses to nothing when we're synced.
                      const OfflineBanner(),
                      const SizedBox(height: 16),
                      _buildDivider(),
                      const SizedBox(height: 20),
                      ...prayers.asMap().entries.map(
                        (e) => _buildPrayerCard(
                          e.value.name,
                          e.value.time,
                          e.key == nextIndex,
                          e.key < nextIndex,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        // _TapScale rather than InkWell — the last stock Material tap
        // surface on this screen; now the header presses with the same
        // scale/fade language as every row and dialog control.
        child: _TapScale(
          onTap: _showLocationDialog,
          child: Semantics(
            button: true,
            label: 'تغيير الموقع، $_cityText، $_countryText',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/locationIcon.png',
                      width: 32,
                      height: 32,
                      color: AppColors.body,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _cityText.isNotEmpty
                                      ? _cityText
                                      : _countryText,
                                  style: const TextStyle(
                                    color: AppColors.body,
                                    fontFamily: 'cairo',
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // A small rounded-square badge around the
                              // pencil rather than a bare glyph floating next
                              // to the text — reads as a tappable control
                              // instead of a stray icon, and matches the
                              // soft-tinted badge treatment used elsewhere
                              // (e.g. the troubleshoot items in Settings).
                              Container(
                                width: 26,
                                height: 26,
                                // Load-bearing, not cosmetic. A sized
                                // Container passes *tight* constraints down,
                                // and an Image sizes itself from its
                                // constraints — so `width: 14` below was
                                // being overridden and the pen rendered at
                                // the full 26x26, filling the badge. Setting
                                // an alignment is what makes Container loosen
                                // the child's constraints so its own size is
                                // honoured. The Icon this replaced never hit
                                // this: an icon's glyph is sized by fontSize,
                                // not by layout, so it ignored the tight
                                // constraint entirely.
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.accentFillSoft,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: AppColors.accentBorderSoft,
                                  ),
                                ),
                                child: Image.asset(
                                  'assets/editIcon.png',
                                  width: 14,
                                  height: 14,
                                  color: AppColors.heading,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                            ],
                          ),
                          if (_cityText.isNotEmpty && _countryText.isNotEmpty)
                            Text(
                              _countryText,
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontFamily: 'cairo',
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // A soft, edge-faded hairline rather than a hard full-width rule — reads
  // as a quiet section break instead of a heavy structural divider.
  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            AppColors.cardBorder,
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  void _showLocationDialog() {
    final cityController = TextEditingController();
    List<Map<String, dynamic>> suggestions = [];
    bool isSearching = false;
    // Without this, every keystroke fired its own Nominatim request and
    // rebuild — visibly stuttery while typing, and prone to out-of-order
    // responses overwriting newer ones.
    Timer? debounceTimer;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: AppColors.scrim,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: _dialogTransitionBuilder,
      pageBuilder:
          (context, animation, secondaryAnimation) => _noInk(
            context,
            StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    backgroundColor: AppColors.sheetBottom,
                    // Material 3 applies a default tinted overlay on dialogs
                    // unless explicitly disabled — without this, the same
                    // background color can render slightly differently
                    // depending on context, which is why the two dialogs
                    // didn't actually match despite using the same hex.
                    surfaceTintColor: Colors.transparent,
                    shape: _dialogShape,
                    title: const Text(
                      'تغيير الموقع',
                      style: TextStyle(
                        color: AppColors.body,
                        fontFamily: 'cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                        ),
                        child: SizedBox(
                          width: double.maxFinite,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 24),
                                TextField(
                                  controller: cityController,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: AppColors.body),
                                  decoration: InputDecoration(
                                    hintText: 'أدخل اسم المدينة (بالإنجليزية)',
                                    hintStyle: const TextStyle(
                                      color: AppColors.secondary,
                                      fontFamily: 'cairo',
                                      fontSize: 16,
                                    ),
                                    suffixIcon:
                                        isSearching
                                            ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: Padding(
                                                padding: EdgeInsets.all(12),
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 1,
                                                      color:
                                                          AppColors.secondary,
                                                    ),
                                              ),
                                            )
                                            : null,
                                    enabledBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.label,
                                      ),
                                    ),
                                    focusedBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.body,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    debounceTimer?.cancel();
                                    if (value.length < 3) {
                                      setDialogState(() => suggestions = []);
                                      return;
                                    }
                                    debounceTimer = Timer(
                                      const Duration(milliseconds: 400),
                                      () async {
                                        setDialogState(
                                          () => isSearching = true,
                                        );
                                        try {
                                          // Use Nominatim API for better city suggestions
                                          final uri = Uri.parse(
                                            'https://nominatim.openstreetmap.org/search?q=$value&format=json&limit=5&addressdetails=1&accept-language=ar',
                                          );
                                          final response = await http
                                              .get(
                                                uri,
                                                headers: _nominatimHeaders,
                                              )
                                              .timeout(_geocodeTimeout);
                                          if (!context.mounted) return;
                                          if (response.statusCode == 200) {
                                            final List<dynamic> data = json
                                                .decode(response.body);
                                            final List<Map<String, dynamic>>
                                            results =
                                                data.map((item) {
                                                  final address =
                                                      item['address']
                                                          as Map<
                                                            String,
                                                            dynamic
                                                          >? ??
                                                      {};
                                                  final city =
                                                      address['city']
                                                          as String? ??
                                                      address['town']
                                                          as String? ??
                                                      address['village']
                                                          as String? ??
                                                      address['state']
                                                          as String? ??
                                                      (item['display_name']
                                                              as String)
                                                          .split(',')
                                                          .first
                                                          .trim();
                                                  final country =
                                                      address['country']
                                                          as String? ??
                                                      '';
                                                  return {
                                                    'city': city,
                                                    'country': country,
                                                    'lat': double.parse(
                                                      item['lat'] as String,
                                                    ),
                                                    'lon': double.parse(
                                                      item['lon'] as String,
                                                    ),
                                                  };
                                                }).toList();
                                            setDialogState(() {
                                              suggestions = results;
                                              isSearching = false;
                                            });
                                          } else {
                                            setDialogState(() {
                                              suggestions = [];
                                              isSearching = false;
                                            });
                                          }
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          setDialogState(() {
                                            suggestions = [];
                                            isSearching = false;
                                          });
                                          // An empty list used to be the only
                                          // signal here, so "we can't reach the
                                          // search service" looked exactly like
                                          // "no city by that name" — and the user
                                          // retyped their own city over and over.
                                          AppToast.error(
                                            context,
                                            'تعذّر البحث عن المدينة',
                                            detail:
                                                'تحقّق من اتصالك بالشبكة ثم أعد المحاولة',
                                          );
                                          logWarning('City search failed', e);
                                        }
                                      },
                                    );
                                  },
                                ),
                                if (suggestions.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 200,
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: suggestions.length,
                                      itemBuilder: (context, index) {
                                        final loc = suggestions[index];
                                        final cityName = loc['city'] as String;
                                        final countryName =
                                            loc['country'] as String;
                                        return _TapScale(
                                          onTap: () async {
                                            Navigator.pop(context);
                                            final lat = loc['lat'] as double;
                                            final lon = loc['lon'] as double;
                                            // Save location and names
                                            final prefs =
                                                await SharedPreferences.getInstance();
                                            await prefs.setDouble(
                                              'last_latitude',
                                              lat,
                                            );
                                            await prefs.setDouble(
                                              'last_longitude',
                                              lon,
                                            );
                                            await prefs.setString(
                                              'country_name',
                                              countryName,
                                            );
                                            await prefs.setString(
                                              'city_name',
                                              cityName,
                                            );

                                            _updateLocation(
                                              countryName,
                                              cityName,
                                            );
                                            ref
                                                .read(
                                                  prayerTimesProvider.notifier,
                                                )
                                                .fetchPrayerTimes(
                                                  lat: lat,
                                                  lng: lon,
                                                );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Image.asset(
                                                  'assets/locationIcon.png',
                                                  width: 20,
                                                  height: 20,
                                                  color: AppColors.secondary,
                                                  colorBlendMode:
                                                      BlendMode.srcIn,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    '$cityName، $countryName',
                                                    style: const TextStyle(
                                                      color: AppColors.body,
                                                      fontFamily: 'cairo',
                                                      fontSize: 14,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                _dialogPrimaryButton(
                                  label: 'استخدم GPS',
                                  icon: Icons.my_location,
                                  onTap: () {
                                    Navigator.pop(context);
                                    _loadLocation();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      _dialogTextAction(
                        label: 'إلغاء',
                        onTap: () => Navigator.pop(context),
                      ),
                      _dialogTextAction(
                        label: 'بحث',
                        color: AppColors.body,
                        weight: FontWeight.w600,
                        onTap: () async {
                          final city = cityController.text.trim();
                          if (city.isNotEmpty) {
                            Navigator.pop(context);
                            await _searchAndSetLocation(city);
                          }
                        },
                      ),
                    ],
                  ),
            ),
          ),
    ).then((_) {
      debounceTimer?.cancel();
      // A TextEditingController holds a listener list and a change
      // notification chain; one leaked per visit to this dialog.
      cityController.dispose();
    });
  }

  Future<void> _searchAndSetLocation(String cityName) async {
    setState(() {
      _countryText = 'جاري البحث...';
      _cityText = cityName;
    });

    try {
      // Search for city coordinates using geocoding. On Android this is the
      // platform Geocoder, which is network-backed — hence the timeout.
      final locations = await locationFromAddress(
        cityName,
      ).timeout(_geocodeTimeout);
      if (locations.isNotEmpty) {
        final location = locations.first;

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_latitude', location.latitude);
        await prefs.setDouble('last_longitude', location.longitude);
        await prefs.setString('manual_city', cityName);

        // Naming it is optional; having its coordinates is not. A failed
        // placemark lookup must not stop the prayer-time fetch below.
        try {
          final placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          ).timeout(_geocodeTimeout);

          if (placemarks.isNotEmpty) {
            _updateLocation(
              placemarks[0].country ?? cityName,
              placemarks[0].locality ?? '',
            );
          } else {
            _updateLocation(cityName, '');
          }
        } catch (e) {
          logWarning('Placemark lookup failed, using typed name', e);
          _updateLocation(cityName, '');
        }

        // Refresh prayer times with manual coordinates
        ref
            .read(prayerTimesProvider.notifier)
            .fetchPrayerTimes(lat: location.latitude, lng: location.longitude);
      } else {
        _restoreLocationLabel();
        if (mounted) {
          AppToast.error(
            context,
            'لم يتم العثور على «$cityName»',
            detail: 'تأكّد من اسم المدينة ثم أعد المحاولة',
          );
        }
      }
    } catch (e) {
      // The failure used to be written into the country slot, so the header
      // read "خطأ في البحث" as though that were a place — permanently, with no
      // way to retry. Say it in a toast and put the real label back.
      logWarning('City lookup failed', e);
      _restoreLocationLabel();
      if (mounted) {
        AppToast.error(
          context,
          'تعذّر البحث عن المدينة',
          detail: 'تحقّق من اتصالك بالشبكة ثم أعد المحاولة',
        );
      }
    }
  }

  /// Puts the header back to the last place we actually knew about, after a
  /// search that went nowhere.
  Future<void> _restoreLocationLabel() async {
    final prefs = await SharedPreferences.getInstance();
    _updateLocation(
      prefs.getString('country_name') ?? 'الموقع...',
      prefs.getString('city_name') ?? '',
    );
  }

  Widget _buildPrayerCard(
    String name,
    String time,
    bool isNext,
    bool isPassed,
  ) {
    return _AnimatedPrayerCard(
      name: name,
      time: time,
      isNext: isNext,
      isPassed: isPassed,
      alertMode: _alertModes[name] ?? _AdhanAlertMode.sound,
      onSoundTap: () => _showSoundDialog(name),
      onCycleAlertMode:
          (mode) => _setAlertMode(name, mode),
      onFinishCountdown: () {
        setState(() {}); // Rebuild the whole screen to move the active card!
      },
    );
  }

  Future<void> _showSoundDialog(String prayerName) async {
    final prefs = await SharedPreferences.getInstance();
    // The dialog is opened after an await, so the screen may already be gone
    // (the user switched tabs, or the app was backgrounded and torn down).
    if (!mounted) return;
    bool isEnabled = prefs.getBool('adhan_enabled_$prayerName') ?? true;
    String selectedSound =
        prefs.getString('adhan_sound_$prayerName') ?? 'adhan1';

    // Preview through the native AdhanPlayer rather than `audioplayers`.
    // That is the same code path the alarm itself uses (ALARM stream, same
    // audio-focus rules), so what the user hears here is what they'll hear at
    // prayer time — and it lets the app stop shipping a second ~7 MB copy of
    // all three recordings as Flutter assets. See MainActivity's
    // `previewAdhan`.
    String? playingSound;

    // Seven recordings from aladhan.com/download-adhans (Islamic Network),
    // replacing the previous three whose provenance wasn't documented. The
    // 'id' is also the literal Android raw-resource name — it's read back
    // directly by RawResourceAndroidNotificationSound in
    // prayer_alarm_scheduler.dart's fallback path, not just through
    // AdhanPlayer.getSoundResId's mapping, so the two must stay identical.
    final sounds = [
      {'id': 'adhan1', 'name': 'مشاري راشد العفاسي'},
      {'id': 'adhan2', 'name': 'أحمد النفيس'},
      {'id': 'adhan3', 'name': 'حافظ مصطفى أوزجان'},
      {'id': 'adhan4', 'name': 'كارل جينكينز'},
      {'id': 'adhan5', 'name': 'مشاري العفاسي — قناة وان دبي'},
      {'id': 'adhan6', 'name': 'مشاري العفاسي — أذان آخر'},
      {'id': 'adhan7', 'name': 'منصور الزهراني'},
    ];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: AppColors.scrim,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: _dialogTransitionBuilder,
      pageBuilder:
          (context, animation, secondaryAnimation) => _noInk(
            context,
            StatefulBuilder(
              builder:
                  (context, setDialogState) => AlertDialog(
                    backgroundColor: AppColors.sheetBottom,
                    // Material 3 applies a default tinted overlay on dialogs
                    // unless explicitly disabled — without this, the same
                    // background color can render slightly differently
                    // depending on context, which is why the two dialogs
                    // didn't actually match despite using the same hex.
                    surfaceTintColor: Colors.transparent,
                    shape: _dialogShape,
                    title: Text(
                      'اشعار $prayerName',
                      style: const TextStyle(
                        color: AppColors.body,
                        fontFamily: 'cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    content: Directionality(
                      textDirection: TextDirection.rtl,
                      // Bounded + scrollable: the list below grew from 3 rows to
                      // 7 (all seven aladhan.com/download-adhans recordings), and
                      // 7 no longer reliably fits an unscrollable AlertDialog
                      // content on shorter screens the way 3 did. Same pattern
                      // as the location dialog above.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        child: SizedBox(
                          width: double.maxFinite,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Enable/Disable toggle — tapping the label
                                // toggles too, but isn't nested inside the same
                                // tap target as the switch itself.
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TapScale(
                                        onTap:
                                            () => setDialogState(
                                              () => isEnabled = !isEnabled,
                                            ),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            'تفعيل الأذان',
                                            style: TextStyle(
                                              color: AppColors.body,
                                              fontFamily: 'cairo',
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: isEnabled,
                                      activeThumbColor: AppColors.accent,
                                      // Switch draws its press/hover state from
                                      // overlayColor, which the theme-level splash
                                      // override doesn't reach — this is the large
                                      // pale halo that appears around the thumb.
                                      overlayColor:
                                          const WidgetStatePropertyAll(
                                            Colors.transparent,
                                          ),
                                      onChanged: (value) {
                                        setDialogState(() => isEnabled = value);
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: AppColors.cardBorder),
                                const SizedBox(height: 4),
                                // Sound selection
                                const Text(
                                  'اختر نغمة الأذان',
                                  style: TextStyle(
                                    color: AppColors.secondary,
                                    fontFamily: 'cairo',
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...sounds.map((sound) {
                                  final isSelected =
                                      selectedSound == sound['id'];
                                  final isPlaying = playingSound == sound['id'];
                                  return _TapScale(
                                    onTap:
                                        isEnabled
                                            ? () => setDialogState(
                                              () =>
                                                  selectedSound = sound['id']!,
                                            )
                                            : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color:
                                                  isSelected
                                                      ? AppColors.accent
                                                      : Colors.transparent,
                                              border: Border.all(
                                                color:
                                                    isSelected
                                                        ? AppColors.accent
                                                        : AppColors.label,
                                                width: 2,
                                              ),
                                            ),
                                            child:
                                                isSelected
                                                    ? const Icon(
                                                      Icons.check,
                                                      size: 14,
                                                      color: AppColors.surface,
                                                    )
                                                    : null,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              sound['name']!,
                                              style: TextStyle(
                                                color:
                                                    isEnabled
                                                        ? AppColors.body
                                                        : AppColors.label,
                                                fontFamily: 'cairo',
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          _TapScale(
                                            onTap: () async {
                                              if (isPlaying) {
                                                await _stopPreview();
                                                setDialogState(
                                                  () => playingSound = null,
                                                );
                                              } else {
                                                setDialogState(
                                                  () =>
                                                      playingSound =
                                                          sound['id'],
                                                );
                                                await _playPreview(
                                                  sound['id']!,
                                                );
                                              }
                                            },
                                            child: Padding(
                                              // 22px icon + 13px padding on every
                                              // side = 48x48, the accessibility
                                              // minimum touch target — smaller
                                              // icon, same tap area.
                                              padding: const EdgeInsets.all(13),
                                              child: Icon(
                                                isPlaying
                                                    ? Icons.stop_circle_outlined
                                                    : Icons.play_circle_outline,
                                                color: AppColors.body,
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      _dialogTextAction(
                        label: 'إلغاء',
                        onTap: () => Navigator.pop(context),
                      ),
                      _dialogTextAction(
                        label: 'تطبيق للكل',
                        color: AppColors.body,
                        weight: FontWeight.w600,
                        onTap: () async {
                          Navigator.pop(context);
                          await _stopPreview();
                          for (final name in _prayerNames) {
                            await prefs.setBool(
                              'adhan_enabled_$name',
                              isEnabled,
                            );
                            await prefs.setString(
                              'adhan_sound_$name',
                              selectedSound,
                            );
                          }
                          await _rescheduleAfterSoundChange();
                          if (!mounted) return;
                          await _refreshAdhanFlags();
                          if (!mounted) return;
                          AppToast.success(
                            // The screen's context, not the dialog's: the
                            // dialog has just been popped, so posting a
                            // SnackBar through its Navigator did nothing.
                            this.context,
                            'تم تطبيق الإعدادات على جميع الصلوات',
                          );
                        },
                      ),
                      // The primary action — same filled-accent language as
                      // the location dialog's GPS button, instead of one
                      // dialog having a bright CTA and the other only text.
                      _dialogPrimaryButton(
                        label: 'حفظ',
                        onTap: () async {
                          Navigator.pop(context);
                          await _stopPreview();
                          await prefs.setBool(
                            'adhan_enabled_$prayerName',
                            isEnabled,
                          );
                          await prefs.setString(
                            'adhan_sound_$prayerName',
                            selectedSound,
                          );

                          await _rescheduleAfterSoundChange();
                          if (!mounted) return;
                          // Refresh UI to show icon change
                          await _refreshAdhanFlags();
                          if (!mounted) return;

                          // Saving used to close the dialog silently, leaving
                          // no confirmation that anything was stored. State
                          // the consequence, not just the outcome.
                          final soundName =
                              sounds.firstWhere(
                                (s) => s['id'] == selectedSound,
                                orElse: () => sounds.first,
                              )['name'] ??
                              '';
                          AppToast.success(
                            this.context,
                            'تم حفظ الإعدادات',
                            detail:
                                isEnabled
                                    ? 'سيؤذّن $prayerName بنغمة «$soundName»'
                                    : 'تم كتم أذان $prayerName',
                          );
                        },
                      ),
                    ],
                  ),
            ),
          ),
    ).then((_) {
      // Stop any preview still playing when the dialog is closed or dismissed.
      _stopPreview();
    });
  }

  /// Re-arms every alarm after a per-prayer sound or mute change.
  Future<void> _rescheduleAfterSoundChange() async {
    final data = ref.read(prayerTimesProvider).value;
    if (data == null) return;
    await PrayerAlarmScheduler.scheduleAllPrayersWithData(data);
  }

  /// Plays [soundId] through the native player used by the alarm itself.
  Future<void> _playPreview(String soundId) async {
    try {
      await _nativeChannel.invokeMethod('previewAdhan', {'soundName': soundId});
    } catch (e) {
      logWarning('Adhan preview failed', e);
      if (mounted) {
        AppToast.error(context, 'تعذّر تشغيل المعاينة');
      }
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _nativeChannel.invokeMethod('stopAdhanPreview');
    } catch (e) {
      logWarning('Could not stop preview', e);
    }
  }
}

class _AnimatedPrayerCard extends StatefulWidget {
  final String name;
  final String time;
  final bool isNext;
  final bool isPassed;
  final _AdhanAlertMode alertMode;
  final VoidCallback onSoundTap;
  final ValueChanged<_AdhanAlertMode> onCycleAlertMode;
  final VoidCallback onFinishCountdown;

  const _AnimatedPrayerCard({
    required this.name,
    required this.time,
    required this.isNext,
    required this.isPassed,
    required this.alertMode,
    required this.onSoundTap,
    required this.onCycleAlertMode,
    required this.onFinishCountdown,
  });

  @override
  State<_AnimatedPrayerCard> createState() => _AnimatedPrayerCardState();
}

class _AnimatedPrayerCardState extends State<_AnimatedPrayerCard> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    // Passed rows drop to the `label` tier — visibly de-emphasized next to
    // upcoming/next rows without becoming unreadable.
    final contentColor = widget.isPassed ? AppColors.label : AppColors.body;
    final timeColor = widget.isPassed ? AppColors.label : AppColors.body;
    final nameColor =
        widget.isNext
            ? AppColors.accent
            : (widget.isPassed ? AppColors.label : AppColors.heading);

    // Children ordered so that, under the RTL Directionality below, the
    // name/time sits at the reading-start (visual right) and the mute
    // icon at the reading-end (visual left) — reproducing the app's
    // existing layout, but as genuine RTL rather than an LTR coincidence.
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Semantics(
            label:
                widget.isNext
                    ? '${widget.name}، الصلاة القادمة، الساعة ${widget.time}'
                    : '${widget.name}، الساعة ${widget.time}',
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: TextStyle(
                      fontFamily: 'cairo',
                      color: nameColor,
                      fontWeight:
                          widget.isNext ? FontWeight.bold : FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.time,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: 'cairo',
                      color: timeColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child:
                  widget.isNext
                      ? Semantics(
                        label: 'الوقت المتبقي',
                        child: CountdownTimer(
                          onFinish: widget.onFinishCountdown,
                        ),
                      )
                      : const SizedBox.shrink(),
            ),
          ),
          Semantics(
            button: true,
            // Three states, so "mute/unmute" no longer describes it — the
            // label has to say which one is current and what a tap does next.
            label: widget.alertMode.semanticsLabel(widget.name),
            child: GestureDetector(
              onTap: () => widget.onCycleAlertMode(widget.alertMode.next),
              child: Padding(
                // 24px icon + 12px padding on every side = 48x48,
                // the accessibility minimum touch target.
                padding: const EdgeInsets.all(12),
                // Cross-fades between the three glyphs instead of hard-cutting
                // — the row already fades its own state changes, and a bare
                // swap next to that read as a glitch.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Image.asset(
                    widget.alertMode.iconAsset,
                    key: ValueKey(widget.alertMode),
                    width: 24,
                    height: 24,
                    // Image.asset's own tinting, not SvgPicture's colorFilter
                    // — these are PNGs (see pubspec.yaml for why), and this is
                    // the directly-analogous API: BlendMode.srcIn replaces
                    // color wherever the source's alpha is non-zero, exactly
                    // like the old Icon() and the SvgPicture attempt before it.
                    color:
                        widget.alertMode == _AdhanAlertMode.silent
                            ? AppColors.label
                            : contentColor,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // No BackdropFilter here — blurring the mostly-flat background behind
    // these rows added real GPU/compositing cost (four simultaneous blur
    // passes, recomposited every frame a dialog opens on top of this list
    // or the next-row glow animates) for almost no visual difference, since
    // there's no complex imagery behind them to actually blur.
    final decoratedRow =
        widget.isNext
            ? AccentCard(borderRadius: _rowRadius, child: row)
            : Container(
              decoration: BoxDecoration(
                color: AppColors.cardFill,
                borderRadius: _rowRadius,
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: row,
            );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 12, left: 12),
      // Isolates this row's own repaints (notably the next row's
      // continuous glow animation) from its siblings and from anything
      // painted above it, e.g. a dialog opening on top of the list —
      // without this, one row's animation can force the compositor to
      // redo unrelated work every frame.
      child: RepaintBoundary(
        child: GestureDetector(
          onTapDown: (_) => setState(() => isPressed = true),
          onTapUp: (_) {
            setState(() => isPressed = false);
            widget.onSoundTap();
          },
          onTapCancel: () => setState(() => isPressed = false),
          child: AnimatedScale(
            scale: isPressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: isPressed ? 0.7 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Directionality(
                textDirection: TextDirection.rtl,
                // A gentle cross-fade when a row's state changes (upcoming
                // → next → passed) instead of a hard cut.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  child: KeyedSubtree(
                    key: ValueKey('${widget.isNext}-${widget.isPassed}'),
                    child: decoratedRow,
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
