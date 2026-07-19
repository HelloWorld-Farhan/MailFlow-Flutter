import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/Logo.png',
              width: 120,
              height: 120,
            ).animate()
             .fade(duration: 800.ms)
             .scale(delay: 200.ms, duration: 600.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              'MailFlow',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                letterSpacing: 2,
                fontSize: 32,
              ),
            ).animate()
             .fade(delay: 600.ms, duration: 800.ms)
             .slideY(begin: 0.5, end: 0, curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }
}
