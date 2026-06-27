/// ─────────────────────────────────────────────────────────────────────────────
/// 🔔 CustomToast - إشعارات Toast أنيقة
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum ToastType { success, error, warning, info }

class CustomToast {
  /// Show a beautiful toast notification
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
  }) {
    _showToast(context,
        message: message, type: type, duration: duration, icon: icon);
  }

  static void _showToast(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
  }) {
    // Dismiss any existing toasts
    ScaffoldMessenger.of(context).clearSnackBars();

    // Determine colors and icon
    Color bgColor;
    Color iconColor;
    IconData toastIcon;

    switch (type) {
      case ToastType.success:
        bgColor = AppColors.success;
        iconColor = Colors.white;
        toastIcon = Icons.check_circle_rounded;
        break;
      case ToastType.error:
        bgColor = AppColors.error;
        iconColor = Colors.white;
        toastIcon = Icons.error_rounded;
        break;
      case ToastType.warning:
        bgColor = AppColors.warning;
        iconColor = Colors.white;
        toastIcon = Icons.warning_rounded;
        break;
      case ToastType.info:
        bgColor = AppColors.info;
        iconColor = Colors.white;
        toastIcon = Icons.info_rounded;
        break;
    }

    final snackBar = SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? toastIcon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: duration,
      elevation: 6,
      dismissDirection: DismissDirection.horizontal,
      animation: CurvedAnimation(
        parent: kAlwaysCompleteAnimation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
