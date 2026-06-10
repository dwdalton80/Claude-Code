import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const warmGold = Color(0xFFC9942A);
  static const flameOrange = Color(0xFFFF6B35);
  static const deepSlate = Color(0xFF1A1D2E);
  static const warmWhite = Color(0xFFFAFAF7);
  static const emerald = Color(0xFF2E7D5E);
  static const indigoAccent = Color(0xFF2D3A8C);
  static const textPrimary = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF6E6E73);

  // Semantic
  static const success = emerald;
  static const xpGold = warmGold;
  static const streak = flameOrange;
  static const error = Color(0xFFFF3B30);
  static const warning = Color(0xFFFF9F0A);

  // Highlight colors
  static const highlightYellow = Color(0xFFFFF176);
  static const highlightGreen = Color(0xFFA5D6A7);
  static const highlightBlue = Color(0xFF90CAF9);
  static const highlightPink = Color(0xFFF48FB1);

  // Surface variants
  static const surface = Color(0xFF252838);
  static const surfaceVariant = Color(0xFF2E3147);
  static const cardDark = Color(0xFF1E2235);

  // Gradient stops
  static const flameGradientStart = Color(0xFFFF6B35);
  static const flameGradientEnd = Color(0xFFC9942A);

  static const LinearGradient flameGradient = LinearGradient(
    colors: [flameGradientStart, flameGradientEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient flameCTAGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFE8561F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
