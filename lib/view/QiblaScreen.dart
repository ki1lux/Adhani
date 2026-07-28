import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:myadhan/controller/QiblahController.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';

import 'dart:async';

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

  double _getShortestTurns(double oldTurns, double newTurns) {
    double difference = newTurns - oldTurns;
    while (difference < -0.5) difference += 1.0;
    while (difference > 0.5) difference -= 1.0;
    return oldTurns + difference;
  }

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _checkPermission();
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
          child: Stack(
          children: [
            Center(
              child: Builder(
                builder: (context) {
                  if (_qiblahDirection == null) {
                    return Center(child: CircularProgressIndicator());
                  }

                  final qiblahDirection = _qiblahDirection!;
                  final double screenWidth = MediaQuery.of(context).size.width;

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
                  final double currentDir =
                      qiblahDirection.direction.toDouble();
                  final int now = DateTime.now().millisecondsSinceEpoch;

                  // Haptic feedback every 1 degree slightly
                  if ((currentDir - _lastDirection).abs() > 1 &&
                      now - _lastHapticTime > 200) {
                    HapticFeedback.lightImpact();
                    _lastDirection = currentDir;
                    _lastHapticTime = now;
                  }

                  return SizedBox(
                    height: screenWidth + 75,
                    width: screenWidth -32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedRotation(
                          turns: _lastCompassTurns,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          child: SvgPicture.asset("assets/test.svg"),
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
                                " ${qiblahDirection.direction.toStringAsFixed(0)}°",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontFamily: 'cairo',
                                  fontWeight: FontWeight.bold,
                                  // Identity's success/aligned token
                                  // (DESIGN_IDENTITY.md §1) — not
                                  // Colors.green, which has no home in
                                  // this palette.
                                  // This text sits on the light dial, so
                                  // its resting color is the on-light
                                  // token, not the dark surface color.
                                  color:
                                      isPointingToQibla
                                          ? AppColors.success
                                          : AppColors.onLight,
                                ),
                              ),
                              if (isPointingToQibla)
                                const Text(
                                  "في اتجاه القبلة",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'cairo',
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Reset Qibla button
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
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
                          // Matches PrayerTimeScreen's snackbar treatment —
                          // same component, same role, same look.
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
                  // icon: const Icon(Icons.compass_calibration, size: 20),
                  label: const Text(
                    'إعادة ضبط القبلة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.body.withValues(alpha: 0.05),
                    foregroundColor: AppColors.body,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
