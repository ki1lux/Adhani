import 'package:flutter/material.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The prominent disclosure Google Play requires before location access.
///
/// Play's User Data policy is explicit: when an app collects location and
/// sends it off the device, it must show an in-app disclosure *before* the
/// runtime permission prompt, naming the data and what it's used for, with an
/// affirmative action to continue. The app previously went straight to
/// `Permission.locationWhenInUse.request()` on first frame — coordinates leave
/// the device on the very next call (Aladhan for the times, Nominatim for the
/// city name), so that is exactly the case the policy covers, and it is one of
/// the most common reasons a first submission is rejected.
///
/// Shown once. [wasAccepted] records the answer so a user who declines isn't
/// asked again on every launch — the app degrades to cached times and a
/// manually chosen city, which it already supports.
class LocationDisclosure extends StatelessWidget {
  static const _prefsKey = 'location_disclosure_shown';

  const LocationDisclosure({super.key});

  /// Returns true when the user has already seen this dialog.
  static Future<bool> hasBeenShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  /// Shows the disclosure and records that it was shown.
  ///
  /// Resolves to true when the user chose to continue — only then may the
  /// caller request the location permission.
  static Future<bool> show(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.scrim,
      builder: (_) => const LocationDisclosure(),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);

    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: AppColors.sheetBottom,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, color: AppColors.accent, size: 40),
            SizedBox(height: 12),
            Text(
              'لماذا نحتاج موقعك؟',
              style: TextStyle(
                color: AppColors.heading,
                fontFamily: 'cairo',
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'يستخدم «أذاني» موقعك الجغرافي لحساب مواقيت الصلاة الدقيقة '
                'واتجاه القبلة في مكانك.',
                style: TextStyle(
                  color: AppColors.body,
                  fontFamily: 'cairo',
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
              SizedBox(height: 14),
              _Bullet(
                'تُرسَل إحداثياتك إلى خدمة Aladhan لحساب المواقيت، وإلى '
                'OpenStreetMap لمعرفة اسم مدينتك.',
              ),
              _Bullet('لا نجمع موقعك إلا أثناء استخدامك للتطبيق.'),
              _Bullet('لا نحتفظ بموقعك على أي خادم ولا نشاركه مع أي جهة أخرى.'),
              SizedBox(height: 10),
              Text(
                'يمكنك الرفض والاستمرار باختيار مدينتك يدويًا من شاشة المواقيت.',
                style: TextStyle(
                  color: AppColors.label,
                  fontFamily: 'cairo',
                  fontSize: 12.5,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
            child: const Text(
              'ليس الآن',
              style: TextStyle(color: AppColors.label, fontFamily: 'cairo'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.body,
              foregroundColor: AppColors.surface,
              elevation: 0,
              minimumSize: const Size(120, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'موافق، تابع',
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
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 5, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.secondary,
                fontFamily: 'cairo',
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
