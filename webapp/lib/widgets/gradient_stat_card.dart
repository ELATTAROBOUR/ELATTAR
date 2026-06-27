/// ─────────────────────────────────────────────────────────────────────────────
/// 💎 PremiumStatCard - بطاقة إحصائية متدرجة فاخرة مع تأثيرات حركية
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GradientStatCard extends StatefulWidget {
  final String title;
  final String value;
  final IconData icon;
  final LinearGradient gradient;
  final String? subtitle;
  final double valueFontSize;
  final VoidCallback? onTap;

  const GradientStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    this.subtitle,
    this.valueFontSize = 28,
    this.onTap,
  });

  /// Predefined card: Revenue/Sales (Gold)
  factory GradientStatCard.sales({
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      GradientStatCard(
        title: title,
        value: value,
        icon: Icons.trending_up_rounded,
        gradient: AppColors.primaryGradient,
        subtitle: subtitle,
        onTap: onTap,
      );

  /// Predefined card: Warning/Alert (Orange)
  factory GradientStatCard.warning({
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      GradientStatCard(
        title: title,
        value: value,
        icon: Icons.warning_amber_rounded,
        gradient: AppColors.warningGradient,
        subtitle: subtitle,
        onTap: onTap,
      );

  /// Predefined card: Error/Critical (Red)
  factory GradientStatCard.error({
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      GradientStatCard(
        title: title,
        value: value,
        icon: Icons.error_outline_rounded,
        gradient: AppColors.errorGradient,
        subtitle: subtitle,
        onTap: onTap,
      );

  /// Predefined card: Info/Count (Blue)
  factory GradientStatCard.info({
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      GradientStatCard(
        title: title,
        value: value,
        icon: Icons.info_outline_rounded,
        gradient: AppColors.infoGradient,
        subtitle: subtitle,
        onTap: onTap,
      );

  /// Predefined card: Success/Complete (Green)
  factory GradientStatCard.success({
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      GradientStatCard(
        title: title,
        value: value,
        icon: Icons.check_circle_outline_rounded,
        gradient: AppColors.successGradient,
        subtitle: subtitle,
        onTap: onTap,
      );

  /// Predefined card: Accent/Purple
  factory GradientStatCard.accent({
    required String title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      GradientStatCard(
        title: title,
        value: value,
        icon: Icons.auto_awesome_rounded,
        gradient: AppColors.purpleGradient,
        subtitle: subtitle,
        onTap: onTap,
      );

  @override
  State<GradientStatCard> createState() => _GradientStatCardState();
}

class _GradientStatCardState extends State<GradientStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - opacity)),
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor:
            widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          transform: _isHovered
              ? (Matrix4.identity()..translate(0.0, -4.0, 0.0))
              : Matrix4.identity(),
          decoration: AppDecorations.gradientCard(gradient: widget.gradient),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.lgBr,
            child: InkWell(
              borderRadius: AppRadius.lgBr,
              onTap: widget.onTap,
              splashColor: Colors.white.withValues(alpha: 0.1),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon with glass background
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _isHovered
                            ? Colors.white.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(widget.icon,
                          color: Colors.white, size: _isHovered ? 24 : 22),
                    ),
                    const Spacer(),
                    // Value with shimmer effect
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        widget.value,
                        style: TextStyle(
                          fontSize: widget.valueFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              color: Colors.white.withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Title
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    // Subtitle
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                    // Subtle glow line at bottom
                    Container(
                      height: 2,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
