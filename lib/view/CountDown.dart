import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/theme/app_colors.dart';

class CountdownTimer extends ConsumerStatefulWidget {
  final VoidCallback onFinish;

  /// Overrides the default 16px bold style. Falls back to the existing
  /// style when omitted, so the PrayerTimeScreen call site is unaffected.
  final TextStyle? style;

  /// Fired whenever the next-prayer name or Adhan/Iqamah phase changes, so a
  /// parent can display the prayer name in sync with this ticking countdown
  /// without recomputing "which prayer is next" itself.
  final void Function(String prayerName, bool isAdhanPhase)? onPrayerInfo;

  const CountdownTimer({
    required this.onFinish,
    this.style,
    this.onPrayerInfo,
    super.key,
  });

  @override
  ConsumerState<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends ConsumerState<CountdownTimer> {
  static const _defaultIqamaDelay = Duration(minutes: 30);
  static const _maghribIqamaDelay = Duration(minutes: 15);
  static const _textStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
  );
  // The app's own red (DESIGN_IDENTITY.md §1e) — its role was deliberately
  // widened to cover countdown/urgency displays like this one, alongside
  // the Qibla direction marker, rather than reaching for Material's
  // generic Colors.red.
  static const _iqamaColor = AppColors.danger;

  Timer? _timer;
  Duration _remaining = Duration.zero;
  Duration _iqamaRemaining = Duration.zero;
  bool _isAdhanPhase = true;
  String? _lastPlayedPrayer;
  DateTime? _targetTime;
  DateTime? _iqamaStartTime;
  String? _nextPrayerName;

  TextStyle get _effectiveStyle => widget.style ?? _textStyle;

  void _notifyPrayerInfo() {
    final name = _nextPrayerName;
    if (name != null) {
      widget.onPrayerInfo?.call(name, _isAdhanPhase);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown(PrayerTimeModel data) {
    _timer?.cancel();

    final prayers = [
      (name: 'الفجر', time: data.fajer),
      (name: 'الظهر', time: data.dhuhr),
      (name: 'العصر', time: data.asr),
      (name: 'المغرب', time: data.maghrib),
      (name: 'العشاء', time: data.isha),
    ];

    final now = DateTime.now();
    final nextIndex = _findNextPrayerIndex(prayers, now);

    // First, let's check if we are currently IN an Iqamah phase
    final previousIndex = (nextIndex - 1 + prayers.length) % prayers.length;
    final previous = prayers[previousIndex];
    // We need to know previous prayer's actual time for *today*
    // (or yesterday if Fajr next and Isha was yesterday)
    DateTime previousTimeCandidate = DateTime(
      now.year,
      now.month,
      now.day,
      previous.time.hour,
      previous.time.minute,
    );
    if (previousTimeCandidate.isAfter(now)) {
      previousTimeCandidate = previousTimeCandidate.subtract(
        const Duration(days: 1),
      );
    }

    final delayForPrevious = _getIqamaDelay(previous.name);
    final elapsedSincePrevious = now.difference(previousTimeCandidate);

    if (elapsedSincePrevious >= Duration.zero &&
        elapsedSincePrevious < delayForPrevious) {
      // WE ARE IN THE IQAMAH PHASE!
      // Keep the name as the prayer currently in its Iqamah window (matches
      // the live-transition path below) — not the one after it. Nothing
      // used to read this name externally so this drift was invisible
      // before; it isn't a deliberate "show the next one during Iqamah" rule.
      _isAdhanPhase = false;
      _lastPlayedPrayer = previous.name;
      _nextPrayerName = previous.name;
      _iqamaStartTime = previousTimeCandidate;
      _iqamaRemaining = elapsedSincePrevious;
      // Keep target time as the previous one just so _remaining isn't null,
      // though _remaining isn't shown during Iqamah phase.
      _targetTime = previousTimeCandidate;
    } else {
      // WE ARE IN NORMAL ADHAN COUNTDOWN PHASE
      final next = prayers[nextIndex];
      _nextPrayerName = next.name;
      _targetTime = _getNextPrayerTime(next.time, now);
      _isAdhanPhase = true;
      _iqamaStartTime = null;
      _iqamaRemaining = Duration.zero;
    }

    _notifyPrayerInfo();
    _updateRemaining();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _updateRemaining();
        _handlePhaseTransition();
      });
    });
  }

  void _updateRemaining() {
    if (_targetTime != null) {
      _remaining = _targetTime!.difference(DateTime.now());
    }
  }

  Duration _getIqamaDelay(String? prayerName) {
    return prayerName == 'المغرب' ? _maghribIqamaDelay : _defaultIqamaDelay;
  }

  void _handlePhaseTransition() {
    if (_isAdhanPhase &&
        _remaining.inSeconds <= 0 &&
        _lastPlayedPrayer != _nextPrayerName) {
      final delay = _getIqamaDelay(_nextPrayerName);

      // If we completely skipped the Iqamah phase (e.g. user manually stepped time forward)
      if (-_remaining.inSeconds >= delay.inSeconds) {
        _timer?.cancel();
        widget.onFinish();
        ref.read(prayerTimesProvider).whenData(_startCountdown);
        return;
      }

      _isAdhanPhase = false;
      _lastPlayedPrayer = _nextPrayerName;
      _iqamaStartTime = _targetTime ?? DateTime.now();
      _iqamaRemaining = Duration.zero;
      _notifyPrayerInfo();
    } else if (!_isAdhanPhase && _iqamaStartTime != null) {
      final delay = _getIqamaDelay(_lastPlayedPrayer);
      final elapsed = DateTime.now().difference(_iqamaStartTime!);
      _iqamaRemaining = elapsed;
      if (elapsed >= delay) {
        _timer?.cancel();
        widget.onFinish();
        ref.read(prayerTimesProvider).whenData(_startCountdown);
      }
    }
  }

  int _findNextPrayerIndex(
    List<({String name, DateTime time})> prayers,
    DateTime now,
  ) {
    for (int i = 0; i < prayers.length; i++) {
      if (prayers[i].time.isAfter(now)) return i;
    }
    return 0;
  }

  DateTime _getNextPrayerTime(DateTime prayerTime, DateTime now) {
    final candidate = DateTime(
      now.year,
      now.month,
      now.day,
      prayerTime.hour,
      prayerTime.minute,
    );
    return candidate.isBefore(now)
        ? candidate.add(const Duration(days: 1))
        : candidate;
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(prayerTimesProvider)
        .when(
          loading:
              () => Text(
                '00:00:00',
                textDirection: TextDirection.ltr,
                style: _effectiveStyle.copyWith(color: AppColors.body),
              ),
          error:
              (_, __) => Text(
                '--:--:--',
                textDirection: TextDirection.ltr,
                style: _effectiveStyle.copyWith(color: _iqamaColor),
              ),
          data: (data) {
            if (_targetTime == null) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _startCountdown(data),
              );
            }
            return Text(
              _formatDuration(_isAdhanPhase ? _remaining : _iqamaRemaining),
              // Always render digits left-to-right, regardless of any
              // ambient RTL Directionality a parent may set — this is
              // plain numeric content, not Arabic text.
              textDirection: TextDirection.ltr,
              style: _effectiveStyle.copyWith(
                color: _isAdhanPhase ? AppColors.body : _iqamaColor,
              ),
            );
          },
        );
  }
}
