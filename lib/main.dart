import 'dart:math' show pi, sin;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/app_config.dart';
import 'services/backend_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppTheme.loadThemeMode();
  await AppConfig.load();
  await NotificationService.initialize();
  await BackendService.startRealtime();
  runApp(const MailFlowApp());
}

class MailFlowApp extends StatelessWidget {
  const MailFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'MailFlow',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          themeAnimationDuration: const Duration(milliseconds: 380),
          themeAnimationCurve: Curves.easeInOutCubic,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: isDark ? AppTheme.darkBg : AppTheme.bgWhite,
              systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            ));
            return ThemeBlurOverlay(
              key: const Key('theme_blur_overlay'),
              isDark: isDark,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}

/// Applies a brief, per-frame blur pulse only when the theme brightness actually
/// changes, ensuring startup/restart never leaves the app blurred.
class ThemeBlurOverlay extends StatefulWidget {
  final bool isDark;
  final Widget child;
  const ThemeBlurOverlay({super.key, required this.isDark, required this.child});

  @override
  State<ThemeBlurOverlay> createState() => _ThemeBlurOverlayState();
}

class _ThemeBlurOverlayState extends State<ThemeBlurOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void didUpdateWidget(covariant ThemeBlurOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final sigma = _controller.isAnimating
            ? sin(_controller.value * pi) * 5.0
            : 0.0;
        if (sigma <= 0.05) return child!;
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        );
      },
    );
  }
}
