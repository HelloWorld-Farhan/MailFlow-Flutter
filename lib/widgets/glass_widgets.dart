import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Theme-aware MailFlow logo badge that adapts the inner mark & container for Dark Mode.
class AppLogo extends StatelessWidget {
  final double size;
  final double padding;
  final double borderRadius;

  const AppLogo({
    super.key,
    this.size = 26,
    this.padding = 4,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      width: size + padding * 2,
      height: size + padding * 2,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.coffeeBean2 : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark ? AppTheme.blackberryCream : AppTheme.divider,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: AppTheme.blackberryCream.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 340),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: ClipRRect(
          key: ValueKey(isDark),
          borderRadius: BorderRadius.circular((borderRadius - 4).clamp(4, 24)),
          child: Image.asset(
            isDark ? 'assets/Black-Logo.png' : 'assets/Logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// Centers content cleanly on tablets/desktops while filling phones edge-to-edge.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 860,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    return content;
  }
}

/// Translucent frosted-glass surface with backdrop blur and soft border.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blurSigma = 14,
    this.padding,
    this.color,
    this.borderColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final isDark = AppTheme.isDark(context);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? (isDark ? AppTheme.darkCard : Colors.white).withValues(alpha: isDark ? 0.84 : 0.78),
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? AppTheme.border(context).withValues(alpha: 0.9),
            ),
            boxShadow: boxShadow ??
                [
                  BoxShadow(
                    color: (isDark ? Colors.black : AppTheme.primaryBlue).withValues(alpha: isDark ? 0.25 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted glass background widget for `AppBar.flexibleSpace` / `SliverAppBar`.
Widget buildGlassAppBarBackground({Color? tint}) {
  return Builder(
    builder: (context) {
      final isDark = AppTheme.isDark(context);
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: tint ?? (isDark ? AppTheme.darkBg : Colors.white).withValues(alpha: isDark ? 0.84 : 0.78),
          ),
        ),
      );
    },
  );
}

/// Page route with opaque scaffold backing, blur-in, and smooth slide + fade transition.
class BlurredPageRoute<T> extends PageRouteBuilder<T> {
  BlurredPageRoute({required WidgetBuilder builder})
      : super(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final sigma = (1.0 - curved.value) * 6.0;
            // Opaque backing prevents the previous route from bleeding through during fade/blur.
            return ColoredBox(
              color: AppTheme.scaffoldBg(context),
              child: FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: sigma > 0.05
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                          child: child,
                        )
                      : child,
                ),
              ),
            );
          },
        );
}

/// Opens a dialog over a fast, lag-free translucent scrim with scale + fade entrance.
Future<T?> showBlurredDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
