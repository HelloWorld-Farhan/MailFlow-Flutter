import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dashboard_screen.dart';
import '../theme/app_theme.dart';

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

    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, a, __) => const DashboardScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
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

    return Scaffold(
      backgroundColor: Colors.white,
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
                    AppTheme.primaryBlue.withOpacity(0.12),
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
                    AppTheme.accentBlue.withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── Blue wave at bottom ───────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (_, __) => CustomPaint(
                size: Size(size.width, 160),
                painter: _WavePainter(_waveController.value),
              ),
            ),
          ),

          // ── Main centered content ─────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo in white card with subtle blue border
                Container(
                  width: 130,
                  height: 130,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withOpacity(0.15),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.12),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset('assets/Logo.png', fit: BoxFit.contain),
                )
                    .animate()
                    .fade(duration: 600.ms)
                    .scale(
                      begin: const Offset(0.6, 0.6),
                      curve: Curves.easeOutBack,
                      duration: 800.ms,
                    ),

                const SizedBox(height: 28),

                // App name
                const Text(
                  'MailFlow',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: 1.5,
                  ),
                )
                    .animate(delay: 400.ms)
                    .fade(duration: 600.ms)
                    .slideY(begin: 0.4, end: 0.0, duration: 600.ms),

                const SizedBox(height: 8),

                // Tagline
                Text(
                  'Email Automation, Simplified',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    color: AppTheme.textMid,
                    letterSpacing: 0.4,
                  ),
                )
                    .animate(delay: 650.ms)
                    .fade(duration: 500.ms),

                const SizedBox(height: 56),

                // Dot loader
                AnimatedBuilder(
                  animation: _dotController,
                  builder: (_, __) {
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
  _WavePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    void drawWave(double opacity, double heightFactor, double offset) {
      final paint = Paint()
        ..color = AppTheme.primaryBlue.withOpacity(opacity)
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
