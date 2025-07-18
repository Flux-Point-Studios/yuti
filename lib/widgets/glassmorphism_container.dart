import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

enum GlassType {
  light,
  medium,
  dark,
  card,
  overlay,
}

class GlassmorphismContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final GlassType glassType;
  final double blur;
  final bool showBorder;
  final bool showGlow;
  final Gradient? customGradient;
  final Color? customBorderColor;

  const GlassmorphismContainer({
    Key? key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.glassType = GlassType.medium,
    this.blur = 15.0,
    this.showBorder = true,
    this.showGlow = false,
    this.customGradient,
    this.customBorderColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: customGradient ?? _getGradientForType(),
              borderRadius: borderRadius ?? BorderRadius.circular(16),
              border: showBorder ? Border.all(
                color: customBorderColor ?? _getBorderColorForType(),
                width: 1.0,
              ) : null,
              boxShadow: showGlow ? [
                BoxShadow(
                  color: AppColors.glowColor,
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: AppColors.shadowColorDeep,
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ] : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Gradient _getGradientForType() {
    switch (glassType) {
      case GlassType.light:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x20FFFFFF),
            Color(0x10FFFFFF),
            Color(0x08000000),
          ],
          stops: [0.0, 0.5, 1.0],
        );
      case GlassType.medium:
        return AppColors.smokedGlassGradient;
      case GlassType.dark:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x15FFFFFF),
            Color(0x08FFFFFF),
            Color(0x12000000),
          ],
          stops: [0.0, 0.3, 1.0],
        );
      case GlassType.card:
        return AppColors.cardGradient;
      case GlassType.overlay:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x25000000),
            Color(0x40000000),
          ],
        );
    }
  }

  Color _getBorderColorForType() {
    switch (glassType) {
      case GlassType.light:
        return const Color(0x30FFFFFF);
      case GlassType.medium:
        return AppColors.glassBorder;
      case GlassType.dark:
        return const Color(0x20FFFFFF);
      case GlassType.card:
        return AppColors.glassBorder.withOpacity(0.6);
      case GlassType.overlay:
        return const Color(0x15FFFFFF);
    }
  }
}

// Specialized glassmorphism widgets for common use cases

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showGlow;
  final VoidCallback? onTap;

  const GlassCard({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.showGlow = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final glassContainer = GlassmorphismContainer(
      glassType: GlassType.card,
      padding: padding ?? const EdgeInsets.all(20),
      margin: margin,
      showGlow: showGlow,
      borderRadius: BorderRadius.circular(20),
      blur: 12.0,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: glassContainer,
      );
    }

    return glassContainer;
  }
}

class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final bool isPrimary;
  final bool showGlow;

  const GlassButton({
    Key? key,
    required this.child,
    this.onPressed,
    this.padding,
    this.isPrimary = false,
    this.showGlow = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: GlassmorphismContainer(
        glassType: isPrimary ? GlassType.medium : GlassType.light,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        borderRadius: BorderRadius.circular(12),
        blur: 10.0,
        showGlow: showGlow || isPrimary,
        customGradient: isPrimary ? AppColors.primaryGradient.scale(0.3) : null,
        child: child,
      ),
    );
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double? elevation;

  const GlassAppBar({
    Key? key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.elevation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AppBar(
          title: title,
          actions: actions,
          leading: leading,
          automaticallyImplyLeading: automaticallyImplyLeading,
          backgroundColor: AppColors.glassBackground,
          elevation: elevation ?? 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x18FFFFFF),
                  Color(0x08FFFFFF),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.glassBorder,
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// Extension to help with gradient scaling
extension GradientScale on Gradient {
  LinearGradient scale(double opacity) {
    if (this is LinearGradient) {
      final gradient = this as LinearGradient;
      return LinearGradient(
        begin: gradient.begin,
        end: gradient.end,
        colors: gradient.colors.map((color) => color.withOpacity(color.opacity * opacity)).toList(),
        stops: gradient.stops,
      );
    }
    return this as LinearGradient;
  }
}