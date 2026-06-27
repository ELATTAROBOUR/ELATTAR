/// ─────────────────────────────────────────────────────────────────────────────
/// 🎨 ELATTAR Design System V2 — Luxe Premium
/// نظام التصميم الموحد — إصدار فاخر
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ⚡ ANIMATION CONSTANTS
// ═════════════════════════════════════════════════════════════════════════════
class AppAnimations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration page = Duration(milliseconds: 350);

  static const Curve defaultCurve = Curves.easeInOut;
  static const Curve springCurve = Curves.easeOutCubic;
  static const Curve bounceCurve = Curves.elasticOut;

  static const Cubic fastOutSlowIn = Cubic(0.4, 0.0, 0.2, 1.0);
}

// ═════════════════════════════════════════════════════════════════════════════
// 📐 SPACING SYSTEM (4px grid)
// ═════════════════════════════════════════════════════════════════════════════
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  static const EdgeInsets hSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets hMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets hLg = EdgeInsets.symmetric(horizontal: lg);

  static const EdgeInsets vSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets vMd = EdgeInsets.symmetric(vertical: md);

  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets listTilePadding =
      EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

// ═════════════════════════════════════════════════════════════════════════════
// 🎨 COLOR PALETTE — Luxe Premium
// ═════════════════════════════════════════════════════════════════════════════
class AppColors {
  // ── Brand: Gold (Luxury feel, warm & premium) ──
  static const Color primary = Color(0xFFD4AF37);
  static const Color primaryLight = Color(0xFFE8C84A);
  static const Color primaryDark = Color(0xFFB8962E);
  static const Color primaryGlow = Color(0x30D4AF37);

  // ── Secondary Accent: Vibrant Teal (modern, fresh contrast) ──
  static const Color accent = Color(0xFF2DD4BF);
  static const Color accentLight = Color(0xFFCCFBF1);
  static const Color accentDark = Color(0xFF0D9488);

  // ── Dark Mode Surfaces (deep midnight navy) ──
  static const Color surfaceDark = Color(0xFF080E1A);
  static const Color surfaceDarkAlt = Color(0xFF0B1323);
  static const Color cardDark = Color(0xFF111C2E);
  static const Color cardDarkElevated = Color(0xFF162338);
  static const Color sidebarDark = Color(0xFF0A1220);
  static const Color scaffoldDark = Color(0xFF060B14);

  // ── Light Mode Surfaces (warm creamy tones) ──
  static const Color surfaceLight = Color(0xFFF5F0EB);
  static const Color surfaceLightAlt = Color(0xFFFAF7F4);
  static const Color cardLight = Colors.white;
  static const Color cardLightElevated = Color(0xFFFAFAFA);
  static const Color sidebarLight = Color(0xFFF0EBE4);
  static const Color scaffoldLight = Color(0xFFF8F4F0);

