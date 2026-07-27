import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' as intl;
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/view/AccentCard.dart';
import 'package:myadhan/view/CountDown.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp:
          widget.onTap == null
              ? null
              : (_) async {
                setState(() => _pressed = false);
                // Let the release animation actually be seen before firing
                // the action — many of these close a dialog or navigate
                // away, and doing that in the same frame as "un-pressing"
                // cut the animation off mid-motion, which read as a harsh
                // flash-cut rather than a smooth press.
                await Future.delayed(const Duration(milliseconds: 90));
                if (mounted) widget.onTap!();
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
  Color color = const Color(0xFFD3E0EC),
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
        color: const Color(0xFFF0F8FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: const Color(0xFF0A2239), size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'cairo',
              color: Color(0xFF0A2239),
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

class _PrayerTimeState extends ConsumerState<PrayerTimeScreen> {
  String _countryText = 'الموقع...';
  String _cityText = '';

  @override
  void initState() {
    super.initState();
    _loadSavedLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();

      // save location (same keys the rest of the app uses)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_latitude', position.latitude);
      await prefs.setDouble('last_longitude', position.longitude);

      // Get Arabic location names via Nominatim reverse geocoding
      try {
        final geoUri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1&accept-language=ar',
        );
        final geoResponse = await http.get(
          geoUri,
          headers: {'User-Agent': 'Adhani-App/1.0'},
        );
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
          }
        }
      } catch (e) {
        // Fallback to geocoding package if Nominatim fails
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          String country = placemarks[0].country ?? '';
          String city = placemarks[0].locality ?? '';
          await prefs.setString('country_name', country);
          await prefs.setString('city_name', city);
          _updateLocation(country, city);
        }
      }

      // Refresh prayer times with GPS coordinates
      ref
          .read(prayerTimesProvider.notifier)
          .fetchPrayerTimes(lat: position.latitude, lng: position.longitude);
    } catch (e) {
      print("Error: $e");
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
        loading: () => _buildLoadingState(),
        error: (error, _) => _buildErrorState(error),
        data: (data) => _buildSuccessState(data),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: const Color(0xff0A2239),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFF0F8FF)),
            SizedBox(height: 24),
            Text(
              'جاري التحميل...',
              style: TextStyle(
                color: Color(0xFFF0F8FF),
                fontFamily: 'cairo',
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    // Not changed automatically per the audit's #10 — see the recommendation
    // in the accompanying explanation for whether an error state should use
    // red at all, given DESIGN_IDENTITY.md reserves it for the Qibla marker.
    return Container(
      color: const Color(0xff0A2239),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'حدث خطأ',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'cairo',
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: const TextStyle(
                color: Colors.red,
                fontFamily: 'cairo',
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _dialogPrimaryButton(
              label: 'إعادة المحاولة',
              onTap: () => ref.read(prayerTimesProvider.notifier).refresh(),
            ),
          ],
        ),
      ),
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
        backgroundColor: const Color(0xff0A2239),
        body: Stack(
          children: [
            SvgPicture.asset(
              'assets/Vector.svg',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
            SafeArea(
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
          ],
        ),
      ),
    );
  }

  Widget _buildLocationHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: InkWell(
          onTap: _showLocationDialog,
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Semantics(
            button: true,
            label: 'تغيير الموقع، $_cityText، $_countryText',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Color(0xFFF0F8FF),
                      size: 32,
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
                                    color: Color(0xFFF0F8FF),
                                    fontFamily: 'cairo',
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.edit,
                                color: Color(0x66F0F8FF),
                                size: 17,
                              ),
                            ],
                          ),
                          if (_cityText.isNotEmpty && _countryText.isNotEmpty)
                            Text(
                              _countryText,
                              style: const TextStyle(
                                color: Color(0xFFD3E0EC),
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
            Color(0x33F0F8FF),
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
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: _dialogTransitionBuilder,
      pageBuilder:
          (context, animation, secondaryAnimation) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  backgroundColor: const Color(0xFF0E2031),
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
                      color: Color(0xFFF0F8FF),
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
                              style: const TextStyle(color: Color(0xFFF0F8FF)),
                              decoration: InputDecoration(
                                hintText: 'أدخل اسم المدينة (بالإنجليزية)',
                                hintStyle: const TextStyle(
                                  color: Color(0xFFD3E0EC),
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
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1,
                                              color: Color(0xFFD3E0EC),
                                            ),
                                          ),
                                        )
                                        : null,
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0x66F0F8FF),
                                  ),
                                ),
                                focusedBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFF0F8FF),
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
                                    setDialogState(() => isSearching = true);
                                    try {
                                      // Use Nominatim API for better city suggestions
                                      final uri = Uri.parse(
                                        'https://nominatim.openstreetmap.org/search?q=$value&format=json&limit=5&addressdetails=1&accept-language=ar',
                                      );
                                      final response = await http.get(
                                        uri,
                                        headers: {
                                          'User-Agent': 'AdhanUK-App/1.0',
                                        },
                                      );
                                      if (!context.mounted) return;
                                      if (response.statusCode == 200) {
                                        final List<dynamic> data = json.decode(
                                          response.body,
                                        );
                                        final List<Map<String, dynamic>>
                                        results =
                                            data.map((item) {
                                              final address =
                                                  item['address']
                                                      as Map<String, dynamic>? ??
                                                  {};
                                              final city =
                                                  address['city'] as String? ??
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
                                    } catch (_) {
                                      if (!context.mounted) return;
                                      setDialogState(() {
                                        suggestions = [];
                                        isSearching = false;
                                      });
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

                                        _updateLocation(countryName, cityName);
                                        ref
                                            .read(prayerTimesProvider.notifier)
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
                                            const Icon(
                                              Icons.location_on,
                                              color: Color(0xFFD3E0EC),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '$cityName، $countryName',
                                                style: const TextStyle(
                                                  color: Color(0xFFF0F8FF),
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
                      color: const Color(0xFFF0F8FF),
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
    ).then((_) {
      debounceTimer?.cancel();
    });
  }

  Future<void> _searchAndSetLocation(String cityName) async {
    setState(() {
      _countryText = 'جاري البحث...';
      _cityText = cityName;
    });

    try {
      // Search for city coordinates using geocoding
      final locations = await locationFromAddress(cityName);
      if (locations.isNotEmpty) {
        final location = locations.first;

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_latitude', location.latitude);
        await prefs.setDouble('last_longitude', location.longitude);
        await prefs.setString('manual_city', cityName);

        // Get place name
        final placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );

        if (placemarks.isNotEmpty) {
          _updateLocation(
            placemarks[0].country ?? cityName,
            placemarks[0].locality ?? '',
          );
        } else {
          _updateLocation(cityName, '');
        }

        // Refresh prayer times with manual coordinates
        ref
            .read(prayerTimesProvider.notifier)
            .fetchPrayerTimes(lat: location.latitude, lng: location.longitude);
      } else {
        _updateLocation('لم يتم العثور', cityName);
      }
    } catch (e) {
      _updateLocation('خطأ في البحث', cityName);
    }
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
      isAdhanEnabledFuture: _isAdhanEnabled(name),
      onSoundTap: () => _showSoundDialog(name),
      onToggleAdhan: (enabled) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('adhan_enabled_$name', enabled);
        setState(() {}); // Refresh parent list
        final prayerTimesAsync = ref.read(prayerTimesProvider);
        if (prayerTimesAsync.hasValue) {
          await PrayerAlarmScheduler.scheduleAllPrayersWithData(
            prayerTimesAsync.value!,
          );
        }
      },
      onFinishCountdown: () {
        setState(() {}); // Rebuild the whole screen to move the active card!
      },
    );
  }

  Future<bool> _isAdhanEnabled(String prayerName) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('adhan_enabled_$prayerName') ?? true;
  }

  void _showSoundDialog(String prayerName) async {
    final prefs = await SharedPreferences.getInstance();
    bool isEnabled = prefs.getBool('adhan_enabled_$prayerName') ?? true;
    String selectedSound =
        prefs.getString('adhan_sound_$prayerName') ?? 'adhan1';

    final audioPlayer = AudioPlayer();
    String? playingSound;

    // Available sounds - add more as you add mp3 files
    final sounds = [
      {'id': 'adhan1', 'name': 'الأذان الأول'},
      {'id': 'adhan2', 'name': 'أذان الثاني'},
      {'id': 'adhan3', 'name': 'أذان الثالث'},
    ];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: _dialogTransitionBuilder,
      pageBuilder:
          (context, animation, secondaryAnimation) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  backgroundColor: const Color(0xFF0E2031),
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
                      color: Color(0xFFF0F8FF),
                      fontFamily: 'cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: Directionality(
                    textDirection: TextDirection.rtl,
                    child: SizedBox(
                      width: double.maxFinite,
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
                                        color: Color(0xFFF0F8FF),
                                        fontFamily: 'cairo',
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Switch(
                                value: isEnabled,
                                activeThumbColor: const Color(0xFF4DB3E5),
                                onChanged: (value) {
                                  setDialogState(() => isEnabled = value);
                                },
                              ),
                            ],
                          ),
                          const Divider(color: Color(0x1AF0F8FF)),
                          const SizedBox(height: 4),
                          // Sound selection
                          const Text(
                            'اختر نغمة الأذان',
                            style: TextStyle(
                              color: Color(0xFFD3E0EC),
                              fontFamily: 'cairo',
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...sounds.map((sound) {
                            final isSelected = selectedSound == sound['id'];
                            final isPlaying = playingSound == sound['id'];
                            return _TapScale(
                              onTap:
                                  isEnabled
                                      ? () => setDialogState(
                                        () => selectedSound = sound['id']!,
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
                                                ? const Color(0xFF4DB3E5)
                                                : Colors.transparent,
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? const Color(0xFF4DB3E5)
                                                  : const Color(0x66F0F8FF),
                                          width: 2,
                                        ),
                                      ),
                                      child:
                                          isSelected
                                              ? const Icon(
                                                Icons.check,
                                                size: 14,
                                                color: Color(0xFF0A2239),
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
                                                  ? const Color(0xFFF0F8FF)
                                                  : const Color(0x66F0F8FF),
                                          fontFamily: 'cairo',
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    _TapScale(
                                      onTap: () async {
                                        if (isPlaying) {
                                          await audioPlayer.stop();
                                          setDialogState(
                                            () => playingSound = null,
                                          );
                                        } else {
                                          await audioPlayer.stop();
                                          setDialogState(
                                            () => playingSound = sound['id'],
                                          );
                                          await audioPlayer.play(
                                            AssetSource(
                                              'audio/${sound['id']}.mp3',
                                            ),
                                          );

                                          audioPlayer.onPlayerComplete.listen((
                                            _,
                                          ) {
                                            if (mounted) {
                                              setDialogState(
                                                () => playingSound = null,
                                              );
                                            }
                                          });
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
                                          color: const Color(0xFFF0F8FF),
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
                  actions: [
                    _dialogTextAction(
                      label: 'إلغاء',
                      onTap: () => Navigator.pop(context),
                    ),
                    _dialogTextAction(
                      label: 'تطبيق للكل',
                      color: const Color(0xFFF0F8FF),
                      weight: FontWeight.w600,
                      onTap: () async {
                        final allPrayers = [
                          'الفجر',
                          'الظهر',
                          'العصر',
                          'المغرب',
                          'العشاء',
                        ];
                        for (final name in allPrayers) {
                          await prefs.setBool('adhan_enabled_$name', isEnabled);
                          await prefs.setString(
                            'adhan_sound_$name',
                            selectedSound,
                          );
                        }
                        Navigator.pop(context);
                        setState(() {});
                        // 🔄 Reschedule with the new unified settings
                        final prayerTimesAsync = ref.read(prayerTimesProvider);
                        if (prayerTimesAsync.hasValue) {
                          await PrayerAlarmScheduler.scheduleAllPrayersWithData(
                            prayerTimesAsync.value!,
                          );
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'تم تطبيق الإعدادات على جميع الصلوات',
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  color: Color(0xFFF0F8FF),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              backgroundColor: const Color(0xFF1A3A5C),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    // The primary action — same filled-accent language as
                    // the location dialog's GPS button, instead of one
                    // dialog having a bright CTA and the other only text.
                    _dialogPrimaryButton(
                      label: 'حفظ',
                      onTap: () async {
                        await prefs.setBool(
                          'adhan_enabled_$prayerName',
                          isEnabled,
                        );
                        await prefs.setString(
                          'adhan_sound_$prayerName',
                          selectedSound,
                        );
                        Navigator.pop(context);
                        setState(() {}); // Refresh UI to show icon change

                        // 🔄 Reschedule notifications with new settings
                        final prayerTimesAsync = ref.read(prayerTimesProvider);
                        if (prayerTimesAsync.hasValue) {
                          await PrayerAlarmScheduler.scheduleAllPrayersWithData(
                            prayerTimesAsync.value!,
                          );
                        }
                      },
                    ),
                  ],
                ),
          ),
    ).then((_) {
      // Clean up the player when dialog is closed/dismissed
      audioPlayer.stop();
      audioPlayer.dispose();
    });
  }
}

class _AnimatedPrayerCard extends StatefulWidget {
  final String name;
  final String time;
  final bool isNext;
  final bool isPassed;
  final Future<bool> isAdhanEnabledFuture;
  final VoidCallback onSoundTap;
  final ValueChanged<bool> onToggleAdhan;
  final VoidCallback onFinishCountdown;

  const _AnimatedPrayerCard({
    required this.name,
    required this.time,
    required this.isNext,
    required this.isPassed,
    required this.isAdhanEnabledFuture,
    required this.onSoundTap,
    required this.onToggleAdhan,
    required this.onFinishCountdown,
  });

  @override
  State<_AnimatedPrayerCard> createState() => _AnimatedPrayerCardState();
}

class _AnimatedPrayerCardState extends State<_AnimatedPrayerCard> {
  bool isPressed = false;

  // The same asymmetric shape on every row (not just the next one) — "only
  // some corners rounded, and by a lot," echoing the Home screen's clock
  // card and NextPrayerCard. The next row is still distinguished by its
  // accent edge + glow + color, not by having a different silhouette from
  // its siblings.
  static const _rowRadius = BorderRadius.only(
    topLeft: Radius.circular(24),
    topRight: Radius.circular(12),
    bottomLeft: Radius.circular(12),
    bottomRight: Radius.circular(24),
  );

  @override
  Widget build(BuildContext context) {
    // Passed-row fade: 45% — visible/legible at a glance while still
    // reading as clearly de-emphasized next to upcoming/next rows.
    final contentColor =
        widget.isPassed ? const Color(0x73F0F8FF) : const Color(0xFFF0F8FF);
    final timeColor =
        widget.isPassed ? const Color(0x73F0F8FF) : const Color(0xFFD3E0EC);
    final nameColor = widget.isNext ? const Color(0xFF4DB3E5) : contentColor;

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
          FutureBuilder<bool>(
            future: widget.isAdhanEnabledFuture,
            builder: (context, snapshot) {
              final enabled = snapshot.data ?? true;
              return Semantics(
                button: true,
                label:
                    enabled
                        ? 'كتم أذان ${widget.name}'
                        : 'تفعيل أذان ${widget.name}',
                child: GestureDetector(
                  onTap: () => widget.onToggleAdhan(!enabled),
                  child: Padding(
                    // 24px icon + 12px padding on every side = 48x48,
                    // the accessibility minimum touch target.
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      enabled ? Icons.volume_up : Icons.volume_off,
                      color: enabled ? contentColor : const Color(0x66F0F8FF),
                    ),
                  ),
                ),
              );
            },
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
            : ClipRRect(
              borderRadius: _rowRadius,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x0DF0F8FF),
                  borderRadius: _rowRadius,
                ),
                child: row,
              ),
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
