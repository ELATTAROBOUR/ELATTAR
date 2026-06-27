// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Charts Premium — fl_chart based widgets with enhanced visuals
//  • SalesBarChart           → Daily sales with animated gradient bars
//  • RepairStatusPieChart    → Interactive donut chart with rich legend
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../main.dart';

/// ──────────────────────────────────────────────────────────────────
///  SALES BAR CHART — Premium animated bar chart
/// ──────────────────────────────────────────────────────────────────
class SalesBarChart extends StatefulWidget {
  final Map<String, double> dailySales;
  final Color primaryGold;

  const SalesBarChart({
    super.key,
    required this.dailySales,
    this.primaryGold = AppColors.primary,
  });

  @override
  State<SalesBarChart> createState() => _SalesBarChartState();
}

class _SalesBarChartState extends State<SalesBarChart> {
  late List<String> _last7Days;
  double _maxY = 100;

  @override
  void initState() {
    super.initState();
    _calculateData();
  }

  @override
  void didUpdateWidget(SalesBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dailySales != widget.dailySales) {
      _calculateData();
    }
  }

  void _calculateData() {
    final now = DateTime.now();
    _last7Days = List.generate(7, (i) {
      final d = DateTime(now.year, now.month, now.day - (6 - i));
      return DateFormat('yyyy-MM-dd').format(d);
    });
    _maxY = widget.dailySales.values
        .fold<double>(0.0, (max, v) => v > max ? v : max);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);

    final total = widget.dailySales.values.fold<double>(0.0, (a, b) => a + b);

    return Container(
      decoration: AppDecorations.cardElevated(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المبيعات اليومية',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'الإجمالي: ${total.toStringAsFixed(0)} ج.م',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _maxY > 0 ? _maxY * 1.25 : 100,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipRoundedRadius: 8,
                    tooltipPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    tooltipBorder: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final day = _last7Days[groupIndex];
                      return BarTooltipItem(
                        '${DateFormat('EEEE', 'ar').format(DateTime.parse(day))}\n${rod.toY.toStringAsFixed(0)} ج.م',
                        TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _last7Days.length) {
                          return const SizedBox();
                        }
                        final day = DateTime.parse(_last7Days[idx]);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            DateFormat('E', 'ar').format(day),
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 11,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}',
                          style: TextStyle(
                            color: textMuted.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _maxY > 0 ? _maxY / 4 : 25,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _last7Days.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final day = entry.value;
                  final amount = widget.dailySales[day] ?? 0.0;
                  final hasValue = amount > 0;
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: hasValue ? amount : 0.5,
                        color:
                            hasValue ? widget.primaryGold : Colors.transparent,
                        width: 22,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        gradient: hasValue
                            ? LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  widget.primaryGold.withValues(alpha: 0.8),
                                  widget.primaryGold,
                                ],
                              )
                            : null,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────
///  REPAIR STATUS PIE CHART — Interactive donut with rich info
/// ──────────────────────────────────────────────────────────────────
class RepairStatusPieChart extends StatefulWidget {
  final Map<String, int> statusCounts;
  final Color primaryGold;

  const RepairStatusPieChart({
    super.key,
    required this.statusCounts,
    this.primaryGold = AppColors.primary,
  });

  @override
  State<RepairStatusPieChart> createState() => _RepairStatusPieChartState();
}

class _RepairStatusPieChartState extends State<RepairStatusPieChart> {
  int _touchedIndex = -1;

  static const Map<String, Color> _statusColors = {
    'pending': Color(0xFFFF9800),
    'in_progress': Color(0xFF2196F3),
    'repaired': Color(0xFF4CAF50),
    'delivered': Color(0xFF9E9E9E),
    'rejected': Color(0xFFF44336),
  };

  static const Map<String, String> _statusArabic = {
    'pending': 'انتظار',
    'in_progress': 'قيد الإصلاح',
    'repaired': 'جاهز للتسليم',
    'delivered': 'تم التسليم',
    'rejected': 'مرفوض',
  };

  static const Map<String, IconData> _statusIcons = {
    'pending': Icons.schedule_rounded,
    'in_progress': Icons.engineering_rounded,
    'repaired': Icons.check_circle_rounded,
    'delivered': Icons.assignment_turned_in_rounded,
    'rejected': Icons.cancel_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);

    final total = widget.statusCounts.values.fold<int>(0, (a, b) => a + b);

    return Container(
      decoration: AppDecorations.cardElevated(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حالات الصيانة',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'الإجمالي: $total تذكرة',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.pie_chart_rounded,
                  color: AppColors.accent,
                  size: 24,
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 40,
                        pieTouchData: PieTouchData(
                          touchCallback:
                              (FlTouchEvent event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex = pieTouchResponse
                                  .touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        sections: _buildSections(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Premium Legend
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.statusCounts.entries
                          .toList()
                          .asMap()
                          .entries
                          .map((entry) {
                        final idx = entry.key;
                        final statusEntry = entry.value;
                        final status = statusEntry.key;
                        final count = statusEntry.value;
                        final color = _statusColors[status] ?? Colors.grey;
                        final percent = total > 0 ? (count / total * 100) : 0.0;
                        final isActive = _touchedIndex == idx;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive
                                ? color.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  boxShadow: isActive
                                      ? [
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.5),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_statusArabic[status] ?? status}',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 12,
                                    fontFamily: 'Cairo',
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${percent.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: isActive ? color : textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 50),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_rounded,
                        size: 48, color: textMuted.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text(
                      'لا توجد تذاكر صيانة بعد 📋',
                      style: TextStyle(
                          color: textMuted, fontSize: 15, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    final total = widget.statusCounts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return [];

    return widget.statusCounts.entries.toList().asMap().entries.map((entry) {
      final idx = entry.key;
      final statusEntry = entry.value;
      final status = statusEntry.key;
      final count = statusEntry.value;
      final color = _statusColors[status] ?? Colors.grey;
      final percent = (count / total) * 100;
      final isTouched = idx == _touchedIndex;
      final radius = isTouched ? 50.0 : 42.0;
      final fontSize = isTouched ? 16.0 : 14.0;

      return PieChartSectionData(
        value: percent,
        color: color,
        radius: radius,
        title: '${count}',
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: 'Cairo',
        ),
        badgeWidget: isTouched
            ? Icon(
                _statusIcons[status] ?? Icons.circle,
                color: Colors.white,
                size: 16,
              )
            : null,
        badgePositionPercentageOffset: 1.3,
      );
    }).toList();
  }
}
