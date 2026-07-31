import 'package:flutter/material.dart';
import 'package:myadhan/theme/app_colors.dart';

/// The placeholder's resting colour, and the crest of the sweep.
///
/// Both are **opaque on purpose.** [AppShimmer] masks with
/// `BlendMode.srcATop`, which keeps the *destination's* alpha — so painting a
/// sweep onto a 4.3%-opaque box clamps the whole effect to 4.3% opacity no
/// matter how bright the shader is. That's what made the first version look
/// static: the animation was running, it just had almost no alpha to show up
/// in. These are `cardFill`/a brighter lift already composited over
/// `surface`, so the sweep has full alpha to work with.
/// Composed from palette tokens rather than pasted hexes, so they stay
/// correct if the navy or the card fill changes.
final _shimmerBase = Color.alphaBlend(AppColors.cardFill, AppColors.surface);
final _shimmerHighlight = Color.alphaBlend(
  // Roughly 20% white — enough separation from the base to read as motion.
  // `barFill`'s 7% was only ~3 points brighter than `cardFill`'s 4.3%, which
  // is invisible in motion.
  const Color(0x33FFFFFF),
  AppColors.surface,
);

/// A sweeping highlight for skeleton placeholders.
///
/// Hand-rolled rather than pulling in the `shimmer` package: it's one
/// `ShaderMask` over an `AnimationController`, and the app's dependency list
/// is deliberately short. Wrap a tree of [ShimmerBox]es in this — the mask
/// applies to whatever it contains, so one controller drives a whole screen
/// instead of one per placeholder.
class AppShimmer extends StatefulWidget {
  final Widget child;

  const AppShimmer({super.key, required this.child});

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    // Eased rather than linear so the band accelerates through the middle
    // and settles at the edges — it reads as a pass of light instead of a
    // mechanical scroll.
    _sweep = CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _sweep,
        child: widget.child,
        builder: (context, child) {
          return ShaderMask(
            // srcATop so the sweep only paints where the placeholders
            // actually are, leaving the gaps between them untouched.
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                // Sweeps right-to-left, following the app's reading
                // direction rather than against it.
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [_shimmerBase, _shimmerHighlight, _shimmerBase],
                // A narrow band: a wide one covers most of the width at
                // once, which is why a gentle gradient can look like it
                // isn't moving at all.
                stops: const [0.35, 0.5, 0.65],
                transform: _SlideTransform(_sweep.value),
              ).createShader(bounds);
            },
            child: child,
          );
        },
      ),
    );
  }
}

/// Slides the gradient across the masked bounds. Travels a full width past
/// each edge so the highlight enters and leaves cleanly instead of popping
/// at the boundaries.
class _SlideTransform extends GradientTransform {
  final double progress;

  const _SlideTransform(this.progress);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * (progress * 3.0 - 1.5);
    return Matrix4.translationValues(dx, 0, 0);
  }
}

/// A single placeholder block.
///
/// Opaque by design — see [_shimmerBase]. A translucent placeholder would
/// swallow the sweep.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    BorderRadius? borderRadius,
  }) : borderRadius =
           borderRadius ?? const BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _shimmerBase,
        borderRadius: borderRadius,
      ),
    );
  }
}
