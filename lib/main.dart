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
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (w, anim) {
                final sigma = (1.0 - anim.value) * 6.0;
                return FadeTransition(
                  opacity: anim,
                  child: sigma > 0.05
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                          child: w,
                        )
                      : w,
                );
              },
              child: KeyedSubtree(
                key: ValueKey(isDark),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
