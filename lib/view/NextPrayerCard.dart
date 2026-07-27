import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:myadhan/model/PrayerTimeModel.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
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

class _NextPrayerCardState extends ConsumerState<NextPrayerCard>
    with SingleTickerProviderStateMixin {
  static const _cardColor = Color(0xFF283F54);
  static const _accent = Color(0xFF4DB3E5);
  static const _muted = Color(0xFFD3E0EC);
  static const _content = Color(0xFFF0F8FF);

  static const _cardRadius = BorderRadius.only(
    topLeft: Radius.circular(36),
    topRight: Radius.circular(12),
    bottomLeft: Radius.circular(12),
    bottomRight: Radius.circular(36),
  );

  static const _prayerTimeKeys = {
    'الفجر': 'fajer',
    'الظهر': 'dhuhr',
    'العصر': 'asr',
    'المغرب': 'maghrib',
    'العشاء': 'isha',
  };

  String? _prayerName;
  bool _isAdhanPhase = true;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // A slow, low-amplitude breathing pulse on the accent glow — a calm
    // "alive" presence rather than a mechanical tick.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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
    // Same reasoning as adhan_screen.dart: read the device locale directly
    // rather than through the (unconfigured) Localizations tree.
    final locale = WidgetsBinding.instance.platformDispatcher.locale.toString();

    String? timeLabel;
    prayerTimesAsync.whenData((data) {
      final name = _prayerName;
      if (name == null) return;
      final time = _timeOf(name, data);
      if (time != null) {
        timeLabel = intl.DateFormat.jm(locale).format(time);
      }
    });

    final showError = prayerTimesAsync.hasError && _prayerName == null;
    final showLoading = prayerTimesAsync.isLoading && _prayerName == null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final glow = 0.12 + (_pulseController.value * 0.14);
          return Container(
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: _cardRadius,
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: glow),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: _cardRadius,
          child: Stack(
            children: [
              // Thin accent edge on the RTL leading (right) side — a
              // spatial "this is the active one" cue, not just text color.
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Container(width: 4, color: _accent),
              ),
              Padding(
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
            ],
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
