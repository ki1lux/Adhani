import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/services/app_config.dart';
import 'package:myadhan/services/app_logger.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';
import 'package:myadhan/view/AppToast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _channel = MethodChannel('com.myadhan/notification');

  /// Mirrors `PrayerCountdownService.KEY_COUNTDOWN_ENABLED` on the native
  /// side — written here without the `flutter.` prefix, which the plugin adds
  /// on disk (see CLAUDE.md's shared-storage contract).
  static const _countdownEnabledKey = 'countdown_notification_enabled';

  /// Whether the persistent countdown notification is on.
  ///
  /// This replaces an "إشعار ملء الشاشة" switch that was wired to nothing but
  /// its own `setState` — it wasn't persisted, nothing read it, and the app
  /// has never used a full-screen intent. This one controls a real thing the
  /// user can see and has a reason to want off: an ongoing notification backed
  /// by a foreground service.
  bool _countdownEnabled = true;

  /// Per-prayer alarm state, read from the same prefs the native scheduler
  /// arms alarms from. Previously always empty, so "حالة التنبيهات" opened on
  /// a permanent "no data available".
  Map<String, _AlarmStatus> _alarmStatus = {};
  bool _exactAlarmsAllowed = true;

  // Shared with the rest of the app: rows and dialogs use the same
  // translucent fill + hairline border as PrayerTimeScreen's cards and
  // QiblaScreen's bar, instead of this screen's old opaque sheetTop tiles.
  static final _rowRadius = BorderRadius.circular(16);
  static final _dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
  );

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _countdownEnabled = prefs.getBool(_countdownEnabledKey) ?? true;
    });
  }

  /// Turns the ongoing countdown notification on or off, and starts/stops the
  /// foreground service behind it.
  Future<void> _setCountdownEnabled(bool enabled) async {
    setState(() => _countdownEnabled = enabled);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_countdownEnabledKey, enabled);

    try {
      await _channel.invokeMethod(
        enabled ? 'startCountdownService' : 'stopCountdownService',
      );
    } catch (e) {
      logWarning('Could not toggle countdown service', e);
    }

    if (!mounted) return;
    AppToast.success(
      context,
      enabled ? 'تم تفعيل إشعار العدّاد' : 'تم إيقاف إشعار العدّاد',
      detail:
          enabled
              ? 'سيظهر الوقت المتبقي للصلاة القادمة في شريط الإشعارات'
              : 'لن يظهر الإشعار الدائم بعد الآن',
    );
  }

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
                        _assetIcon('assets/timerIcon.png'),
                        'إشعار العدّاد الدائم',
                        _countdownEnabled,
                        _setCountdownEnabled,
                        subtitle: 'يعرض الوقت المتبقي للصلاة القادمة',
                      ),
                      _buildRow(
                        _assetIcon('assets/popupIcon.png'),
                        'حالة التنبيهات',
                        _showAlarmStatusDialog,
                      ),
                      _buildRow(
                        // No matching custom icon provided for this row.
                        _matIcon(Icons.build_outlined),
                        'إصلاح مشاكل التنبيه',
                        _showTroubleshootDialog,
                      ),
                      _buildRow(
                        _assetIcon('assets/batteryWarningIcon.png'),
                        'تعطيل تحسين البطارية',
                        _openBatteryOptimizationSettings,
                      ),
                      _buildRow(
                        _assetIcon('assets/widgetsIcon.png'),
                        'تحديث الودجت الآن',
                        _refreshWidget,
                      ),

                      const SizedBox(height: 24),
                      _sectionLabel('مواقيت الصلاة'),
                      _buildRow(
                        _assetIcon('assets/calculatorIcon.png'),
                        'طريقة الحساب',
                        _showCalculationMethodDialog,
                      ),

                      const SizedBox(height: 24),
                      _sectionLabel('التطبيق'),
                      _buildRow(
                        _assetIcon('assets/shareIcon.png'),
                        'مشاركة التطبيق',
                        _shareApp,
                      ),
                      _buildRow(
                        _assetIcon('assets/starIcon.png'),
                        'تقييم التطبيق',
                        _rateApp,
                      ),
                      _buildRow(
                        _assetIcon('assets/privacyIcon.png'),
                        'سياسة الخصوصية',
                        _openPrivacyPolicy,
                      ),
                      _buildRow(
                        _assetIcon('assets/directoryIcon.png'),
                        'مصادر البيانات',
                        _showDataSourcesDialog,
                      ),

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

  /// A row's leading Material icon, sized/tinted to match [_assetIcon] below
  /// — so a row can be switched between the two without its glyph's size or
  /// color shifting.
  Widget _matIcon(IconData icon) =>
      Icon(icon, color: AppColors.secondary, size: 22);

  /// A row's leading custom icon (DESIGN_IDENTITY.md: solid white PNG
  /// silhouettes — see pubspec.yaml for why these ship as .png, not .svg).
  /// Tinted the same way `Icon()` is, via Image.asset's own color +
  /// colorBlendMode rather than a ColorFilter/SvgPicture.
  Widget _assetIcon(String assetPath, {double size = 22}) => Image.asset(
    assetPath,
    width: size,
    height: size,
    color: AppColors.secondary,
    colorBlendMode: BlendMode.srcIn,
  );

  Widget _buildRow(Widget icon, String title, VoidCallback onTap) {
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
                icon,
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
                // chevronIcon.png points right (like its source name says);
                // Icons.chevron_left pointed left because this Row sits
                // inside a `Directionality(rtl)` ancestor, where the last
                // child in a Row renders at the visual *left* edge — so a
                // left-pointing glyph there reads as "continue reading
                // forward" in RTL. Swapping the raster in without
                // accounting for that would have flipped every disclosure
                // arrow in Settings to point the wrong way. `Transform.flip`
                // mirrors it losslessly since it's a flat solid silhouette,
                // rather than needing a second, mirrored asset.
                Transform.flip(
                  flipX: true,
                  child: Image.asset(
                    'assets/chevronIcon.png',
                    width: 20,
                    height: 20,
                    color: AppColors.faint,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    Widget icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // One node for the whole row, so a screen reader announces
      // "إشعار العدّاد الدائم, switch, on" instead of reading the label and
      // the control as two unrelated things.
      child: MergeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardFill,
            borderRadius: _rowRadius,
            border: Border.all(color: AppColors.cardBorder),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 15,
                        fontFamily: 'cairo',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.label,
                          fontSize: 11.5,
                          fontFamily: 'cairo',
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
      ),
    );
  }

  // ── App section actions ───────────────────────────────────────────────
  // These three rows were `() {}` — visible, tappable, and doing nothing.
  // A reviewer taps every row on the settings screen.

  /// Opens the system share sheet via a one-off ACTION_SEND on the existing
  /// MethodChannel, rather than pulling in a plugin for a single intent.
  Future<void> _shareApp() async {
    const text =
        '${AppConfig.appName} — تطبيق مواقيت الصلاة والأذان واتجاه القبلة\n'
        '${AppConfig.playStoreUrl}';
    try {
      final shared = await _channel.invokeMethod<bool>('shareApp', {
        'text': text,
      });
      if (shared == true || !mounted) return;
    } catch (e) {
      logWarning('Share sheet unavailable', e);
      if (!mounted) return;
    }
    // No app can handle a share intent — fall back to the clipboard rather
    // than leaving the tap with no visible result.
    await Clipboard.setData(const ClipboardData(text: text));
    if (!mounted) return;
    AppToast.success(context, 'تم نسخ رابط التطبيق');
  }

  /// Opens the Play listing — the installed Play app when it's there, the web
  /// listing when it isn't.
  Future<void> _rateApp() async {
    final market = Uri.parse(AppConfig.playStoreMarketUri);
    try {
      if (await canLaunchUrl(market)) {
        await launchUrl(market, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      logWarning('Play app not available', e);
    }

    final opened = await _openExternal(AppConfig.playStoreUrl);
    if (!opened && mounted) {
      AppToast.error(
        context,
        'تعذّر فتح متجر Play',
        detail: 'يمكنك تقييم التطبيق من صفحته في المتجر',
      );
    }
  }

  /// Play requires the privacy policy to be reachable from inside an app that
  /// requests location, not only from the store listing.
  Future<void> _openPrivacyPolicy() async {
    final opened = await _openExternal(AppConfig.privacyPolicyUrl);
    if (!opened && mounted) {
      AppToast.error(context, 'تعذّر فتح سياسة الخصوصية');
    }
  }

  Future<bool> _openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      logWarning('Could not open external URL', e);
      return false;
    }
  }

  /// Attribution for the two services the app sends coordinates to. Both sets
  /// of terms ask for it, and naming them in-app matches what the Play Data
  /// Safety form has to declare.
  void _showDataSourcesDialog() {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.sheetBottom,
            surfaceTintColor: Colors.transparent,
            shape: _dialogShape,
            title: const Text(
              'مصادر البيانات',
              style: TextStyle(
                color: AppColors.heading,
                fontFamily: 'cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مواقيت الصلاة والتاريخ الهجري: Aladhan API\n'
                    'أسماء المدن: OpenStreetMap Nominatim\n\n'
                    'يُرسَل موقعك الجغرافي إلى هاتين الخدمتين لحساب المواقيت '
                    'ومعرفة اسم مدينتك فقط. لا يجمع التطبيق أي بيانات أخرى ولا '
                    'يحتفظ بها على أي خادم.',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontFamily: 'cairo',
                      fontSize: 13.5,
                      height: 1.8,
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
        Semantics(
          label: 'صفحة المطوّر على GitHub',
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _openExternal(AppConfig.developerUrl),
              child: Padding(
                // 24px icon + 12px on each side = 48x48, the minimum
                // accessible tap target.
                padding: const EdgeInsets.all(12),
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
        ),
        const SizedBox(height: 6),
        const SelectableText(
          AppConfig.supportEmail,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: AppColors.faint,
            fontSize: 12,
            fontFamily: 'cairo',
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          // Was hardcoded 'Adhani · 1.0' — one more place for the shipped
          // version to disagree with pubspec.yaml.
          'Adhani · v${AppConfig.version}',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            // `inactive` is 2.9:1 against the navy surface — below the 4.5:1
            // WCAG AA minimum, and this is 11px text.
            color: AppColors.label,
            fontSize: 11,
            fontFamily: 'cairo',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          AppConfig.dataAttribution,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: AppColors.label,
            fontSize: 10.5,
            fontFamily: 'cairo',
          ),
        ),
      ],
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
      if (mounted) {
        AppToast.success(
          context,
          'تم تحديث الودجت',
          detail: 'أعيد حساب مواقيت اليوم على الشاشة الرئيسية',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(
          context,
          'تعذر تحديث الودجت',
          detail: 'تأكد من أذونات التنبيه ثم حاول مجددًا',
        );
      }
    }
  }

  /// Reads the same `prayer_{id}_*` prefs the native scheduler arms alarms
  /// from, so this dialog reports what is actually scheduled rather than what
  /// the UI hopes is scheduled.
  Future<void> _loadAlarmStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final exact = await PrayerAlarmScheduler.checkExactAlarmPermission();
    final now = DateTime.now();
    final result = <String, _AlarmStatus>{};

    for (var id = 1; id <= 5; id++) {
      final name = prefs.getString('prayer_${id}_name');
      final time = prefs.getString('prayer_${id}_time');
      if (name == null || time == null) continue;

      final trigger = prefs.getInt('prayer_${id}_trigger_millis');
      final enabled = prefs.getBool('adhan_enabled_$name') ?? true;

      DateTime? next;
      if (trigger != null && trigger > 0) {
        next = DateTime.fromMillisecondsSinceEpoch(trigger);
      }

      result[name] = _AlarmStatus(
        time: time,
        enabled: enabled,
        isTomorrow: next != null && next.day != now.day,
        scheduled: next != null && next.isAfter(now),
      );
    }

    if (!mounted) return;
    setState(() {
      _alarmStatus = result;
      _exactAlarmsAllowed = exact;
    });
  }

  Future<void> _showAlarmStatusDialog() async {
    // Loaded on open rather than never: `alarmStatus` was declared, rendered
    // and left empty, so this dialog always said "no data available".
    await _loadAlarmStatus();
    if (!mounted) return;

    final entries = _alarmStatus.entries.toList();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.sheetBottom,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_exactAlarmsAllowed) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.cardFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Text(
                      'إذن «التنبيهات الدقيقة» غير مفعّل — قد يتأخر الأذان '
                      'بضع دقائق. فعّله من «إصلاح مشاكل التنبيه».',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontFamily: 'cairo',
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (entries.isEmpty)
                  const Text(
                    'لم تُجدول أي تنبيهات بعد. افتح شاشة المواقيت لتحميل '
                    'مواقيت اليوم.',
                    style: TextStyle(
                      color: AppColors.secondary,
                      fontFamily: 'cairo',
                      fontSize: 14,
                      height: 1.7,
                    ),
                  )
                else
                  ...entries.map((entry) {
                    final name = entry.key;
                    final status = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              color:
                                  status.enabled
                                      ? AppColors.body
                                      : AppColors.faint,
                              fontFamily: 'cairo',
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            status.label,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: status.color,
                              fontFamily: 'cairo',
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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
    // The builder's parameter used to be called `context`, shadowing the
    // State's. Every `AppToast(context, ...)` inside therefore posted to the
    // *dialog's* Navigator — which is torn down the moment the dialog closes,
    // so a toast fired after an await landed on a defunct element. Naming it
    // `dialogContext` makes the two impossible to confuse.
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.sheetBottom,
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
                      // `this.context` — the screen's, which outlives the
                      // dialog and is guarded by the `mounted` check above.
                      AppToast.success(context, 'الإذن مفعل بالفعل');
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildTroubleshootItem(
                  "2. تحسين البطارية (Battery Optimization)",
                  "بعض الهواتف توقف التطبيق في الخلفية. يرجى استثناء التطبيق من تحسين البطارية.",
                  _openBatterySettings,
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
              onPressed: () => Navigator.of(dialogContext).pop(),
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

  /// Hands off to the native handler, which opens the battery-optimisation
  /// list and falls back to the app's own settings page when a device doesn't
  /// have that screen.
  ///
  /// The Dart fallback this replaces tried to launch
  /// `package:com.example.myadhan` through `url_launcher` — not a launchable
  /// URI scheme, and naming the pre-rename package. It could never have
  /// worked, so a device without the battery screen got a dialog that closed
  /// and did nothing.
  Future<void> _openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (e) {
      logWarning('Could not open battery settings', e);
      if (!mounted) return;
      AppToast.error(
        context,
        'تعذّر فتح الإعدادات',
        detail: 'افتح إعدادات النظام ← البطارية ← استثناء التطبيقات',
      );
    }
  }

  /// Opens Android battery optimization settings for this app
  /// This helps users disable battery restrictions that delay notifications
  void _openBatteryOptimizationSettings() async {
    // Show explanation dialog first
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.sheetBottom,
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
                Image.asset(
                  'assets/batteryWarningIcon.png',
                  width: 44,
                  height: 44,
                  color: AppColors.accent,
                  colorBlendMode: BlendMode.srcIn,
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
                  style: TextStyle(color: AppColors.label, fontFamily: 'cairo'),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openBatterySettings();
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

  /// Persists the chosen method, waits for the times it produces, and only
  /// then re-arms the alarms.
  ///
  /// The old flow fired `fetchPrayerTimes()` without awaiting it and read the
  /// provider on the very next line — so it re-armed five alarms from the
  /// *previous* method's times while the new ones were still in flight, and
  /// the alarms only became correct on some later refresh. It also announced
  /// success before anything had actually been recalculated.
  Future<void> _applyCalculationMethod(
    SharedPreferences prefs,
    int method,
  ) async {
    await prefs.setInt('calculation_method', method);

    final notifier = ref.read(prayerTimesProvider.notifier);
    await notifier.fetchPrayerTimes();

    final data = ref.read(prayerTimesProvider).value;
    if (data != null) {
      await PrayerAlarmScheduler.scheduleAllPrayersWithData(data);
    }

    if (!mounted) return;
    final methodName =
        _calculationMethods.firstWhere(
              (m) => m['id'] == method,
              orElse: () => _calculationMethods.first,
            )['name']
            as String;

    if (data == null) {
      AppToast.error(
        context,
        'تم حفظ طريقة الحساب',
        detail: 'تعذّر تحديث المواقيت الآن — سيُعاد المحاولة تلقائيًا',
      );
      return;
    }

    AppToast.success(
      context,
      'تم تغيير طريقة الحساب',
      detail: 'حُسبت المواقيت حسب «$methodName»',
    );
  }

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
                  backgroundColor: AppColors.sheetBottom,
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
                        final selected = currentMethod;
                        Navigator.pop(context);
                        await _applyCalculationMethod(prefs, selected);
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

/// One prayer's scheduling state, as read back from the prefs the native
/// alarm scheduler actually uses.
class _AlarmStatus {
  final String time;
  final bool enabled;
  final bool isTomorrow;
  final bool scheduled;

  const _AlarmStatus({
    required this.time,
    required this.enabled,
    required this.isTomorrow,
    required this.scheduled,
  });

  String get label {
    if (!enabled) return 'الأذان متوقف';
    if (!scheduled) return 'غير مجدول';
    return isTomorrow ? 'غدًا $time' : 'اليوم $time';
  }

  Color get color {
    if (!enabled) return AppColors.faint;
    if (!scheduled) return AppColors.danger;
    return isTomorrow ? AppColors.warning : AppColors.success;
  }
}
