/// ─────────────────────────────────────────────────────────────────────────────
/// 📭 AppEmptyState - صفحة فارغة جميلة مع أيقونة ورسالة
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconSize = 80,
  });

  /// Predefined empty states
  factory AppEmptyState.noData({String? message, VoidCallback? onAdd}) =>
      AppEmptyState(
        icon: Icons.inbox_rounded,
        title: message ?? 'لا توجد بيانات',
        subtitle: 'لم يتم إضافة أي عناصر بعد',
        actionLabel: onAdd != null ? 'إضافة جديد' : null,
        onAction: onAdd,
      );

  factory AppEmptyState.noResults({String? query}) => AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'لا توجد نتائج',
        subtitle: query != null
            ? 'لا توجد نتائج لـ "$query"'
            : 'حاول بكلمة بحث مختلفة',
      );

  factory AppEmptyState.noSales({VoidCallback? onAddSale}) => AppEmptyState(
        icon: Icons.shopping_cart_rounded,
        title: 'لا توجد مبيعات',
        subtitle: 'لم يتم تسجيل أي عملية بيع بعد',
        actionLabel: onAddSale != null ? 'تسجيل عملية بيع' : null,
        onAction: onAddSale,
      );

  factory AppEmptyState.noTickets({VoidCallback? onAdd}) => AppEmptyState(
        icon: Icons.build_circle_rounded,
        title: 'لا توجد تذاكر صيانة',
        subtitle: 'لم يتم إضافة أي تذكرة صيانة بعد',
        actionLabel: onAdd != null ? 'إضافة تذكرة' : null,
        onAction: onAdd,
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with subtle background
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: context.isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              title,
              style: AppTextStyles.titleLarge.copyWith(
                color: context.textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Subtitle
            if (subtitle != null)
              Text(
                subtitle!,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: context.textMutedColor,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 24),
            // Action button
            if (actionLabel != null && onAction != null)
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
