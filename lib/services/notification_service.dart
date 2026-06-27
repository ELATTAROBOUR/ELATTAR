// ─────────────────────────────────────────────────────────────────────────────
// Notification Service
//  • Low stock alerts
//  • Upcoming delivery date reminders
//  • Overdue payment reminders (future)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../database_helper.dart';

class DashboardAlert {
  final String type; // 'low_stock', 'delivery_soon', 'overdue'
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final int? navigateToIndex;

  DashboardAlert({
    required this.type,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.navigateToIndex,
  });
}

class NotificationService {
  /// Loads all dashboard alerts based on current data
  static Future<List<DashboardAlert>> loadAlerts() async {
    final alerts = <DashboardAlert>[];

    try {
      // ── 1. Low Stock Alerts ──────────────────────────────────────
      final accessories = await DatabaseHelper.loadAccessories();
      final devices = await DatabaseHelper.loadDevices();
      final spareParts = await DatabaseHelper.loadSpareParts();

      int lowStockCount = 0;
      final lowStockDetails = <String>[];

      for (var item in accessories) {
        if (item.quantity < 3) {
          lowStockCount++;
          if (lowStockDetails.length < 3) {
            lowStockDetails.add('${item.name} (متبقي ${item.quantity})');
          }
        }
      }
      for (var item in devices) {
        if (item.quantity < 3) {
          lowStockCount++;
          if (lowStockDetails.length < 3) {
            lowStockDetails.add('${item.model} (متبقي ${item.quantity})');
          }
        }
      }
      for (var item in spareParts) {
        if (item.quantity < 3) {
          lowStockCount++;
          if (lowStockDetails.length < 3) {
            lowStockDetails.add('قطعة: ${item.name} (متبقي ${item.quantity})');
          }
        }
      }

      if (lowStockCount > 0) {
        alerts.add(DashboardAlert(
          type: 'low_stock',
          title: '⚠️ مخزون منخفض',
          message: lowStockCount <= 3
              ? lowStockDetails.join(' • ')
              : '${lowStockDetails.take(3).join(' • ')} • و${lowStockCount - 3} أخرى',
          icon: Icons.inventory_2_rounded,
          color: const Color(0xFFFF9800),
          actionLabel: 'عرض المخزون',
          navigateToIndex: 8,
        ));
      }

      // ── 2. Upcoming Delivery Reminders ──────────────────────────
      final tickets = await DatabaseHelper.loadTickets();
      final now = DateTime.now();
      final in3Days = now.add(const Duration(days: 3));

      int upcomingDeliveries = 0;
      final deliveryDetails = <String>[];

      for (var ticket in tickets) {
        if (ticket.status == 'pending' || ticket.status == 'in_progress') {
          if (ticket.expectedDelivery != null &&
              ticket.expectedDelivery!.isNotEmpty) {
            try {
              final expected = DateTime.parse(ticket.expectedDelivery!);
              if (expected.isAfter(now.subtract(const Duration(days: 1))) &&
                  expected.isBefore(in3Days)) {
                upcomingDeliveries++;
                if (deliveryDetails.length < 3) {
                  final daysLeft = expected.difference(now).inDays;
                  final dayStr = daysLeft == 0
                      ? 'اليوم'
                      : daysLeft == 1
                          ? 'غداً'
                          : 'بعد $daysLeft أيام';
                  deliveryDetails.add(
                      '${ticket.customerName} - ${ticket.deviceModel} ($dayStr)');
                }
              }
            } catch (_) {}
          }
        }
      }

      if (upcomingDeliveries > 0) {
        alerts.add(DashboardAlert(
          type: 'delivery_soon',
          title: '📦 مواعيد تسليم وشيكة',
          message: upcomingDeliveries <= 3
              ? deliveryDetails.join(' • ')
              : '${deliveryDetails.take(3).join(' • ')} • و${upcomingDeliveries - 3} أخرى',
          icon: Icons.event_available_rounded,
          color: const Color(0xFF2196F3),
          actionLabel: 'عرض الصيانة',
          navigateToIndex: 3,
        ));
      }

      // ── 3. Overdue Payments Reminder ────────────────────────────
      final deferredPayments = await DatabaseHelper.loadDeferredPayments();
      int overdueCount = 0;
      final overdueDetails = <String>[];

      for (var payment in deferredPayments) {
        if (payment.remainingAmount > 0 &&
            payment.dueDate != null &&
            payment.dueDate!.isNotEmpty) {
          try {
            final due = DateTime.parse(payment.dueDate!);
            if (due.isBefore(now) && payment.remainingAmount > 0) {
              overdueCount++;
              if (overdueDetails.length < 3) {
                overdueDetails.add(
                    '${payment.customerName} - ${payment.remainingAmount.toStringAsFixed(0)} ج.م');
              }
            }
          } catch (_) {}
        }
      }

      if (overdueCount > 0) {
        alerts.add(DashboardAlert(
          type: 'overdue',
          title: '💰 دفعات متأخرة',
          message: overdueCount <= 3
              ? overdueDetails.join(' • ')
              : '${overdueDetails.take(3).join(' • ')} • و${overdueCount - 3} أخرى',
          icon: Icons.payment_rounded,
          color: const Color(0xFFF44336),
          actionLabel: 'عرض الديون',
          navigateToIndex: 5,
        ));
      }
    } catch (e) {
      debugPrint('NotificationService.loadAlerts error: $e');
    }

    return alerts;
  }
}
