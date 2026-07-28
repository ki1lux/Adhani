import 'package:flutter/material.dart';
import 'package:myadhan/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  //  Card 
  late final AnimationController _cardCtrl;
  late final Animation<double> _cardScale;
  late final Animation<double> _cardFade;

  //  icon
  late final AnimationController _iconCtrl;
  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<Offset> _iconSlide;

  //  Glow pulse 
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    // Card
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _cardScale = Tween(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.elasticOut));
    _cardFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: const Interval(0.0, 0.35, curve: Curves.easeIn)));

    // Icon
    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _iconFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut));
    _iconScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOutBack));
    _iconSlide = Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut));

    //  Glow
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _glowAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await _cardCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 50));
    await _iconCtrl.forward();
    _glowCtrl.repeat(reverse: true);
    await Future.delayed(const Duration(milliseconds: 1100));
    _navigate();
  }

  void _navigate() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => widget.nextScreen,
      transitionDuration: const Duration(milliseconds: 700),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn), child: child),
    ));
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    _iconCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_cardCtrl, _iconCtrl, _glowCtrl]),
        builder: (_, __) {
          final glowOpacity = 0.12 + (_glowAnim.value * 0.22);
          final glowBlur    = 28.0 + (_glowAnim.value * 22.0);

          return Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [Color(0xFF1E2A3A), Color(0xFF0B1220)],
              ),
            ),
            child: Center(
              child: FadeTransition(
                opacity: _cardFade,
                child: ScaleTransition(
                  scale: _cardScale,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [

                      // Glow
                      Container(
                        width: 178, height: 178,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [BoxShadow(
                            color: Colors.white.withValues(alpha: glowOpacity),
                            blurRadius: glowBlur,
                            spreadRadius: 6,
                          )],
                        ),
                      ),

                      // White rounded card
                      Container(
                        width: 160, height: 160,
                        decoration: BoxDecoration(
                          color: AppColors.archTop,
                          borderRadius: BorderRadius.circular(36),
                          boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          )],
                        ),

                        // icon file — animated
                        child: FadeTransition(
                          opacity: _iconFade,
                          child: ScaleTransition(
                            scale: _iconScale,
                            child: SlideTransition(
                              position: _iconSlide,
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Image.asset(
                                  'assets/mainIcon.png', 
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
