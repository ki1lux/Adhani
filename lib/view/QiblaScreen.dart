import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:myadhan/controller/QiblahController.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:myadhan/view/CompassDialPainter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kaaba coordinates, used only to show the user a "distance to Mecca" info
// card — the actual Qibla bearing itself comes from flutter_qiblah, not from
// this.
const double _kaabaLat = 21.4225;
const double _kaabaLon = 39.8262;

class QiblaScreen extends StatefulWidget {
  final bool isActive;
  
  const QiblaScreen({Key? key, this.isActive = true}) : super(key: key);

  @override
  _QiblaScreenState createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  final QiblahController _controller = QiblahController();
  StreamSubscription? _compassSubscription;
  QiblahDirection? _qiblahDirection;

  bool _hasPermission = false;
  bool _loading = true;
  bool _isCompassSupported = true;
  double _lastDirection = 0;
  int _lastHapticTime = 0;
  bool _wasPointingToQibla = false;

  double _lastCompassTurns = 0.0;
  double _lastQiblaTurns = 0.0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _bigAudioPlayer = AudioPlayer();

  double _lastTickDirection = 0;
  int _lastCardinalZone = -1;
  bool _isPlayingTick = false;
  bool _isPlayingBigTick = false;

  double? _distanceToMeccaKm;

  double _getShortestTurns(double oldTurns, double newTurns) {
    double difference = newTurns - oldTurns;
    while (difference < -0.5) difference += 1.0;
    while (difference > 0.5) difference -= 1.0;
    return oldTurns + difference;
  }

  double _degToRad(double deg) => deg * pi / 180.0;

