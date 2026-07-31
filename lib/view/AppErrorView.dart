import 'package:flutter/material.dart';
import 'package:myadhan/services/app_exception.dart';
import 'package:myadhan/theme/app_colors.dart';
import 'package:myadhan/view/AppBackground.dart';

/// The app's error state: what went wrong, what to do about it, and a way to
/// try again.
///
/// Replaces `Text('$error')`, which rendered the raw exception object — users
/// were reading `Exception: API request failed: 500`. Wording is chosen here
/// from [AppException.kind] rather than passed up from the throwing layer, so
/// every screen phrases the same failure the same way.
class AppErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const AppErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final e = AppException.from(error);
    final (icon, title, detail) = _copyFor(e.kind);

    // The technical text still needs to reach a bug report — it just must
    // never reach the screen.
    debugPrint('AppErrorView: ${e.debugMessage}');

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: AppBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A tinted badge, not a full-bleed red screen. Red stays a
                  // marker here, consistent with how DESIGN_IDENTITY.md
                  // scopes it — the old state coloured every line of text in
                  // it, which read as alarming out of proportion to a failed
                  // network call.
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, color: AppColors.danger, size: 30),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 13.5,
                      height: 1.6,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _RetryButton(onTap: onRetry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One place to phrase every failure. Each detail line says what the user
  /// can actually do — "حاول مجددًا" alone tells them nothing they didn't
  /// already know from the retry button.
  (IconData, String, String) _copyFor(AppErrorKind kind) {
    switch (kind) {
      case AppErrorKind.network:
        return (
          Icons.wifi_off_rounded,
          'لا يوجد اتصال بالإنترنت',
          'تحقّق من اتصالك بالشبكة ثم أعد المحاولة.',
        );
      case AppErrorKind.server:
        return (
          Icons.cloud_off_rounded,
          'تعذّر جلب المواقيت',
          'الخدمة غير متاحة حاليًا. أعد المحاولة بعد قليل.',
        );
      case AppErrorKind.location:
        return (
          Icons.location_off_rounded,
          'تعذّر تحديد موقعك',
          'فعّل خدمة الموقع، أو اختر مدينتك يدويًا من شاشة المواقيت.',
        );
      case AppErrorKind.locationPermission:
        return (
          Icons.lock_outline_rounded,
          'إذن الموقع مرفوض',
          'امنح التطبيق إذن الوصول إلى الموقع من إعدادات النظام.',
        );
      case AppErrorKind.unknown:
        return (
          Icons.error_outline_rounded,
          'حدث خطأ غير متوقّع',
          'أعد المحاولة، وإذا استمرّت المشكلة أعد تشغيل التطبيق.',
        );
    }
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RetryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.body,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, color: AppColors.surface, size: 18),
              SizedBox(width: 8),
              Text(
                'إعادة المحاولة',
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.surface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
