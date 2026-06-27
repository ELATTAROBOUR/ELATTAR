/// ─────────────────────────────────────────────────────────────────────────────
/// 🪟 GlassDialog - نافذة منبثقة زجاجية فاخرة (Glassmorphism Premium)
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shows a beautiful glassmorphism-styled dialog with animations
class GlassDialog {
  /// Display a glassmorphism dialog with optional title, content, and actions.
  ///
  /// [context] - Build context
  /// [icon] - Optional icon displayed at top
  /// [title] - Dialog title
  /// [content] - Dialog body widget
  /// [actions] - List of action widgets at bottom
  /// [width] - Dialog width (default: 480)
  /// [height] - Dialog height (default: adaptive)
  static Future<T?> show<T>({
    required BuildContext context,
    IconData? icon,
    required String title,
    required Widget content,
    List<Widget>? actions,
    double width = 480,
    double? height,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierBuilder: (context) => AnimatedBarrier(
        color: TweenSequence<Color>([
          TweenSequenceItem(
            tween: ConstantTween<Color>(Colors.black54),
            weight: 1,
          ),
        ]).animate(const AlwaysStoppedAnimation(0)),
      ),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.9 + (0.1 * value),
                  child: child,
                ),
              );
            },
            child: Center(
              child: Container(
                width: width,
                constraints: BoxConstraints(
                  maxHeight:
                      height ?? MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: AppDecorations.glass(context),
                child: ClipRRect(
                  borderRadius: AppRadius.xlBr,
                  child: BackdropFilter(
                    filter: isDark ? null : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Optional icon header with glow
                        if (icon != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 28, bottom: 4),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: isDark ? AppShadows.goldGlow : null,
                              ),
                              child: Icon(
                                icon,
                                size: 36,
                                color: AppColors.primary,
                              ),
                            ),
                          ),

                        // Title
                        if (title.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              top: icon != null ? 12 : 28,
                              left: 24,
                              right: 24,
                              bottom: 8,
                            ),
                            child: Text(
                              title,
                              style: AppTextStyles.titleLarge.copyWith(
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        // Content
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                            child: content,
                          ),
                        ),

                        // Divider
                        if (actions != null && actions.isNotEmpty)
                          Container(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),

                        // Actions
                        if (actions != null && actions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: actions,
                            ),
                          ),

                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Convenience: show a confirmation dialog
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'إلغاء',
    Color? confirmColor,
    IconData? icon,
  }) {
    return show<bool>(
      context: context,
      icon: icon ?? Icons.help_outline_rounded,
      title: title,
      content: Text(
        message,
        style: AppTextStyles.bodyLarge.copyWith(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : AppColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey[600],
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(cancelLabel, style: const TextStyle(fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor ?? AppColors.primary,
            foregroundColor:
                confirmColor != null ? Colors.white : AppColors.textOnPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
            shadowColor:
                (confirmColor ?? AppColors.primary).withValues(alpha: 0.3),
          ),
          child: Text(confirmLabel,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
