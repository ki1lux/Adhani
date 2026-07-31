import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myadhan/providers/prayer_times_provider.dart';
import 'package:myadhan/theme/app_colors.dart';

/// Tells the user the times they're looking at came from the cache.
///
/// Deliberately not an error: with a month of times stored locally the app is
/// still fully correct offline, so this is an aside, not an interruption. It
/// uses [AppColors.warning] rather than `danger` for exactly that reason —
/// red would claim something is broken when nothing is.
///
/// Reads [prayerDataStatusProvider], which rides alongside the prayer times
/// `AsyncValue` so no existing `.when()` call site had to learn about offline.
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  /// Dismissal lasts for the session only. Persisting it would mean a user who
  /// waved the banner away once never learns their times are a month old.
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(prayerDataStatusProvider);

    // Re-arm on recovery: once we sync successfully, a later outage deserves
    // to be mentioned again.
    if (!status.shouldWarn && _dismissed) {
      _dismissed = false;
    }

    final visible = status.shouldWarn && !_dismissed;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: visible ? 1 : 0,
        child: visible
            ? _Banner(
                title: status.isStale
                    ? 'المواقيت قد لا تكون محدّثة'
                    : 'وضع دون اتصال',
                detail: _detailFor(status),
                onDismiss: () => setState(() => _dismissed = true),
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }

  String _detailFor(PrayerDataStatus status) {
    final synced = status.lastSyncedAt;
    if (synced == null) return 'مواقيت محفوظة على الجهاز';

    final ago = DateTime.now().difference(synced);
    if (ago.inMinutes < 60) return 'آخر تحديث منذ قليل';
    if (ago.inHours < 24) return 'آخر تحديث منذ ${ago.inHours} ساعة';
    return 'آخر تحديث منذ ${ago.inDays} يوم';
  }
}

class _Banner extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onDismiss;

  const _Banner({
    required this.title,
    required this.detail,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.cardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: AppColors.warning.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.body,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 11,
                    color: AppColors.label,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 16px glyph + 16px of padding on each side = 48x48. The old
          // EdgeInsets.all(4) gave a 24dp target, half the accessible minimum
          // — and this is the only way to dismiss the banner.
          Semantics(
            label: 'إخفاء التنبيه',
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onDismiss,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.faint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
