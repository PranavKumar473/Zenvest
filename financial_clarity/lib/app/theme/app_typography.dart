/// Financial Clarity — Typography System.
///
/// Uses 'Syne' for bold display headings and 'Inter' for body/data text.
/// Both loaded via Google Fonts with system fallbacks.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  // ── Syne — Display & Headings ────────────────────────────────
  /// H1: Dashboard title, hero text
  static TextStyle displayLarge = GoogleFonts.syne(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.2,
    letterSpacing: -0.5,
  );

  /// H2: Section headings, card titles
  static TextStyle displayMedium = GoogleFonts.syne(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// H3: Sub-section headings
  static TextStyle displaySmall = GoogleFonts.syne(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.3,
  );

  /// Title Large: Card headers
  static TextStyle titleLarge = GoogleFonts.syne(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.3,
  );

  /// Title Medium: List section headers
  static TextStyle titleMedium = GoogleFonts.syne(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.35,
  );

  /// Title Small: Small card titles
  static TextStyle titleSmall = GoogleFonts.syne(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.4,
  );

  // ── Inter — Body, Data, Labels ───────────────────────────────
  /// Body Large: Primary body text
  static TextStyle bodyLarge = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    height: 1.5,
  );

  /// Body Medium: Transaction lists, data tables
  static TextStyle bodyMedium = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    height: 1.45,
  );

  /// Body Small: Captions, timestamps, secondary info
  static TextStyle bodySmall = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.inkMuted,
    height: 1.4,
  );

  /// Label Large: Button text, active tabs
  static TextStyle labelLarge = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.4,
    letterSpacing: 0.3,
  );

  /// Label Medium: Chips, tags
  static TextStyle labelMedium = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.inkLight,
    height: 1.35,
    letterSpacing: 0.2,
  );

  /// Label Small: Micro labels, badges
  static TextStyle labelSmall = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.inkMuted,
    height: 1.3,
    letterSpacing: 0.3,
  );

  // ── Special Purpose ──────────────────────────────────────────
  /// Large monetary value display
  static TextStyle moneyLarge = GoogleFonts.syne(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.1,
    letterSpacing: -1.0,
  );

  /// Medium monetary value
  static TextStyle moneyMedium = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.2,
  );

  /// Percentage / metric values
  static TextStyle metric = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    height: 1.3,
  );

  /// Build the complete TextTheme
  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        headlineLarge: titleLarge,
        headlineMedium: titleMedium,
        headlineSmall: titleSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      );
}
