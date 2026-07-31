import 'package:flutter/material.dart';
import 'package:myadhan/theme/app_colors.dart';

/// How a confirmation reads. The surface stays identical across both — only
/// the badge changes colour — so this remains one component with a state
/// accent rather than two lookalike components competing for the same slot.
enum ToastKind { success, error }

/// Adhani's single confirmation toast.
///
/// Consolidates the three hand-rolled `SnackBar`s that had drifted apart
/// across SettingsScreen, QiblaScreen and PrayerTimeScreen — same intent,
/// three copies, three sets of defaults.
///
/// The `SnackBar` itself is transparent with no padding; everything visible
/// is drawn by [_ToastBody]. Material's own surface only accepts a flat
/// `backgroundColor`, which can't carry the sheet gradient or a hairline
/// border, and it forces its own content padding.
///
/// **Show every confirmation through here** so the app speaks with one voice.
abstract final class AppToast {
  static const _duration = Duration(seconds: 3);

  /// Bottom nav is 58 tall with 16 of padding under it (see
  /// `main.dart#_buildBottomNav`), and `MainScreen` sets `extendBody: true`.
  /// Each tab hosts its own `Scaffold` with no `bottomNavigationBar` of its
  /// own, so Flutter can't lift the toast above the bar for us — without
  /// this the toast slides in underneath it.
  static const _navBarClearance = 58.0 + 16.0 + 8.0;

  /// [title] is the outcome ("تم حفظ الإعدادات"); [detail] is the optional
  /// consequence ("سيؤذّن المغرب بنغمة «الأذان الأول»"). Keep [title] short —
  /// it's the line people actually read.
  static void success(BuildContext context, String title, {String? detail}) =>
      _show(context, title, detail, ToastKind.success);

  static void error(BuildContext context, String title, {String? detail}) =>
      _show(context, title, detail, ToastKind.error);

  static void _show(
    BuildContext context,
    String title,
    String? detail,
    ToastKind kind,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    // Replace rather than queue: tapping an action three times used to mean
    // watching three identical toasts play out back to back.
    messenger.removeCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        duration: _duration,
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        padding: EdgeInsets.zero,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: _navBarClearance + MediaQuery.viewPaddingOf(context).bottom,
        ),
        content: _ToastBody(title: title, detail: detail, kind: kind),
      ),
    );
  }
}

class _ToastBody extends StatelessWidget {
  final String title;
  final String? detail;
  final ToastKind kind;

  const _ToastBody({required this.title, this.detail, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isError = kind == ToastKind.error;

    return Directionality(
      // The messages are Arabic; the badge belongs on the reading-start
      // side, which is the right.
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          // The nav bar's exact recipe — `barFill`'s 7% white lift over the
          // navy — just resolved to an opaque colour, since a toast floats
          // over arbitrary screen content and can't rely on what's behind it.
          //
          // Deliberately NOT the `sheetTop` blue that dialogs use: a dialog
          // owns the screen behind a scrim, so it can afford to be its own
          // surface. A toast is seen side by side with the nav bar it sits
          // directly above, and against that neighbour the dialog blue read
          // as a different app.
          color: Color.alphaBlend(AppColors.barFill, AppColors.surface),
          // Matches the card/row family (16) rather than the dialog family
          // (24) — it's a small floating surface, not a sheet.
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A filled badge, not a bare tinted glyph: at this size the
            // status needs to register before the text is read.
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isError ? AppColors.dangerDeep : AppColors.successDeep,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                isError ? Icons.close_rounded : Icons.check_rounded,
                color: AppColors.heading,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.heading,
                      height: 1.3,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 12.5,
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