  // ── Text ──
  static const Color textPrimary = Color(0xFF1A2A3A);
  static const Color textSecondary = Color(0xFF4A5D6E);
  static const Color textTertiary = Color(0xFF7A8A9A);
  static const Color textDisabled = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFF1A1A1A);

  // ── Status Colors (modern, vibrant) ──
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFCCFBF1);
  static const Color successDark = Color(0xFF047857);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color warningDark = Color(0xFFB45309);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color errorDark = Color(0xFFB91C1C);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color infoDark = Color(0xFF1D4ED8);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleLight = Color(0xFFEDE9FE);
  static const Color rose = Color(0xFFF43F5E);
  static const Color roseLight = Color(0xFFFFE4E6);

  // ── Sidebar Accents ──
  static const Color sidebarDivider = Color(0x1AFFFFFF);
  static const Color sidebarHover = Color(0x14FFFFFF);
  static const Color sidebarActiveGold = Color(0x1AD4AF37);

  // ── Dark Mode Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFD4AF37), Color(0xFFE8C84A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient primaryDarkGradient = LinearGradient(
    colors: [Color(0xFFB8962E), Color(0xFFD4AF37)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF2DD4BF), Color(0xFF14B8A6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient errorGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFFF87171)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient infoGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient roseGradient = LinearGradient(
    colors: [Color(0xFFF43F5E), Color(0xFFFB7185)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Luxury dark surface gradient (subtle shimmer)
  static const LinearGradient surfaceDarkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0B1323),
      Color(0xFF080E1A),
      Color(0xFF060B14),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Get status color for repair status strings
  static Color forStatus(String status) {
    switch (status) {
      case 'pending':
        return warning;
      case 'in_progress':
        return info;
      case 'repaired':
        return success;
      case 'delivered':
        return textTertiary;
      case 'rejected':
        return error;
      default:
        return textSecondary;
    }
  }

  /// Get background tint for status (dark mode aware)
  static Color forStatusBg(String status, {bool isDark = true}) {
    if (isDark) {
      switch (status) {
        case 'pending':
          return const Color(0x33F59E0B);
        case 'in_progress':
          return const Color(0x333B82F6);
        case 'repaired':
          return const Color(0x3310B981);
        case 'delivered':
          return const Color(0x1AFFFFFF);
        case 'rejected':
          return const Color(0x33EF4444);
        default:
          return const Color(0x0AFFFFFF);
      }
    }
    switch (status) {
      case 'pending':
        return warningLight;
      case 'in_progress':
        return infoLight;
      case 'repaired':
        return successLight;
      case 'delivered':
        return Colors.grey[100]!;
      case 'rejected':
        return errorLight;
      default:
        return Colors.grey[50]!;
    }
  }

  /// Get gradient for status
  static LinearGradient forStatusGradient(String status) {
    switch (status) {
      case 'pending':
        return warningGradient;
      case 'in_progress':
        return infoGradient;
      case 'repaired':
        return successGradient;
      case 'delivered':
        return tealGradient;
      case 'rejected':
        return errorGradient;
      default:
        return primaryGradient;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 🔵 BORDER RADIUS
// ═════════════════════════════════════════════════════════════════════════════
class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double full = 999;

  static BorderRadius get xsBr => BorderRadius.circular(xs);
  static BorderRadius get smBr => BorderRadius.circular(sm);
  static BorderRadius get mdBr => BorderRadius.circular(md);
  static BorderRadius get lgBr => BorderRadius.circular(lg);
  static BorderRadius get xlBr => BorderRadius.circular(xl);
  static BorderRadius get xxlBr => BorderRadius.circular(xxl);
}

// ═════════════════════════════════════════════════════════════════════════════
// 🌓 SHADOWS — Rich, layered shadows with color
// ═════════════════════════════════════════════════════════════════════════════
class AppShadows {
  /// Subtle shadow for small elements
  static List<BoxShadow> get sm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 1),
        ),
      ];

  /// Medium shadow for cards
  static List<BoxShadow> get md => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ];

  /// Large shadow for elevated elements
  static List<BoxShadow> get lg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 48,
          offset: const Offset(0, 12),
        ),
      ];

  /// Extra large shadow for dialogs
  static List<BoxShadow> get xl => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 40,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 60,
          offset: const Offset(0, 20),
        ),
      ];

  /// Gold glow for primary elements
  static List<BoxShadow> get goldGlow => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.25),
          blurRadius: 20,
          offset: const Offset(0, 0),
        ),
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.1),
          blurRadius: 40,
          offset: const Offset(0, 0),
        ),
      ];

  /// Teal glow for accent elements
  static List<BoxShadow> get tealGlow => [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.25),
          blurRadius: 20,
          offset: const Offset(0, 0),
        ),
      ];

  /// Soft outer glow for cards in dark mode
  static List<BoxShadow> get subtleGlow => [
        BoxShadow(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.06),
          blurRadius: 30,
          offset: const Offset(0, 0),
        ),
      ];

  /// Inner shadow for pressed states
  static List<BoxShadow> get inner => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 4,
          offset: const Offset(0, 1),
          blurStyle: BlurStyle.inner,
        ),
      ];

  /// Colored shadow helper
  static List<BoxShadow> colored({
    required Color color,
    double alpha = 0.3,
    double blurRadius = 16,
    double offsetY = 4,
  }) {
    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: blurRadius,
        offset: Offset(0, offsetY),
      ),
    ];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ✍️ TEXT STYLES — Premium Typography
// ═════════════════════════════════════════════════════════════════════════════
class AppTextStyles {
  static const String _font = 'Cairo';
  static const double _goldLetterSpacing = 1.5;

