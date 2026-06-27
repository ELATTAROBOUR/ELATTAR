// lib/views/dashboard_overview_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/gradient_stat_card.dart';
import '../widgets/skeleton_loading.dart';
import '../services/notification_service.dart';

class DashboardOverviewView extends StatefulWidget {
  final Function(int)? onNavigate;
  const DashboardOverviewView({super.key, this.onNavigate});

  @override
  State<DashboardOverviewView> createState() => _DashboardOverviewViewState();
}

class _DashboardOverviewViewState extends State<DashboardOverviewView> {
  bool _isLoading = true;
  int _activeRepairs = 0;
  int _accessoriesCount = 0;
  int _devicesCount = 0;
  double _customerDebts = 0.0;
  double _supplierDebts = 0.0;

  List<Ticket> _recentTickets = [];
  List<dynamic> _lowStockItems = []; // Accessories and Devices
  List<ModificationLog> _recentLogs = [];

  // ── Chart data ──
  Map<String, double> _dailySales = {};
  Map<String, int> _repairStatusCounts = {};

  // ── Alerts ──
  List<DashboardAlert> _alerts = [];
  bool _alertsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final tickets = await DatabaseHelper.loadTickets();
      final accessories = await DatabaseHelper.loadAccessories();
      final devices = await DatabaseHelper.loadDevices();
      final customerDeferred = await DatabaseHelper.loadDeferredPayments();
      final supplierDebts = await DatabaseHelper.loadSupplierDebts();

      // Active repairs: status is pending or in_progress
      _activeRepairs = tickets
          .where((t) => t.status == 'pending' || t.status == 'in_progress')
          .length;

      // Total items counts
      _accessoriesCount =
          accessories.fold(0, (sum, item) => sum + item.quantity);
      _devicesCount = devices.fold(0, (sum, item) => sum + item.quantity);

      // Debts totals
      _customerDebts =
          customerDeferred.fold(0.0, (sum, item) => sum + item.remainingAmount);
      _supplierDebts =
          supplierDebts.fold(0.0, (sum, item) => sum + item.remainingAmount);

      // Recent 5 tickets
      _recentTickets = tickets.take(5).toList();

      // Low stock warning items (quantity < 3)
      _lowStockItems = [];
      for (var item in accessories) {
        if (item.quantity < 3) {
          _lowStockItems.add(
              {'name': item.name, 'qty': item.quantity, 'type': 'إكسسوار'});
        }
      }
      for (var item in devices) {
        if (item.quantity < 3) {
          _lowStockItems.add({
            'name':
                '${item.model} (${item.condition == 'new' ? 'جديد' : 'مستعمل'})',
            'qty': item.quantity,
            'type': 'جهاز'
          });
        }
      }

      // Load recent modification logs
      _recentLogs = await DatabaseHelper.loadModificationLogs(limit: 5);

      // ── Load chart data ──
      // Daily sales grouped by date (last 7 days)
      final allSales = await DatabaseHelper.loadSales();
      final now = DateTime.now();
      final last7Days = List.generate(7, (i) {
        final d = DateTime(now.year, now.month, now.day - (6 - i));
        return DateFormat('yyyy-MM-dd').format(d);
      });
      _dailySales = {
        for (var day in last7Days) day: 0.0,
      };
      for (var sale in allSales) {
        final saleDate = DateFormat('yyyy-MM-dd').format(sale.saleDate);
        if (_dailySales.containsKey(saleDate)) {
          _dailySales[saleDate] =
              (_dailySales[saleDate] ?? 0.0) + sale.finalAmount;
        }
      }

      // Repair status counts
      _repairStatusCounts = {};
      for (var t in tickets) {
        _repairStatusCounts[t.status] =
            (_repairStatusCounts[t.status] ?? 0) + 1;
      }

