import 'package:flutter/material.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:myadhan/prayer_alarm_scheduler.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}



class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool isFullScreen = true;
  Map<String, dynamic> alarmStatus = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,  // White icons on Android
        statusBarBrightness: Brightness.dark,        // White icons on iOS
      ),
      child: Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 6),

                Text(
                  "Settings",
                  style: TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                    alignment: Alignment.center,
                    height: 64,
                    decoration: _tileDecoration(),
                    child: SwitchListTile(
                      value: isFullScreen,
                      onChanged: (val) {
                        setState(() {
                          isFullScreen = val;
                        });
                      },
                      activeThumbColor: AppColors.body,
                      title: const Text(
                        "Full screen notif",
                        style: TextStyle(
                          color: AppColors.body,
                          fontSize: 16,
                          fontFamily: 'cairo',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      secondary: const Icon(
                        Icons.notifications,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                ),
                _settingsButtons(Icons.share, "Share App", () {}),
                _settingsButtons(Icons.star, "Rate App", () {}),
                _settingsButtons(Icons.info, "Alarm Status", () {
                  _showAlarmStatusDialog();
                }),
                _settingsButtons(Icons.build, "Troubleshoot Alarm", () {
                  _showTroubleshootDialog();
                }),
                _settingsButtons(Icons.battery_alert, "تعطيل تحسين البطارية", () {
                  _openBatteryOptimizationSettings();
                }),
                _settingsButtons(Icons.calculate, "طريقة الحساب", () {
                  _showCalculationMethodDialog();
                }),
                _settingsButtons(Icons.mosque, "Adhani\nversion : 1.0", () {}),

                const SizedBox(height: 32),

                const Divider(color: AppColors.cardFill),
                SizedBox(height: 5),
                Center(
                  child: const Text(
                    "Designed & Devloped by :",
                    style: TextStyle(
                      color: AppColors.body,
                      fontSize: 24,
                      fontFamily: 'cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final url = Uri.parse("https://github.com/ki1lux");
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      throw 'Could not launch $url';
                    }
                  },
                  child: Icon(
                    Icons.link,
                    color: AppColors.body,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "khalilbenfiala001@gmail.com",
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 12,
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _settingsButtons(IconData icon, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Material(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.sheetTop,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(icon, color: AppColors.body, size: 28),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: 16,
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _tileDecoration() {
    return BoxDecoration(
      color: AppColors.sheetTop,
      borderRadius: BorderRadius.circular(24),
    );
  }

  void _showAlarmStatusDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.sheetTop,
          title: Text(
            'Prayer Alarm Status',
            style: TextStyle(color: AppColors.body, fontFamily: 'cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  alarmStatus.entries.map((entry) {
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
                            style: TextStyle(
                              color: AppColors.body,
                              fontFamily: 'cairo',
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            isPassed
                                ? 'Tomorrow $nextOccurrence'
                                : 'Today ${data['time']}',
                            style: TextStyle(
                              color: isPassed ? AppColors.warning : AppColors.success,
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
              child: Text(
                'Close',
                style: TextStyle(color: AppColors.body, fontFamily: 'cairo'),
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
          title: Text(
            'استكشاف الأخطاء وإصلاحها',
            style: TextStyle(
              color: AppColors.body,
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
                    bool granted = await PrayerAlarmScheduler.checkExactAlarmPermission();
                    if (!granted) {
                      await PrayerAlarmScheduler.requestExactAlarmPermission();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('الإذن مفعل بالفعل ✅')),
                      );
                    }
                  },
                ),
                SizedBox(height: 16),
                _buildTroubleshootItem(
                  "2. تحسين البطارية (Battery Optimization)",
                  "بعض الهواتف توقف التطبيق في الخلفية. يرجى استثناء التطبيق من تحسين البطارية.",
                  () async {
                     const channel = MethodChannel('com.myadhan/notification');
                     await channel.invokeMethod('openBatterySettings');
                  },
                ),
                SizedBox(height: 16),
                Text(
                  "نصيحة: إذا كان هاتفك من نوع Xiaomi أو Huawei، ابحث عن إعدادات 'التشغيل التلقائي' (Autostart) وقم بتفعيل التطبيق.",
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontFamily: 'cairo',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'إغلاق',
                style: TextStyle(color: AppColors.body, fontFamily: 'cairo'),
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
            style: TextStyle(
              color: AppColors.body,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              fontFamily: 'cairo',
            ),
          ),
          SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(
              color: AppColors.secondary,
              fontSize: 13,
              fontFamily: 'cairo',
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
            ),
            child: Text(
              "اضغط هنا للتحقق / الإصلاح",
              style: TextStyle(color: Colors.blueAccent, fontSize: 12),
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
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'تعطيل تحسين البطارية',
          style: TextStyle(color: AppColors.body, fontFamily: 'cairo'),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.battery_alert, color: AppColors.accent, size: 48),
            const SizedBox(height: 16),
            const Text(
              'لضمان وصول إشعارات الصلاة في وقتها بدقة:\n\n'
              '1. اضغط "فتح الإعدادات"\n'
              '2. ابحث عن التطبيق واختر "غير مُحسّن"\n'
              '3. هذا يمنع Android من تأخير الإشعارات',
              style: TextStyle(color: AppColors.secondary, fontFamily: 'cairo', height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: AppColors.label)),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('فتح الإعدادات', style: TextStyle(color: AppColors.body)),
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.sheetBottom,
          title: const Text(
            'طريقة الحساب',
            style: TextStyle(
              color: AppColors.body,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              fontSize: 24,
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
                // ignore: deprecated_member_use
                return RadioListTile<int>(
                  title: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.body,
                      fontFamily: 'Cairo',
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    nameEn,
                    style: const TextStyle(
                      color: AppColors.label,
                      fontSize: 12,
                    ),
                  ),
                  value: id,
                  // ignore: deprecated_member_use
                  groupValue: currentMethod,
                  activeColor: const Color(0xFF0768C5),
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    setDialogState(() => currentMethod = value!);
                  },
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
                  fontFamily: 'Cairo',
                  fontSize: 16,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                await prefs.setInt('calculation_method', currentMethod);
                Navigator.pop(context);

                // Refresh prayer times with new method
                ref.read(prayerTimesProvider.notifier).fetchPrayerTimes();

                // Reschedule alarms after prayer provider updates
                final prayerTimesAsync = ref.read(prayerTimesProvider);
                if (prayerTimesAsync.hasValue) {
                  await PrayerAlarmScheduler.scheduleAllPrayersWithData(
                    prayerTimesAsync.value!,
                  );
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تغيير طريقة الحساب ✅')),
                  );
                }
              },
              child: const Text(
                'حفظ',
                style: TextStyle(
                  color: AppColors.body,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
