import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:myadhan/services/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:myadhan/controller/QiblahController.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:myadhan/view/AppToast.dart';
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

  const QiblaScreen({super.key, this.isActive = true});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
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

  /// Compass render throttle — see [_startCompass].
  static const _minRenderIntervalMs = 16; // ~60 fps
  static const _minRenderDeltaDegrees = 0.4;
  DateTime _lastRenderedAt = DateTime.fromMillisecondsSinceEpoch(0);

  double _getShortestTurns(double oldTurns, double newTurns) {
    double difference = newTurns - oldTurns;
    while (difference < -0.5) {
      difference += 1.0;
    }
    while (difference > 0.5) {
      difference -= 1.0;
    }
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
    // The magnetometer emits far faster than the screen refreshes — on most
    // devices 50-100 events a second. Every one of them used to call
    // `setState` on this whole screen, so the dial, the Kaaba marker, the
    // distance card and the info bar were all rebuilt dozens of times per
    // frame, for a needle that can only move once per frame anyway. Coalescing
    // to ~60 Hz and skipping sub-degree jitter cuts the rebuild count by an
    // order of magnitude with no visible change in smoothness — and stops the
    // compass tab from being the app's biggest CPU (and therefore battery)
    // consumer while it's open.
    _compassSubscription ??= _controller.getQiblaStream().listen((data) {
      if (!mounted) return;
      final direction = data as QiblahDirection;

      final now = DateTime.now();
      final sinceLastFrame =
          now.difference(_lastRenderedAt).inMilliseconds;
      final movedEnough =
          _qiblahDirection == null ||
          (direction.direction - _qiblahDirection!.direction).abs() >=
              _minRenderDeltaDegrees;

      if (sinceLastFrame >= _minRenderIntervalMs && movedEnough) {
        _lastRenderedAt = now;
        setState(() => _qiblahDirection = direction);
      }

      // Audio cues are driven off every sample: they trigger on crossings,
      // which a throttled stream could step straight over.
      _processCompassAudio(direction);
    });
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
        logDebug('Compass permission popup already open: $e');
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
    // Every state shares the same canvas, so entering the screen doesn't
    // flash flat navy before the gradient and pattern appear. The font
    // family is lowercase 'cairo' throughout — the capitalised spelling
    // these states used doesn't match the family declared in pubspec.yaml,
    // so they were silently falling back to the system font.
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: const AppBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.body),
                SizedBox(height: 24),
                Text(
                  'جاري التحميل...',
                  style: TextStyle(
                    color: AppColors.body,
                    fontFamily: 'cairo',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isCompassSupported) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: const AppBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: AppColors.label, size: 56),
                SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    "جهازك لا يحتوي على مستشعر البوصلة",
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 16,
                      fontFamily: 'cairo',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: AppBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_off, color: AppColors.label, size: 56),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    "يجب السماح بإذن الموقع لاستخدام البوصلة",
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 16,
                      fontFamily: 'cairo',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                // Same button treatment as the recalibrate control, so the
                // app has one button family rather than one per screen state.
                _FilledAction(
                  icon: Icons.refresh,
                  label: 'إعادة المحاولة',
                  onTap: _checkPermission,
                ),
              ],
            ),
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

                // Three groups, not seven stacked sections: the header, the
                // task cluster (instruction → marker → dial, which move as
                // one object), and the quiet footer. The instruction lives
                // inside the cluster rather than above it, so the leftover
                // space falls either side of the whole group instead of
                // pooling underneath the dial.
                return Column(
                  children: [
                    _buildHeader(),
                    // The dial is width-bound, so on a tall phone it can
                    // never grow enough to fill the column — there will
                    // always be slack. Expanded owns that slack (which also
                    // keeps the cluster's FittedBox able to scale down on
                    // short screens), and the cluster sits a little above
                    // the midpoint of it: roughly 40% of the slack above,
                    // 60% below. Dead-centre reads as floating and
                    // top-pinned strands the footer.
                    Expanded(
                      child: _buildTaskCluster(
                        qiblahDirection,
                        isPointingToQibla,
                        normalizedQiblah,
                      ),
                    ),
                    _buildFooter(displayQibla: normalizedQiblah),
                    const SizedBox(height: 28),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // One composition rule, applied top and bottom: information sits on the
  // reading-start side (right, in RTL), actions sit on the far side. That
  // gives the page a consistent off-centre axis without the layout looking
  // arbitrarily nudged — the compass stays the only centred thing.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // A plain icon target, not another bordered surface — a utility
          // affordance shouldn't carry the same weight as a real button.
          IconButton(
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.help_outline, size: 20),
            color: AppColors.faint,
            splashRadius: 22,
            tooltip: 'كيف تعمل البوصلة؟',
          ),
          const Text(
            'اتجاه القبلة',
            style: TextStyle(
              fontFamily: 'cairo',
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.body,
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
            backgroundColor: AppColors.sheetBottom,
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

  /// The one thing the user is here to read. Deliberately unadorned — no
  /// pill, no border, no glow — because the surrounding surfaces were what
  /// made it read as another badge instead of an instruction. Size and
  /// colour alone carry it, so state is legible without decoration: white
  /// while the user still has to move, the success token once they're
  /// aligned.
  Widget _buildInstruction(bool isPointingToQibla, double normalizedQiblah) {
    // Shortest-turn instruction: turn right if the bearing is in the near
    // half of the circle, left otherwise — mirrors how the arc/marker
    // already animate via the shortest-turn logic above.
    final turnRight = normalizedQiblah <= 180;
    final degrees =
        (turnRight ? normalizedQiblah : 360 - normalizedQiblah).round();

    return SizedBox(
      // Fixed height: the instruction swaps text between states, and a
      // self-sizing box would shunt the compass up and down as it does.
      // Trimmed from 44 — that box reserved more room than the 24px text
      // actually needed, which read as dead air between the instruction
      // and the marker below it.
      height: 32,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            isPointingToQibla
                ? 'أنت متجه نحو القبلة'
                : turnRight
                ? 'أدر يمينًا $degrees°'
                : 'أدر يسارًا $degrees°',
            key: ValueKey(isPointingToQibla),
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: 'cairo',
              fontWeight: FontWeight.bold,
              fontSize: 24,
              height: 1.2,
              color:
                  isPointingToQibla ? AppColors.success : AppColors.heading,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCluster(
    QiblahDirection qiblahDirection,
    bool isPointingToQibla,
    double normalizedQiblah,
  ) {
    // Same shortest-turn value already driving the marker's own rotation,
    // read directly for the highlighted arc so the two can never drift out
    // of sync with each other.
    double sweepDegrees = (_lastQiblaTurns * 360) % 360;
    if (sweepDegrees > 180) sweepDegrees -= 360;
    if (sweepDegrees < -180) sweepDegrees += 360;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FittedBox(
        // Scales the marker down together with the dial on narrow or short
        // screens. Anything that shrinks one and not the other would break
        // the marker's orbit radius, which depends on the canvases matching.
        fit: BoxFit.scaleDown,
        // Biased above centre rather than dead-centre: the optical centre of
        // a page sits a little high, and this keeps the gap under the dial
        // from collapsing into the footer.
        alignment: const Alignment(0, -0.28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInstruction(isPointingToQibla, normalizedQiblah),
            // Deliberate, not zero — touching (my previous pass) read as
            // clutter, and the original ~60px gap read as unrelated
            // widgets. This is the middle: close enough to group, distinct
            // enough not to overlap.
            const SizedBox(height: 18),
            SvgPicture.asset("assets/arrow.svg"),
            const SizedBox(height: 10),
            SizedBox(
              width: 360,
              // 366, not 360: ka3baInCompass.svg's canvas is 365 tall, and
              // constraining it below its intrinsic height would rescale it
              // out of alignment with the dial it orbits.
              height: 366,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Painted at the same fixed size assets/test.svg used to
                  // be, so the marker's orbit radius still matches the ring.
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
                  // One number only. The dial reports where the user is
                  // facing; the instruction above says what to do about it.
                  // Stacking the Qibla bearing and a Kaaba chip in here too
                  // just gave the eye three numbers to rank.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${qiblahDirection.direction.toStringAsFixed(0)}°",
                        style: TextStyle(
                          fontSize: 34,
                          fontFamily: 'cairo',
                          fontWeight: FontWeight.bold,
                          // Identity's success/aligned token
                          // (DESIGN_IDENTITY.md §1) — not Colors.green, which
                          // has no home in this palette. This text sits on the
                          // light dial, so its resting colour is the on-light
                          // token, not the dark surface colour.
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
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The recalibrate action and the reference values, unified into one bar
  /// instead of two elements floating independently. A single fill + a
  /// divider does the grouping, rather than giving each its own surface —
  /// still just one filled component on the whole screen, now assembled as
  /// one piece instead of two. The fabricated "compass accuracy" card stays
  /// gone: nothing in flutter_qiblah's `QiblahDirection` reports sensor
  /// accuracy to back it up.
  Widget _buildFooter({required double displayQibla}) {
    final bearing = (((displayQibla % 360) + 360) % 360).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: AppColors.barFill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _recalibrate,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            // Two zones, evenly split: the button centres within its own
            // half, the info column stays end-aligned within its half. A
            // full-bar-relative centre (a version I tried in between) put
            // the button off to one side, since the info group is narrower
            // than the button's own zone — this way each element centres in
            // the space that's actually its own.
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.refresh,
                        size: 18,
                        color: AppColors.body,
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'إعادة ضبط القبلة',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.body,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 30,
                  child: VerticalDivider(
                    color: AppColors.cardBorder,
                    width: 24,
                    thickness: 1,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'القبلة $bearing°',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                      // Dropped entirely rather than shown as a placeholder
                      // dash — an empty slot advertises missing data the
                      // user never asked for.
                      if (_distanceToMeccaKm != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_formatKm(_distanceToMeccaKm!)} كم إلى مكة',
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 12,
                            color: AppColors.faint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatKm(double km) {
    final digits = km.round().toString();
    // Western digits with a thousands separator, matching how every other
    // number in the app renders regardless of device locale.
    return digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
  }

  Future<void> _recalibrate() async {
    setState(() {
      _loading = true;
    });
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      AppToast.success(context, 'تم إعادة ضبط القبلة بنجاح');
    }
    _checkPermission();
  }
}

/// The screen's one button family. It's the only element here that carries a
/// fill, which is what lets it read as "you can press this" without a border,
/// glow or blur doing the work — and its 12px radius keeps it distinct from
/// the pill shapes the app reserves for status and selection.
class _FilledAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilledAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.barFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.body),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
