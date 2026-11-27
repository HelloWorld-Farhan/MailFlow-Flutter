import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dashboard_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _dotController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          BlurredPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _dotController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = AppTheme.isDark(context);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Stack(
        children: [
          // ── Decorative top-left blob ──────────────────────────────────
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? AppTheme.blackberryCream : AppTheme.primaryBlue).withValues(alpha: isDark ? 0.36 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // ── Decorative bottom-right blob ──────────────────────────────
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? AppTheme.midnightViolet : AppTheme.accentBlue).withValues(alpha: isDark ? 0.32 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Wave at bottom ────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) => CustomPaint(
                size: Size(size.width, 160),
                painter: _WavePainter(_waveController.value, isDark),
              ),
            ),
          ),

          // ── Main centered content ─────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo in frosted glass card with blur-in entrance
                GlassContainer(
                  borderRadius: 32,
                  blurSigma: 18,
                  padding: const EdgeInsets.all(14),
                  color: (isDark ? AppTheme.darkCard : Colors.white).withValues(alpha: isDark ? 0.88 : 0.82),
                  borderColor: (isDark ? AppTheme.blackberryCream : AppTheme.primaryBlue).withValues(alpha: isDark ? 0.55 : 0.18),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? AppTheme.blackberryCream : AppTheme.primaryBlue).withValues(alpha: isDark ? 0.34 : 0.14),
                      blurRadius: 36,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  child: const AppLogo(size: 86, padding: 6, borderRadius: 22),
                )
                    .animate()
                    .fade(duration: 550.ms)
                    .blur(begin: const Offset(12, 12), end: Offset.zero, duration: 550.ms)
                    .scale(
                      begin: const Offset(0.7, 0.7),
                      curve: Curves.easeOutBack,
                      duration: 700.ms,
                    ),

                const SizedBox(height: 28),

                // App name
                Text(
                  'MailFlow',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary(context),
                    letterSpacing: 1.5,
                  ),
                )
                    .animate(delay: 250.ms)
                    .fade(duration: 500.ms)
                    .blur(begin: const Offset(8, 8), end: Offset.zero, duration: 500.ms)
                    .slideY(begin: 0.35, end: 0.0, duration: 500.ms),

                const SizedBox(height: 8),

                // Tagline
                Text(
                  'Email Automation, Simplified',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    color: AppTheme.textSecondary(context),
                    letterSpacing: 0.4,
                  ),
                )
                    .animate(delay: 420.ms)
                    .fade(duration: 450.ms)
                    .blur(begin: const Offset(6, 6), end: Offset.zero, duration: 450.ms),

                const SizedBox(height: 56),

                // Dot loader
                AnimatedBuilder(
                  animation: _dotController,
                  builder: (context, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final delay = i * 0.33;
                        final t = (_dotController.value + delay) % 1.0;
                        final scale = 0.6 + 0.5 * sin(t * pi);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ).animate(delay: 900.ms).fade(duration: 400.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final bool isDark;
  _WavePainter(this.progress, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    void drawWave(double opacity, double heightFactor, double offset) {
      final paint = Paint()
        ..color = (isDark ? AppTheme.blackberryCream : AppTheme.primaryBlue).withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      final path = Path();
      path.moveTo(0, size.height * heightFactor);
      for (int i = 0; i <= size.width.toInt(); i++) {
        final y = size.height * heightFactor +
            sin((i / size.width) * 2 * pi + progress * 2 * pi + offset) *
                size.height * 0.2;
        path.lineTo(i.toDouble(), y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }

    drawWave(0.08, 0.30, 0.0);
    drawWave(0.12, 0.50, 1.0);
    drawWave(0.18, 0.65, 2.0);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}