  // Haversine distance, using the same cached last_latitude/last_longitude
  // every other screen already reads (written by PrayerTimeScreen's location
  // flow) — no new GPS/geocoding call of its own.
  Future<void> _loadDistanceToMecca() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('last_latitude');
    final lon = prefs.getDouble('last_longitude');
    if (lat == null || lon == null) return;

    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(_kaabaLat - lat);
    final dLon = _degToRad(_kaabaLon - lon);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat)) *
            cos(_degToRad(_kaabaLat)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    if (mounted) {
      setState(() => _distanceToMeccaKm = earthRadiusKm * c);
    }
  }

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _checkPermission();
    _loadDistanceToMecca();
  }

  @override
  void didUpdateWidget(QiblaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _hasPermission && _isCompassSupported) {
      _startCompass();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopCompass();
    }
  }

  void _startCompass() {
    if (_compassSubscription == null) {
      _compassSubscription = _controller.getQiblaStream().listen((data) {
        if (!mounted) return;
        
        setState(() {
          _qiblahDirection = data as QiblahDirection;
        });
        
        _processCompassAudio(data);
      });
    }
  }

  void _stopCompass() {
    _compassSubscription?.cancel();
    _compassSubscription = null;
  }

  Future<void> _initAudioPlayer() async {
    await _audioPlayer.setSource(AssetSource('audio/effects/compass_ticks.mp3'));
    await _bigAudioPlayer.setSource(AssetSource('audio/effects/big_compass_ticks.mp3'));
  }

  void _processCompassAudio(QiblahDirection qiblahDirection) async {
    final double currentDir = qiblahDirection.direction.toDouble();

      // Calculate current 90-degree quadrant (0..3)
      // We divide by 90 to get quadrant 0(0-89), 1(90-179), 2(180-269), 3(270-359).
      // When moving across a multiple of 90, this integer value will change.
      final int currentCardinalZone = (currentDir.floor() % 360) ~/ 90;

      // Initialize on first valid read
      if (_lastCardinalZone == -1) {
        _lastCardinalZone = currentCardinalZone;
        _lastTickDirection = currentDir;
        return;
      }

      // Check if we crossed a cardinal boundary
      if (currentCardinalZone != _lastCardinalZone) {
        _lastCardinalZone = currentCardinalZone;
        _lastTickDirection =
            currentDir; // Reset small tick origin so it doesn't immediately fire
        if (!_isPlayingBigTick) {
          _isPlayingBigTick = true;
          await _bigAudioPlayer.resume();
          _isPlayingBigTick = false;
        }
      }
      // Otherwise, check for regular 3-degree ticks
      else if ((currentDir - _lastTickDirection).abs() >= 30) {
        _lastTickDirection = currentDir;
        if (!_isPlayingTick) {
          _isPlayingTick = true;
          await _audioPlayer.resume();
          _isPlayingTick = false;
        }
      }
  }

  @override
  void dispose() {
    _stopCompass();
    _audioPlayer.dispose();
    _bigAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    // 1. Check if compass is supported (Android specific check, returns true on iOS)
    final bool? isSupported = await FlutterQiblah.androidDeviceSensorSupport();
    if (isSupported == false) {
      if (mounted) {
        setState(() {
          _isCompassSupported = false;
          _loading = false;
        });
      }
      return;
    }

    // 2. Check if we already have permission
    bool granted = await _controller.hasPermission();

    if (!granted) {
      try {
        // 3. UNCOMMENT this line to show the popup
        // We wrap it in try-catch to stop the crash if it's called twice
        await _controller.init();

        // 4. Check again after the user clicks Allow/Deny
        granted = await _controller.hasPermission();
      } catch (e) {
        // 5. If the error "Already requesting" happens, we ignore it safely.
        print("Popup is already open: $e");
      }
    }

    // 6. Update the UI
    if (mounted) {
      setState(() {
        _hasPermission = granted;
        _isCompassSupported = true;
        _loading = false;
      });
      
      // Start compass only if we have permission, it's supported, and screen is active
      if (_hasPermission && widget.isActive) {
        _startCompass();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.body),
              const SizedBox(height: 24),
              const Text(
                'جاري التحميل...',
                style: TextStyle(
                  color: AppColors.body,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCompassSupported) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.label, size: 64),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "جهازك لا يحتوي على مستشعر البوصلة",
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 16,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, color: AppColors.label, size: 64),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  "يجب السماح بإذن الموقع لاستخدام البوصلة",
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 16,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _checkPermission,
                icon: const Icon(Icons.refresh),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cardFill,
                  foregroundColor: AppColors.body,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // White icons on Android
        statusBarBrightness: Brightness.dark, // White icons on iOS
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // Shared navy glow + pattern, replacing this screen's own
        // flat-fill + full-bleed Vector.svg stack.
        body: AppBackground(
          child: SafeArea(
            child: Builder(
              builder: (context) {
                if (_qiblahDirection == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.body),
                  );
                }

                final qiblahDirection = _qiblahDirection!;

                final double rawDirectionTurns =
                    (qiblahDirection.direction * -1) / 360.0;
                _lastCompassTurns = _getShortestTurns(
                  _lastCompassTurns,
                  rawDirectionTurns,
                );

                final double rawQiblaTurns =
                    (qiblahDirection.qiblah * -1) / 360.0;
                _lastQiblaTurns = _getShortestTurns(
                  _lastQiblaTurns,
                  rawQiblaTurns,
                );

                final double qiblahAngle = qiblahDirection.qiblah;
                final double normalizedQiblah = qiblahAngle % 360;
                final bool isPointingToQibla =
                    (normalizedQiblah < 5 || normalizedQiblah > 355) ||
                    (normalizedQiblah > -5 && normalizedQiblah <= 0);

                if (isPointingToQibla && !_wasPointingToQibla) {
                  HapticFeedback.heavyImpact();
                  _wasPointingToQibla = true;
                } else if (!isPointingToQibla && _wasPointingToQibla) {
                  _wasPointingToQibla = false;
                }

                // Haptic feedback when compass rotates significantly
                final double currentDir = qiblahDirection.direction.toDouble();
                final int now = DateTime.now().millisecondsSinceEpoch;

                // Haptic feedback every 1 degree slightly
                if ((currentDir - _lastDirection).abs() > 1 &&
                    now - _lastHapticTime > 200) {
                  HapticFeedback.lightImpact();
                  _lastDirection = currentDir;
                  _lastHapticTime = now;
                }

                return Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildStatusPill(isPointingToQibla, normalizedQiblah),
                    Expanded(
                      child: Center(
                        child: _buildCompass(
                          qiblahDirection,
                          isPointingToQibla,
                          normalizedQiblah,
                        ),
                      ),
                    ),
                    _buildInfoCards(currentDir),
                    const SizedBox(height: 16),
                    _buildBottomControls(),
                    const SizedBox(height: 10),
                    _buildCalibrationHint(),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundIconButton(
            icon: Icons.help_outline,
            onTap: _showHelpDialog,
          ),
          const Text(
            'اتجاه القبلة',
            style: TextStyle(
              fontFamily: 'cairo',
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: AppColors.heading,
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.sheetTop,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              'كيف تعمل البوصلة؟',
              style: TextStyle(
                fontFamily: 'cairo',
                fontWeight: FontWeight.bold,
                color: AppColors.heading,
              ),
              textAlign: TextAlign.right,
            ),
            content: const Text(
              'وجّه هاتفك للأمام، وستدور البوصلة تلقائيًا. عندما يشير السهم '
              'الأحمر إلى أيقونة الكعبة وتتحول للون الأخضر، فأنت متجه نحو '
              'القبلة. إذا بدت البوصلة غير دقيقة، حرّك هاتفك على شكل رقم ٨ '
              'بعيدًا عن أي معادن.',
              style: TextStyle(
                fontFamily: 'cairo',
                color: AppColors.secondary,
                height: 1.6,
              ),
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'حسنًا',
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildStatusPill(bool isPointingToQibla, double normalizedQiblah) {
    Widget pill;
    if (isPointingToQibla) {
      pill = Container(
        key: const ValueKey('aligned'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 18),
            SizedBox(width: 8),
            Text(
              'أنت متجه نحو القبلة',
              style: TextStyle(
                fontFamily: 'cairo',
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    } else {
      // Shortest-turn instruction: turn right if the bearing is in the
      // near half of the circle, left otherwise — mirrors how the arc/
      // marker already animate via the shortest-turn logic above.
      final turnRight = normalizedQiblah <= 180;
      final degrees = (turnRight ? normalizedQiblah : 360 - normalizedQiblah).round();
      pill = Container(
        key: const ValueKey('turn'),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              turnRight ? Icons.rotate_right : Icons.rotate_left,
              color: AppColors.accent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              turnRight ? 'أدر يمينًا $degrees°' : 'أدر يسارًا $degrees°',
              style: const TextStyle(
                fontFamily: 'cairo',
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: pill);
  }

  Widget _buildCompass(
    QiblahDirection qiblahDirection,
    bool isPointingToQibla,
    double normalizedQiblah,
  ) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double displayQibla = ((normalizedQiblah % 360) + 360) % 360;

    // Same shortest-turn value already driving the marker's own rotation,
    // read directly for the highlighted arc so the two can never drift out
    // of sync with each other.
    double sweepDegrees = (_lastQiblaTurns * 360) % 360;
    if (sweepDegrees > 180) sweepDegrees -= 360;
    if (sweepDegrees < -180) sweepDegrees += 360;

    return SizedBox(
      height: screenWidth + 75,
      width: screenWidth - 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rendered at the same fixed size assets/test.svg used to be
          // (~360x360, unscaled to screen width) — ka3baInCompass.svg's own
          // artwork is offset within an equally-sized canvas, which is what
          // makes it orbit correctly when rotated; keeping this painter the
          // same size keeps that orbit radius matching the ring exactly.
          AnimatedRotation(
            turns: _lastCompassTurns,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: const CustomPaint(
              size: Size(360, 360),
              painter: CompassRingPainter(
                fillColor: AppColors.dialFace,
                ringColor: AppColors.archBottom,
                tickColor: AppColors.onLightSecondary,
                labelColor: AppColors.onLightSecondary,
                cardinalColor: AppColors.onLight,
              ),
            ),
          ),
          CustomPaint(
            size: const Size(360, 360),
            painter: QiblaArcPainter(
              sweepDegrees: sweepDegrees,
              color: AppColors.accent,
            ),
          ),
          AnimatedRotation(
            turns: _lastQiblaTurns,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: SvgPicture.asset("assets/ka3baInCompass.svg"),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SvgPicture.asset("assets/arrow.svg"),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${qiblahDirection.direction.toStringAsFixed(0)}°",
                  style: TextStyle(
                    fontSize: 32,
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.bold,
                    // Identity's success/aligned token (DESIGN_IDENTITY.md
                    // §1) — not Colors.green, which has no home in this
                    // palette. This text sits on the light dial, so its
                    // resting color is the on-light token, not the dark
                    // surface color.
                    color:
                        isPointingToQibla
                            ? AppColors.success
                            : AppColors.onLight,
                  ),
                ),
                const Text(
                  'اتجاهك الحالي',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'cairo',
                    color: AppColors.onLightSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(width: 60, height: 1, color: AppColors.archBottom),
                const SizedBox(height: 10),
                Text(
                  'القبلة ${displayQibla.round()}°',
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.bold,
                    color: AppColors.onLight,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.onLight.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: SvgPicture.asset("assets/ka3baInCompass.svg"),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'القبلة',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'cairo',
                          fontWeight: FontWeight.bold,
                          color: AppColors.onLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCards(double currentDir) {
    final distanceText =
        _distanceToMeccaKm == null
            ? '—'
            : 'كم ${_distanceToMeccaKm!.round()}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _InfoCard(
              icon: Icons.explore_outlined,
              iconColor: AppColors.accent,
              value: '${currentDir.toStringAsFixed(0)}°',
              label: 'اتجاهك الحالي',
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: _InfoCard(
              icon: Icons.signal_cellular_alt,
              iconColor: AppColors.success,
              value: 'عالية',
              label: 'دقة البوصلة',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _InfoCard(
              icon: Icons.near_me_outlined,
              iconColor: AppColors.accent,
              value: distanceText,
              label: 'إلى مكة',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.compass_calibration_outlined,
            onTap: () {},
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                setState(() {
                  _loading = true;
                });
                await Future.delayed(const Duration(milliseconds: 600));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'تم إعادة التهيئة بنجاح.',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          color: AppColors.body,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      duration: const Duration(seconds: 3),
                      // Matches PrayerTimeScreen's snackbar treatment — same
                      // component, same role, same look.
                      backgroundColor: AppColors.sheetTop,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
                _checkPermission();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text(
                'إعادة ضبط القبلة',
                style: TextStyle(fontFamily: 'cairo', fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cardFill,
                foregroundColor: AppColors.body,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                  side: BorderSide(color: AppColors.cardBorder),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        'حرّك هاتفك على شكل رقم ٨ لمعايرة البوصلة، وابعده عن المعادن.',
        style: TextStyle(fontFamily: 'cairo', fontSize: 12, color: AppColors.faint),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardFill,
      shape: const CircleBorder(side: BorderSide(color: AppColors.cardBorder)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppColors.body, size: 20),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'cairo',
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'cairo',
              fontSize: 11,
              color: AppColors.faint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
