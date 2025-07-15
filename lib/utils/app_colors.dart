import 'package:flutter/material.dart';

class AppColors {
  // Primary blue light colors - bright electric blue for the "bluelight" theme
  static const Color primaryBlue = Color(0xFF00D4FF);
  static const Color primaryBlueGlow = Color(0xFF0099CC);

  // Lighter blues for gradients and effects
  static const Color lightBlue = Color(0xFF33E0FF);
  static const Color veryLightBlue = Color(0xFF66EBFF);
  static const Color electricBlue = Color(0xFF0088FF);

  // Enhanced blue light gradient colors
  static const Color blueGlow1 = Color(0xFF00CCFF);
  static const Color blueGlow2 = Color(0xFF0077CC);
  static const Color blueGlow3 = Color(0xFF004499);

  // Very dark backgrounds for the blue light theme
  static const Color backgroundDark = Color(0xFF000000);
  static const Color backgroundMedium = Color(0xFF0A0A0A);
  static const Color backgroundLight = Color(0xFF1A1A1A);
  static const Color backgroundCard = Color(0xFF0F0F0F);

  // Glass morphism colors with blue tint
  static const Color glassWhite = Color(0x1A00D4FF);
  static const Color glassBorder = Color(0x3300D4FF);
  static const Color glassBackground = Color(0x0D00D4FF);

  // Text colors optimized for dark theme
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFE0E0E0);
  static const Color textTertiary = Color(0xFFAAAAAA);
  static const Color textAccent = Color(0xFF00D4FF);

  // Status colors with blue light theme
  static const Color success = Color(0xFF00FF88);
  static const Color error = Color(0xFFFF3366);
  static const Color warning = Color(0xFFFFAA00);
  static const Color info = primaryBlue;

  // Enhanced gradient combinations for blue light effect
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, blueGlow2],
  );

  static const LinearGradient blueGlowGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x4D00D4FF),
      Color(0x1A00D4FF),
      Color(0x0D000000),
    ],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x1A00D4FF),
      Color(0x0D000000),
    ],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundDark, backgroundMedium],
  );

  // Curved blue light gradient to match the logo
  static const LinearGradient curvedBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00D4FF),
      Color(0xFF0099CC),
      Color(0xFF006699),
    ],
  );

  // Glowing effect colors
  static const Color glowColor = Color(0x8000D4FF);
  static const Color shadowColor = Color(0x4000D4FF);
}