      // ── Load alerts ──
      _alerts = await NotificationService.loadAlerts();
    } catch (e) {
      debugPrint('Error loading dashboard stats: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final isDark = AppTheme.isDark(context);

    if (_isLoading) {
      return SkeletonLoading.dashboardPage(context);
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppColors.primary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Premium Header ──
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(opacity: value, child: child);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: AppShadows.goldGlow,
                            ),
                            child: const Icon(
                              Icons.dashboard_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مرحباً بك في لوحة التحكم',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'نظرة عامة على حالة المحل والمبيعات والمخزون',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: textMuted,
                                    fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: InkWell(
                      onTap: _loadStats,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'تحديث',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Alerts Banner ──
            if (_alerts.isNotEmpty)
              _buildAlertsBanner(
                  context, AppColors.primary, textColor, textMuted, isDark),
            const SizedBox(height: 24),

            // ── Premium Stat Cards ──
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: [
                GradientStatCard.info(
                  title: 'أجهزة قيد الصيانة',
                  value: _activeRepairs.toString(),
                ),
                GradientStatCard.warning(
                  title: 'إجمالي الإكسسوارات',
                  value: _accessoriesCount.toString(),
                ),
                GradientStatCard.accent(
                  title: 'الأجهزة بالمخزن',
                  value: _devicesCount.toString(),
                ),
                GradientStatCard.sales(
                  title: 'ديون العملاء (آجل)',
                  value: '${_customerDebts.toStringAsFixed(0)} ج.م',
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Quick Actions Section ──
            Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'إجراءات سريعة',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              children: [
                QuickActionCard(
                  title: 'عملية بيع جديدة',
                  subtitle: 'بيع إكسسوار، جهاز، أو قطعة غيار',
                  icon: Icons.point_of_sale_rounded,
                  color: AppColors.success,
                  onTap: () {
                    if (widget.onNavigate != null) widget.onNavigate!(2);
                  },
                ),
                QuickActionCard(
                  title: 'الصيانة والتذاكر',
                  subtitle: 'تسجيل واستلام أجهزة صيانة',
                  icon: Icons.build_circle_rounded,
                  color: AppColors.info,
                  onTap: () {
                    if (widget.onNavigate != null) widget.onNavigate!(3);
                  },
                ),
                QuickActionCard(
                  title: 'جرد ومراقبة المخزن',
                  subtitle: 'متابعة الكميات وحالة المخزون',
                  icon: Icons.inventory_rounded,
                  color: AppColors.warning,
                  onTap: () {
                    if (widget.onNavigate != null) widget.onNavigate!(8);
                  },
                ),
                QuickActionCard(
                  title: 'استلام بضائع جديدة',
                  subtitle: 'إدخال فواتير الموردين للمخزن',
                  icon: Icons.playlist_add_check_rounded,
                  color: AppColors.purple,
                  onTap: () {
                    if (widget.onNavigate != null) widget.onNavigate!(9);
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Charts Section ──
            SizedBox(
              height: 360,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: SalesBarChart(
                      dailySales: _dailySales,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: RepairStatusPieChart(
                      statusCounts: _repairStatusCounts,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Recent Repairs Card (Premium)
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: AppDecorations.cardElevated(context),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.history_rounded,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'أحدث إيصالات الصيانة',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_recentTickets.length} إيصال',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.06)),
                        const SizedBox(height: 8),
                        if (_recentTickets.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inbox_rounded,
                                      size: 48, color: Colors.grey),
                                  SizedBox(height: 12),
                                  Text(
                                    'لا توجد عمليات صيانة حالياً',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 15,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recentTickets.length,
                            separatorBuilder: (context, index) => Container(
                                height: 1,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.black.withValues(alpha: 0.04)),
                            itemBuilder: (context, index) {
                              final ticket = _recentTickets[index];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.forStatus(ticket.status)
                                                .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        ticket.status == 'pending'
                                            ? Icons.schedule_rounded
                                            : ticket.status == 'in_progress'
                                                ? Icons.engineering_rounded
                                                : ticket.status == 'repaired'
                                                    ? Icons.check_circle_rounded
                                                    : Icons.devices_rounded,
                                        color:
                                            AppColors.forStatus(ticket.status),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${ticket.customerName} - ${ticket.deviceModel}',
                                            style: TextStyle(
                                                color: textColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                fontFamily: 'Cairo'),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${ticket.problem}',
                                            style: TextStyle(
                                                color: textMuted,
                                                fontSize: 12,
                                                fontFamily: 'Cairo'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.forStatus(ticket.status)
                                                .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: AppColors.forStatus(
                                                    ticket.status)
                                                .withValues(alpha: 0.4),
                                            width: 1),
                                      ),
                                      child: Text(
                                        _getStatusArabic(ticket.status),
                                        style: TextStyle(
                                          color: AppColors.forStatus(
                                              ticket.status),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                // Right Column
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      // Supplier Debts Card
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    AppColors.error.withValues(alpha: 0.08),
                                    AppColors.cardDark,
                                  ]
                                : [
                                    AppColors.error.withValues(alpha: 0.04),
                                    AppColors.cardLight,
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: AppRadius.mdBr,
                          border: Border.all(
                            color: isDark
                                ? AppColors.error.withValues(alpha: 0.15)
                                : AppColors.error.withValues(alpha: 0.1),
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.outbox_rounded,
                                  color: AppColors.error, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'مستحقات الموردين',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: textMuted,
                                        fontFamily: 'Cairo'),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_supplierDebts.toStringAsFixed(0)} ج.م',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.error,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Low Stock Warnings Card
                      Container(
                        decoration: AppDecorations.cardElevated(context),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                          Icons.warning_amber_rounded,
                                          color: AppColors.warning,
                                          size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'المخزون المنخفض',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_lowStockItems.length}',
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                                height: 1,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.06)),
                            const SizedBox(height: 8),
                            if (_lowStockItems.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    'كل المنتجات في حالة ممتازة ✅',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                        fontFamily: 'Cairo'),
                                  ),
                                ),
                              )
                            else
                              ...List.generate(
                                _lowStockItems.length > 5
                                    ? 5
                                    : _lowStockItems.length,
                                (index) {
                                  final alert = _lowStockItems[index];
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            alert['name'],
                                            style: TextStyle(
                                                color: textColor,
                                                fontWeight: FontWeight.w500,
                                                fontSize: 13,
                                                fontFamily: 'Cairo'),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.error
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'متبقي: ${alert['qty']}',
                                            style: const TextStyle(
                                                color: AppColors.error,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Latest Modifications Card
                      Container(
                        decoration: AppDecorations.cardElevated(context),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                          Icons.history_toggle_off_rounded,
                                          color: AppColors.accent,
                                          size: 20),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'آخر التعديلات',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                                height: 1,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.06)),
                            const SizedBox(height: 8),
                            if (_recentLogs.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    'لا توجد تعديلات مسجلة بعد 📝',
                                    style: TextStyle(
                                        color: textMuted, fontSize: 15),
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _recentLogs.length,
                                itemBuilder: (context, index) {
                                  final log = _recentLogs[index];

                                  // Determine icon and color based on actionType
                                  IconData iconData = Icons.edit_note_rounded;
                                  Color iconColor = AppColors.primary;
                                  if (log.actionType.contains('إضافة') ||
                                      log.actionType.contains('استلام')) {
                                    iconData = Icons.add_circle_outline_rounded;
                                    iconColor = Colors.greenAccent;
                                  } else if (log.actionType.contains('حذف')) {
                                    iconData = Icons.delete_outline_rounded;
                                    iconColor = Colors.redAccent;
                                  } else if (log.actionType.contains('بيع')) {
                                    iconData = Icons.point_of_sale_rounded;
                                    iconColor = Colors.blueAccent;
                                  } else if (log.actionType.contains('تحويل')) {
                                    iconData = Icons.swap_horiz_rounded;
                                    iconColor = Colors.orangeAccent;
                                  } else if (log.actionType.contains('سداد')) {
                                    iconData = Icons.payment_rounded;
                                    iconColor = Colors.tealAccent;
                                  }

                                  // Parse time
                                  String timeStr = '';
                                  try {
                                    final dt = DateTime.parse(log.actionDate);
                                    timeStr =
                                        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                  } catch (_) {}

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(iconData,
                                                color: iconColor, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${log.actionType} - ${log.itemType} (${log.itemName})',
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (timeStr.isNotEmpty)
                                              Text(
                                                timeStr,
                                                style: TextStyle(
                                                    color: textMuted,
                                                    fontSize: 12),
                                              ),
                                          ],
                                        ),
                                        if (log.details != null &&
                                            log.details!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 28.0),
                                            child: Text(
                                              log.details!,
                                              style: TextStyle(
                                                  color: textMuted,
                                                  fontSize: 13),
                                            ),
                                          ),
                                        ],
                                        if (index < _recentLogs.length - 1)
                                          const Divider(
                                              height: 16, thickness: 0.5),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsBanner(BuildContext context, Color primaryGold,
      Color textColor, Color textMuted, bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _alertsExpanded = !_alertsExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active_rounded,
                          color: AppColors.primary, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        '🔔 التنبيهات (${_alerts.length})',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        _alertsExpanded ? 'إخفاء' : 'عرض الكل',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      Icon(
                        _alertsExpanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._alerts
                  .take(_alertsExpanded ? _alerts.length : 2)
                  .map((alert) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: alert.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: alert.color.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(alert.icon, color: alert.color, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.title,
                                style: TextStyle(
                                  color: alert.color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                alert.message,
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (alert.actionLabel != null &&
                            alert.navigateToIndex != null)
                          TextButton(
                            onPressed: () {
                              if (widget.onNavigate != null) {
                                widget.onNavigate!(alert.navigateToIndex!);
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: alert.color,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              alert.actionLabel!,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              if (!_alertsExpanded && _alerts.length > 2)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Center(
                    child: Text(
                      'و${_alerts.length - 2} تنبيهات أخرى...',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusArabic(String status) {
    switch (status) {
      case 'pending':
        return 'انتظار';
      case 'in_progress':
        return 'قيد الإصلاح';
      case 'repaired':
        return 'جاهز للتسليم';
      case 'delivered':
        return 'تم التسليم';
      case 'rejected':
        return 'مرفوض';
      default:
        return status;
    }
  }
}

class QuickActionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<QuickActionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontFamily: 'Cairo',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: textMuted,
                        fontFamily: 'Cairo',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
