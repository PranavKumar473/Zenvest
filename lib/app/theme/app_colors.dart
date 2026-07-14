/// Financial Clarity — Design System Color Tokens.
///
/// All application colors are defined here as a single source of truth.
/// No raw color values should be used outside this file.
import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Prevent instantiation

  // ── Primary Palette ──────────────────────────────────────────
  /// Deep Indigo — Primary accent for CTAs, active states, highlights
  static const Color primary = Color(0xFF3B3486);
  static const Color primaryLight = Color(0xFF5A52B8);
  static const Color primaryDark = Color(0xFF251F5C);
  static const Color primarySurface = Color(0xFFEDEBF8);

  // ── Ambient (decorative gradients / blurred backgrounds) ──────
  /// Warm cream-peach — paired with the indigo primary for premium
  /// duo-tone ambient backgrounds (auth screens).
  static const Color ambientCream = Color(0xFFFBEEDD);
  static const Color ambientPeach = Color(0xFFF3D9BD);

  // ── Canvas & Surface ─────────────────────────────────────────
  /// Light Paper Cream — Main background
  static const Color canvas = Color(0xFFF7F5F0);

  /// Slightly elevated surface
  static const Color surface = Color(0xFFFFFEFB);

  /// Card surface
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Subtle divider
  static const Color divider = Color(0xFFE8E5DE);

  /// Disabled background
  static const Color disabled = Color(0xFFE0DDD6);

  // ── Text / Ink ───────────────────────────────────────────────
  /// True Black — Primary text
  static const Color ink = Color(0xFF0D0D0D);

  /// Secondary text
  static const Color inkLight = Color(0xFF4A4A4A);

  /// Tertiary / hint text
  static const Color inkMuted = Color(0xFF8A8A8A);

  /// Inverse text on dark backgrounds
  static const Color inkOnPrimary = Color(0xFFF7F5F0);

  // ── System Alerts ────────────────────────────────────────────
  /// Warm Gold — Warnings, budget caution
  static const Color warning = Color(0xFFC9992F);
  static const Color warningLight = Color(0xFFFFF3D6);
  static const Color warningDark = Color(0xFF9A7420);

  /// Crimson — Errors, danger, budget overrun
  static const Color error = Color(0xFFC0392B);
  static const Color errorLight = Color(0xFFFDE8E6);
  static const Color errorDark = Color(0xFF962D22);

  /// Success green
  static const Color success = Color(0xFF27AE60);
  static const Color successLight = Color(0xFFE8F8EF);

  // ── Budget Threshold Gradient ────────────────────────────────
  /// Green → Amber → Red for budget progress bars
  static const Color budgetSafe = Color(0xFF27AE60);
  static const Color budgetWarning = Color(0xFFC9992F);
  static const Color budgetDanger = Color(0xFFC0392B);

  // ── Chart Colors ─────────────────────────────────────────────
  static const Color chartLine = Color(0xFF3B3486);
  static const Color chartFill = Color(0x333B3486);
  static const Color chartGrid = Color(0xFFE8E5DE);

  // ── Asset Type Colors (for pie charts & tags) ────────────────
  static const Color assetMutualFund = Color(0xFF3B3486);
  static const Color assetFixedDeposit = Color(0xFF2980B9);
  static const Color assetStocks = Color(0xFFE67E22);
  static const Color assetGold = Color(0xFFC9992F);
  static const Color assetBonds = Color(0xFF8E44AD);

  /// Get color for a budget threshold status
  static Color budgetColor(String status) {
    switch (status) {
      case 'danger':
        return budgetDanger;
      case 'warning':
        return budgetWarning;
      default:
        return budgetSafe;
    }
  }

  /// Get color for an asset type
  static Color assetColor(String assetType) {
    switch (assetType) {
      case 'mutual_fund':
        return assetMutualFund;
      case 'fixed_deposit':
        return assetFixedDeposit;
      case 'stocks':
        return assetStocks;
      case 'gold':
        return assetGold;
      case 'bonds':
        return assetBonds;
      default:
        return primary;
    }
  }
}
