import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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

/// Page route with animated blur-in and smooth slide+fade transition.
class BlurredPageRoute<T> extends PageRouteBuilder<T> {
  BlurredPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final sigma = (1.0 - curved.value) * 7.0;
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(curved),
                child: sigma > 0.05
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                        child: child,
                      )
                    : child,
              ),
            );
          },
        );
}

/// Opens a dialog over an animated frosted-blur backdrop with scale + fade entrance.
Future<T?> showBlurredDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      final blur = (animation.value * 9.0).clamp(0.0, 9.0);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: barrierDismissible ? () => Navigator.of(ctx).maybePop() : null,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.26 * animation.value),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
