import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool isFullScreen = true;
  Map<String, dynamic> alarmStatus = {};

  // Shared with the rest of the app: rows and dialogs use the same
  // translucent fill + hairline border as PrayerTimeScreen's cards and
  // QiblaScreen's bar, instead of this screen's old opaque sheetTop tiles.
  static final _rowRadius = BorderRadius.circular(16);
  static final _dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light, // White icons on Android
        statusBarBrightness: Brightness.dark, // White icons on iOS
      ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // The shared navy glow + Islamic pattern every other screen uses —
        // this one was still painting a flat fill.
        body: AppBackground(
          child: SafeArea(
            child: Directionality(
              // Arabic-first, like the rest of the app: icons lead on the
              // right, text reads right-to-left.
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),

                      _sectionLabel('التنبيهات'),
                      _buildSwitchRow(
                        Icons.notifications_outlined,
                        'إشعار ملء الشاشة',
                        isFullScreen,
                        (val) => setState(() => isFullScreen = val),
                      ),
                      _buildRow(
                        Icons.info_outline,
                        'حالة التنبيهات',
                        _showAlarmStatusDialog,
                      ),
                      _buildRow(
                        Icons.build_outlined,
                        'إصلاح مشاكل التنبيه',
                        _showTroubleshootDialog,
                      ),
                      _buildRow(
                        Icons.battery_alert_outlined,
                        'تعطيل تحسين البطارية',
                        _openBatteryOptimizationSettings,
                      ),
                      _buildRow(
                        Icons.widgets_outlined,
                        'تحديث الودجت الآن',
                        _refreshWidget,
                      ),

                      const SizedBox(height: 24),
                      _sectionLabel('مواقيت الصلاة'),
                      _buildRow(
                        Icons.calculate_outlined,
                        'طريقة الحساب',
                        _showCalculationMethodDialog,
                      ),

                      const SizedBox(height: 24),
                      _sectionLabel('التطبيق'),
                      _buildRow(Icons.share_outlined, 'مشاركة التطبيق', () {}),
                      _buildRow(Icons.star_outline, 'تقييم التطبيق', () {}),

                      const SizedBox(height: 36),
                      _buildCredits(),
                      // Clears the floating bottom nav bar (MainScreen's
                      // Scaffold uses extendBody: true) — without this the
                      // last rows sat underneath it.
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Align(
      alignment: Alignment.centerRight,
      child: Text(
        'الإعدادات',
        style: TextStyle(
          fontFamily: 'cairo',
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: AppColors.body,
        ),
      ),
    );
  }

  /// Groups the list into readable sections instead of one undifferentiated
  /// stack of nine identical tiles.
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'cairo',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.faint,
        ),
      ),
    );
  }

  Widget _buildRow(IconData icon, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardFill,
        borderRadius: _rowRadius,
        child: InkWell(
          borderRadius: _rowRadius,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: _rowRadius,
              border: Border.all(color: AppColors.cardBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.secondary, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.body,
                      fontSize: 15,
                      fontFamily: 'cairo',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_left,
                  color: AppColors.faint,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardFill,
          borderRadius: _rowRadius,
          border: Border.all(color: AppColors.cardBorder),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.secondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.body,
                  fontSize: 15,
                  fontFamily: 'cairo',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              // Accent is reserved for genuine active/selected indicators —
              // this is one.
              activeThumbColor: AppColors.accent,
              activeTrackColor: AppColors.accentFill,
              inactiveThumbColor: AppColors.faint,
              inactiveTrackColor: AppColors.cardBorder,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredits() {
    return Column(
      children: [
        Divider(color: AppColors.cardBorder, height: 1),
        const SizedBox(height: 20),
        const Text(
          'تصميم وتطوير',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            fontFamily: 'cairo',
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () async {
              final url = Uri.parse("https://github.com/ki1lux");
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              // Material Icons has no GitHub mark, so this is a local SVG
              // tinted through the palette like the app's other custom icons.
              child: SvgPicture.asset(
                'assets/github.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(
                  AppColors.secondary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "khalilbenfiala001@gmail.com",
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: AppColors.faint,
            fontSize: 12,
            fontFamily: 'cairo',
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Adhani · 1.0',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: AppColors.inactive,
            fontSize: 11,
            fontFamily: 'cairo',
          ),
        ),
      ],
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'cairo', color: AppColors.body),
          textAlign: TextAlign.center,
        ),
        // Same floating treatment PrayerTimeScreen and QiblaScreen use.
        backgroundColor: AppColors.sheetTop,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Manual recourse for a stale home-screen widget. Calls the same
  /// `rescheduleFromPrefs` native method every writer of prayer data already
  /// ends with (see CLAUDE.md's "three independent writers" section) —
  /// `AlarmSchedulerHelper.rescheduleAllFromPrefs` re-arms the widget-refresh
  /// alarms *and* immediately broadcasts `ACTION_PRAYER_UPDATED`, which
  /// `PrayerWidgetProvider` reacts to right away. Not a new mechanism, just
  /// user-triggered access to the one that already exists.
  Future<void> _refreshWidget() async {
    const channel = MethodChannel('com.myadhan/notification');
    try {
      await channel.invokeMethod('rescheduleFromPrefs');
      if (mounted) _showSnack('تم تحديث الودجت ✅');
    } catch (e) {
      if (mounted) _showSnack('تعذر تحديث الودجت');
    }
  }

  void _showAlarmStatusDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sheetTop,
          // Material 3 tints dialog surfaces by default, which made this
          // screen's dialogs a different shade from the rest of the app's.
          surfaceTintColor: Colors.transparent,
          shape: _dialogShape,
          title: const Text(
            'حالة تنبيهات الصلاة',
            style: TextStyle(
              color: AppColors.heading,
              fontFamily: 'cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  alarmStatus.isEmpty
                      ? [
                        const Text(
                          'لا تتوفر بيانات عن التنبيهات حاليًا.',
                          style: TextStyle(
                            color: AppColors.secondary,
                            fontFamily: 'cairo',
                            fontSize: 14,
                          ),
                        ),
                      ]
                      : alarmStatus.entries.map((entry) {
                        final prayerName = entry.key;
                        final data = entry.value as Map<String, dynamic>;
                        final isPassed = data['isPassed'] as bool;
                        final nextOccurrence = data['nextOccurrence'] as String;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                prayerName,
                                style: const TextStyle(
                                  color: AppColors.body,
                                  fontFamily: 'cairo',
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                isPassed
                                    ? 'غدًا $nextOccurrence'
                                    : 'اليوم ${data['time']}',
                                style: TextStyle(
                                  color:
                                      isPassed
                                          ? AppColors.warning
                                          : AppColors.success,
                                  fontFamily: 'cairo',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'إغلاق',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontFamily: 'cairo',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showTroubleshootDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sheetTop,
          surfaceTintColor: Colors.transparent,
          shape: _dialogShape,
          title: const Text(
            'استكشاف الأخطاء وإصلاحها',
            style: TextStyle(
              color: AppColors.heading,
              fontFamily: 'cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTroubleshootItem(
                  "1. إذن التنبيه الدقيق (Exact Alarm)",
                  "تأكد من تفعيل هذا الإذن لضمان عمل الأذان في وقته الدقيق.",
                  () async {
                    bool granted =
                        await PrayerAlarmScheduler.checkExactAlarmPermission();
                    if (!granted) {
                      await PrayerAlarmScheduler.requestExactAlarmPermission();
                    } else if (mounted) {
                      _showSnack('الإذن مفعل بالفعل ✅');
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTroubleshootItem(
                  "2. تحسين البطارية (Battery Optimization)",
                  "بعض الهواتف توقف التطبيق في الخلفية. يرجى استثناء التطبيق من تحسين البطارية.",
                  () async {
                    const channel = MethodChannel('com.myadhan/notification');
                    await channel.invokeMethod('openBatterySettings');
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  "نصيحة: إذا كان هاتفك من نوع Xiaomi أو Huawei، ابحث عن إعدادات 'التشغيل التلقائي' (Autostart) وقم بتفعيل التطبيق.",
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontFamily: 'cairo',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'إغلاق',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontFamily: 'cairo',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTroubleshootItem(String title, String desc, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.body,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              fontFamily: 'cairo',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              color: AppColors.secondary,
              fontSize: 13,
              fontFamily: 'cairo',
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              // Was Colors.blueAccent — off-palette. The identity's accent
              // carries the "actionable" role everywhere else.
              color: AppColors.accentFillSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentBorderSoft),
            ),
            child: const Text(
              "اضغط هنا للتحقق / الإصلاح",
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontFamily: 'cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens Android battery optimization settings for this app
  /// This helps users disable battery restrictions that delay notifications
  void _openBatteryOptimizationSettings() async {
    // Show explanation dialog first
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.sheetTop,
            surfaceTintColor: Colors.transparent,
            shape: _dialogShape,
            title: const Text(
              'تعطيل تحسين البطارية',
              style: TextStyle(
                color: AppColors.heading,
                fontFamily: 'cairo',
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.battery_alert_outlined,
                  color: AppColors.accent,
                  size: 44,
                ),
                const SizedBox(height: 16),
                const Text(
                  'لضمان وصول إشعارات الصلاة في وقتها بدقة:\n\n'
                  '1. اضغط "فتح الإعدادات"\n'
                  '2. ابحث عن التطبيق واختر "غير مُحسّن"\n'
                  '3. هذا يمنع Android من تأخير الإشعارات',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontFamily: 'cairo',
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(
                    color: AppColors.label,
                    fontFamily: 'cairo',
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  // Open battery optimization settings using native channel
                  try {
                    const channel = MethodChannel('com.myadhan/notification');
                    await channel.invokeMethod('openBatterySettings');
                  } catch (e) {
                    // Fallback: open general Android settings
                    final uri = Uri.parse('package:com.example.myadhan');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  // Near-white fill with dark text, matching the primary
                  // action in PrayerTimeScreen's dialogs — accent-on-accent
                  // buttons were part of this app's over-reliance on blue.
                  backgroundColor: AppColors.body,
                  foregroundColor: AppColors.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'فتح الإعدادات',
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// List of all Aladhan API calculation methods
  static const List<Map<String, dynamic>> _calculationMethods = [
    {'id': 19, 'name': 'الجزائر', 'nameEn': 'Algeria'},
    {'id': 4, 'name': 'أم القرى، مكة', 'nameEn': 'Umm Al-Qura, Makkah'},
    {'id': 5, 'name': 'الهيئة المصرية العامة للمساحة', 'nameEn': 'Egypt'},
    {'id': 3, 'name': 'رابطة العالم الإسلامي', 'nameEn': 'Muslim World League'},
    {'id': 2, 'name': 'أمريكا الشمالية (ISNA)', 'nameEn': 'ISNA'},
    {'id': 1, 'name': 'جامعة كراتشي', 'nameEn': 'Karachi'},
    {'id': 13, 'name': 'تركيا', 'nameEn': 'Turkey'},
    {'id': 7, 'name': 'طهران', 'nameEn': 'Tehran'},
    {'id': 0, 'name': 'الشيعة الإثنا عشرية، قم', 'nameEn': 'Jafari'},
    {'id': 8, 'name': 'منطقة الخليج', 'nameEn': 'Gulf Region'},
    {'id': 9, 'name': 'الكويت', 'nameEn': 'Kuwait'},
    {'id': 10, 'name': 'قطر', 'nameEn': 'Qatar'},
    {'id': 11, 'name': 'سنغافورة', 'nameEn': 'Singapore'},
    {'id': 12, 'name': 'فرنسا', 'nameEn': 'France'},
    {'id': 14, 'name': 'روسيا', 'nameEn': 'Russia'},
    {'id': 15, 'name': 'لجنة رؤية الهلال', 'nameEn': 'Moonsighting'},
    {'id': 16, 'name': 'دبي', 'nameEn': 'Dubai'},
    {'id': 17, 'name': 'ماليزيا (JAKIM)', 'nameEn': 'Malaysia'},
    {'id': 18, 'name': 'تونس', 'nameEn': 'Tunisia'},
    {'id': 20, 'name': 'إندونيسيا', 'nameEn': 'Indonesia'},
    {'id': 21, 'name': 'المغرب', 'nameEn': 'Morocco'},
    {'id': 22, 'name': 'البرتغال', 'nameEn': 'Portugal'},
    {'id': 23, 'name': 'الأردن', 'nameEn': 'Jordan'},
  ];

  void _showCalculationMethodDialog() async {
    final prefs = await SharedPreferences.getInstance();
    int currentMethod = prefs.getInt('calculation_method') ?? 19;
    if (!mounted) return;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  backgroundColor: AppColors.sheetTop,
                  surfaceTintColor: Colors.transparent,
                  shape: _dialogShape,
                  title: const Text(
                    'طريقة الحساب',
                    style: TextStyle(
                      color: AppColors.heading,
                      fontFamily: 'cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: ListView.builder(
                      itemCount: _calculationMethods.length,
                      itemBuilder: (context, index) {
                        final method = _calculationMethods[index];
                        final id = method['id'] as int;
                        final name = method['name'] as String;
                        final nameEn = method['nameEn'] as String;
                        final selected = id == currentMethod;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap:
                                () => setDialogState(() => currentMethod = id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    size: 20,
                                    // Accent marks the genuinely selected
                                    // item — the old hardcoded #0768C5 sat
                                    // outside the palette entirely.
                                    color:
                                        selected
                                            ? AppColors.accent
                                            : AppColors.faint,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            color:
                                                selected
                                                    ? AppColors.heading
                                                    : AppColors.body,
                                            fontFamily: 'cairo',
                                            fontSize: 15,
                                            fontWeight:
                                                selected
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          nameEn,
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(
                                            color: AppColors.faint,
                                            fontFamily: 'cairo',
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(
                          color: AppColors.label,
                          fontFamily: 'cairo',
                          fontSize: 15,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        await prefs.setInt('calculation_method', currentMethod);
                        if (context.mounted) Navigator.pop(context);

                        // Refresh prayer times with new method
                        ref
                            .read(prayerTimesProvider.notifier)
                            .fetchPrayerTimes();

                        // Reschedule alarms after prayer provider updates
                        final prayerTimesAsync = ref.read(prayerTimesProvider);
                        if (prayerTimesAsync.hasValue) {
                          await PrayerAlarmScheduler.scheduleAllPrayersWithData(
                            prayerTimesAsync.value!,
                          );
                        }

                        if (mounted) {
                          _showSnack('تم تغيير طريقة الحساب ✅');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.body,
                        foregroundColor: AppColors.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'حفظ',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }
}