  // ── Display ──
  static TextStyle get displayLarge => TextStyle(
        fontFamily: _font,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.2,
      );
  static TextStyle get displayMedium => TextStyle(
        fontFamily: _font,
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  // ── Titles ──
  static TextStyle get titleLarge => TextStyle(
        fontFamily: _font,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.3,
      );
  static TextStyle get titleMedium => TextStyle(
        fontFamily: _font,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );
  static TextStyle get titleSmall => TextStyle(
        fontFamily: _font,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  // ── Body ──
  static TextStyle get bodyLarge => TextStyle(
        fontFamily: _font,
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.5,
      );
  static TextStyle get bodyMedium => TextStyle(
        fontFamily: _font,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.5,
      );
  static TextStyle get bodySmall => TextStyle(
        fontFamily: _font,
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  // ── Labels ──
  static TextStyle get labelLarge => TextStyle(
        fontFamily: _font,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.2,
      );
  static TextStyle get labelMedium => TextStyle(
        fontFamily: _font,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        height: 1.2,
      );
  static TextStyle get labelSmall => TextStyle(
        fontFamily: _font,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textTertiary,
        height: 1.2,
      );

  // ── Gold / Premium ──
  static TextStyle get gold => TextStyle(
        fontFamily: _font,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: _goldLetterSpacing,
      );
  static TextStyle get goldLarge => TextStyle(
        fontFamily: _font,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: _goldLetterSpacing,
      );
  static TextStyle get goldDisplay => TextStyle(
        fontFamily: _font,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: _goldLetterSpacing * 2,
      );

  // ── Teal Accent ──
  static TextStyle get teal => TextStyle(
        fontFamily: _font,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppColors.accent,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 🏗️ DECORATIONS — Reusable box decorations
// ═════════════════════════════════════════════════════════════════════════════
class AppDecorations {
  /// Standard card decoration with subtle border
  static BoxDecoration card(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.cardDark : AppColors.cardLight,
      borderRadius: AppRadius.mdBr,
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
      ),
      boxShadow:
          isDark ? [...AppShadows.subtleGlow, ...AppShadows.sm] : AppShadows.sm,
    );
  }

  /// Elevated card with richer shadow
  static BoxDecoration cardElevated(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.cardDarkElevated : AppColors.cardLightElevated,
      borderRadius: AppRadius.lgBr,
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
      ),
      boxShadow:
          isDark ? [...AppShadows.subtleGlow, ...AppShadows.md] : AppShadows.md,
    );
  }

  /// Premium glassmorphism effect for dialogs/modals
  static BoxDecoration glass(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: AppRadius.xlBr,
      gradient: LinearGradient(
        colors: isDark
            ? [
                const Color(0xFF162338).withValues(alpha: 0.95),
                const Color(0xFF111C2E).withValues(alpha: 0.85),
              ]
            : [
                Colors.white.withValues(alpha: 0.98),
                Colors.white.withValues(alpha: 0.9),
              ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.8),
        width: 1.5,
      ),
      boxShadow:
          isDark ? [...AppShadows.xl, ...AppShadows.subtleGlow] : AppShadows.xl,
    );
  }

  /// Gradient background for stat cards with rich shadow
  static BoxDecoration gradientCard({
    required LinearGradient gradient,
    double radius = AppRadius.lg,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: gradient,
      boxShadow: [
        BoxShadow(
          color: gradient.colors.first.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: gradient.colors.last.withValues(alpha: 0.15),
          blurRadius: 35,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  /// Gradient with subtle border (premium look)
  static BoxDecoration gradientCardBordered({
    required LinearGradient gradient,
    double radius = AppRadius.lg,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: gradient,
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.15),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: gradient.colors.first.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Input field decoration
  static BoxDecoration input(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.cardDarkElevated : AppColors.cardLight,
      borderRadius: AppRadius.smBr,
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08),
      ),
    );
  }

  /// Focused input decoration with gold border
  static BoxDecoration inputFocused(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.cardDarkElevated : AppColors.cardLight,
      borderRadius: AppRadius.smBr,
      border: Border.all(
        color: AppColors.primary,
        width: 1.5,
      ),
      boxShadow: AppShadows.goldGlow,
    );
  }

  /// Sidebar item decoration
  static BoxDecoration sidebarItem({
    required bool isSelected,
    required bool isDark,
  }) {
    return BoxDecoration(
      color: isSelected
          ? (isDark
              ? AppColors.sidebarActiveGold
              : AppColors.primary.withValues(alpha: 0.1))
          : Colors.transparent,
      borderRadius: AppRadius.mdBr,
      border: isSelected
          ? Border.all(
              color: (isDark ? AppColors.primary : AppColors.primary)
                  .withValues(alpha: isDark ? 0.4 : 0.3),
              width: 1,
            )
          : null,
    );
  }

  /// Shimmer loading decoration
  static BoxDecoration shimmer({bool isDark = true}) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1A2A3A) : const Color(0xFFE2E8F0),
      borderRadius: AppRadius.smBr,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 🌐 CONTEXT EXTENSIONS — Convenience getters
// ═════════════════════════════════════════════════════════════════════════════
extension AppThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get primaryColor => AppColors.primary;
  Color get accentColor => AppColors.accent;
  Color get cardColor => isDark ? AppColors.cardDark : AppColors.cardLight;
  Color get cardElevatedColor =>
      isDark ? AppColors.cardDarkElevated : AppColors.cardLightElevated;
  Color get surfaceColor =>
      isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
  Color get surfaceAltColor =>
      isDark ? AppColors.surfaceDarkAlt : AppColors.surfaceLightAlt;
  Color get textColor => isDark ? Colors.white : AppColors.textPrimary;
  Color get textMutedColor => isDark ? Colors.white70 : AppColors.textSecondary;
  Color get textTertiaryColor =>
      isDark ? Colors.white38 : AppColors.textTertiary;
  Color get borderColor => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);
  Color get dividerColor => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.06);

  /// Shorthand for Theme.of(this).textTheme
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Get a themed status background color
  Color statusBg(String status) =>
      AppColors.forStatusBg(status, isDark: isDark);
}
