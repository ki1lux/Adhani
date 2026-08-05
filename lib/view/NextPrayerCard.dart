import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AccentCard.dart';
import 'package:myadhan/view/CountDown.dart';

/// The Home screen's focal point: which prayer is next, and how long until
/// it. Reuses [CountdownTimer]'s existing Adhan/Iqamah state machine
/// (via its `onPrayerInfo` callback) rather than recomputing "what's next"
/// independently, so the displayed name can never drift out of sync with
/// the ticking countdown.
class NextPrayerCard extends ConsumerStatefulWidget {
  const NextPrayerCard({super.key});

  @override
  ConsumerState<NextPrayerCard> createState() => _NextPrayerCardState();
}

class _NextPrayerCardState extends ConsumerState<NextPrayerCard> {
  static const _accent = AppColors.accent;
  static const _muted = AppColors.secondary;
  static const _content = AppColors.heading;

  static const _prayerTimeKeys = {
    'الفجر': 'fajer',
    'الظهر': 'dhuhr',
    'العصر': 'asr',
    'المغرب': 'maghrib',
    'العشاء': 'isha',
  };

  /// Same reasoning as adhan_screen's: built once rather than per rebuild.
  static final _timeFormat = intl.DateFormat.jm(
    WidgetsBinding.instance.platformDispatcher.locale.toString(),
  );

  String? _prayerName;
  bool _isAdhanPhase = true;

  void _handlePrayerInfo(String name, bool isAdhanPhase) {
    if (_prayerName == name && _isAdhanPhase == isAdhanPhase) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _prayerName = name;
        _isAdhanPhase = isAdhanPhase;
      });
    });
  }

  DateTime? _timeOf(String prayerName, PrayerTimeModel data) {
    switch (_prayerTimeKeys[prayerName]) {
      case 'fajer':
        return data.fajer;
      case 'dhuhr':
        return data.dhuhr;
      case 'asr':
        return data.asr;
      case 'maghrib':
        return data.maghrib;
      case 'isha':
        return data.isha;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prayerTimesAsync = ref.watch(prayerTimesProvider);

    String? timeLabel;
    prayerTimesAsync.whenData((data) {
      final name = _prayerName;
      if (name == null) return;
      final time = _timeOf(name, data);
      if (time != null) {
        timeLabel = _timeFormat.format(time);
      }
    });

    final showError = prayerTimesAsync.hasError && _prayerName == null;
    final showLoading = prayerTimesAsync.isLoading && _prayerName == null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AccentCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child:
                showError
                    ? _buildError(key: const ValueKey('error'))
                    : showLoading
                    ? _buildLoading(key: const ValueKey('loading'))
                    : _buildReady(
                      key: ValueKey('$_prayerName-$_isAdhanPhase'),
                      timeLabel: timeLabel,
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'الصلاة القادمة',
          style: TextStyle(fontFamily: 'cairo', fontSize: 14, color: _muted),
        ),
        SizedBox(height: 12),
        Text(
          'جاري التحميل...',
          style: TextStyle(
            fontFamily: 'cairo',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _content,
          ),
        ),
      ],
    );
  }

  Widget _buildError({required Key key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'تعذر تحميل مواقيت الصلاة',
          style: TextStyle(
            fontFamily: 'cairo',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _content,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => ref.read(prayerTimesProvider.notifier).refresh(),
          child: const Text(
            'إعادة المحاولة',
            style: TextStyle(
              fontFamily: 'cairo',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _accent,
              decoration: TextDecoration.underline,
              decorationColor: _accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReady({required Key key, String? timeLabel}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'الصلاة القادمة',
              style: TextStyle(
                fontFamily: 'cairo',
                fontSize: 14,
                color: _muted,
              ),
            ),
            if (timeLabel != null)
              Text(
                timeLabel,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 14,
                  color: _muted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _prayerName ?? '',
          style: const TextStyle(
            fontFamily: 'cairo',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: _accent,
          ),
        ),
        const SizedBox(height: 12),
        CountdownTimer(
          onFinish: () {},
          onPrayerInfo: _handlePrayerInfo,
          style: const TextStyle(
            fontFamily: 'cairo',
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
