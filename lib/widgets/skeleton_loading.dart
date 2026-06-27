/// ─────────────────────────────────────────────────────────────────────────────
/// ⏳ SkeletonLoading - تأثير الشحن المتدرج (Shimmer Effect)
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A shimmer loading effect that shows a pulse animation
class ShimmerWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerWidget({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            gradient: LinearGradient(
              colors: [
                isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.1),
                isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
              ],
              stops: [0.0, _animation.value, 1.0],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        );
      },
    );
  }
}

/// Pre-built skeleton layouts for common use cases
class SkeletonLoading {
  /// Skeleton for a stat card
  static Widget statCard(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerWidget(width: 40, height: 40, borderRadius: 10),
          const SizedBox(height: 16),
          const ShimmerWidget(width: 100, height: 28),
          const SizedBox(height: 6),
          const ShimmerWidget(width: 80, height: 14),
        ],
      ),
    );
  }

  /// Skeleton for a list tile
  static Widget listTile(BuildContext context) {
    return Padding(
      padding: AppSpacing.listTilePadding,
      child: Row(
        children: [
          const ShimmerWidget(width: 40, height: 40, borderRadius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerWidget(width: 180, height: 14),
                const SizedBox(height: 6),
                const ShimmerWidget(width: 120, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Skeleton for a table row
  static Widget tableRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(
          5,
          (index) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ShimmerWidget(
                width: double.infinity,
                height: 14,
                borderRadius: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Full page skeleton with multiple stat cards + list
  static Widget dashboardPage(BuildContext context) {
    return SingleChildScrollView(
      padding: AppSpacing.paddingMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4 stat cards in a grid
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: List.generate(4, (_) => statCard(context)),
          ),
          const SizedBox(height: 24),
          // Section header
          const ShimmerWidget(width: 200, height: 20),
          const SizedBox(height: 12),
          // List items
          ...List.generate(
              6,
              (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: listTile(context),
                  )),
        ],
      ),
    );
  }
}
