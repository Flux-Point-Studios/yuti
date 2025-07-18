import 'package:flutter/material.dart';

class AppColors {
  // Primary blue light colors - sophisticated electric blue for the "bluelight" theme
  static const Color primaryBlue = Color(0xFF00D4FF);
  static const Color primaryBlueGlow = Color(0xFF0088CC);
  
  // Enhanced blue spectrum for glassmorphism
  static const Color lightBlue = Color(0xFF33E0FF);
  static const Color deepBlue = Color(0xFF0066BB);
  static const Color electricBlue = Color(0xFF0088FF);
  static const Color cyanBlue = Color(0xFF00AADD);

  // Enhanced blue light gradient colors for depth
  static const Color blueGlow1 = Color(0xFF00CCFF);
  static const Color blueGlow2 = Color(0xFF0077CC);
  static const Color blueGlow3 = Color(0xFF003366);
  static const Color blueGlow4 = Color(0xFF001122);

  // Very dark backgrounds for premium dark theme
  static const Color backgroundDark = Color(0xFF000000);
  static const Color backgroundDeep = Color(0xFF050508);
  static const Color backgroundMedium = Color(0xFF0A0A0F);
  static const Color backgroundLight = Color(0xFF151520);
  static const Color backgroundCard = Color(0xFF0C0C12);

  // Enhanced glassmorphism colors with sophisticated transparency
  static const Color glassWhite = Color(0x12FFFFFF);
  static const Color glassBlue = Color(0x1800D4FF);
  static const Color glassBorder = Color(0x2800D4FF);
  static const Color glassBackground = Color(0x0A000000);
  static const Color glassSurface = Color(0x15000000);
  static const Color glassOverlay = Color(0x08FFFFFF);
  
  // Sophisticated glass tints
  static const Color glassTintLight = Color(0x0F00D4FF);
  static const Color glassTintMedium = Color(0x18003366);
  static const Color glassTintDark = Color(0x25000000);

  // Text colors optimized for dark glass theme
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFE8E8F0);
  static const Color textTertiary = Color(0xFFB8B8C8);
  static const Color textQuaternary = Color(0xFF888898);
  static const Color textAccent = Color(0xFF00D4FF);
  static const Color textGlow = Color(0xFF66E0FF);

  // Status colors with enhanced blue light theme
  static const Color success = Color(0xFF00FF88);
  static const Color error = Color(0xFFFF3366);
  static const Color warning = Color(0xFFFFAA00);
  static const Color info = primaryBlue;

  // Enhanced gradient combinations for sophisticated glassmorphism
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, blueGlow2, blueGlow3],
    stops: [0.0, 0.6, 1.0],
  );

  static const LinearGradient blueGlowGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x4000D4FF),
      Color(0x1800D4FF),
      Color(0x0A003366),
      Color(0x15000000),
    ],
    stops: [0.0, 0.3, 0.7, 1.0],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x1800D4FF),
      Color(0x0F003366),
      Color(0x08000000),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient smokedGlassGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x20FFFFFF),
      Color(0x10FFFFFF),
      Color(0x05000000),
    ],
    stops: [0.0, 0.3, 1.0],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundDark, backgroundDeep, backgroundMedium],
    stops: [0.0, 0.5, 1.0],
  );

  // Premium curved blue gradient matching sophisticated design
  static const LinearGradient curvedBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF00D4FF),
      Color(0xFF0099CC),
      Color(0xFF006699),
      Color(0xFF003366),
    ],
    stops: [0.0, 0.3, 0.7, 1.0],
  );

  // Enhanced glowing effect colors for premium feel
  static const Color glowColor = Color(0x6000D4FF);
  static const Color glowColorStrong = Color(0x8000D4FF);
  static const Color shadowColor = Color(0x4000D4FF);
  static const Color shadowColorDeep = Color(0x6000D4FF);

  // Card and surface gradients for glassmorphism
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x15FFFFFF),
      Color(0x08FFFFFF),
      Color(0x05000000),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x12FFFFFF),
      Color(0x08000000),
    ],
  );
}
