// ignore_for_file: avoid_print

import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  final content = file.readAsStringSync();

  final startMarker = 'class MainScreen extends StatefulWidget';
  final endMarker = '// ==================== TicketCard ====================';

  final startIndex = content.indexOf(startMarker);
  final endIndex = content.indexOf(endMarker);

  if (startIndex == -1 || endIndex == -1) {
    print('Error: Markers not found. start: $startIndex, end: $endIndex');
    return;
  }

  final newMainScreenCode = '''class MainScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const MainScreen({super.key, this.onLogout});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _views = [
    const DashboardOverviewView(),
    const RepairsView(),
    const AccessoriesView(),
    const DevicesView(),
    const InventoryView(),
    const GoodsReceiptView(),
    const InventoryTransferView(),
    const DeferredPaymentsView(),
    const SuppliersView(),
  ];

  final List<Map<String, dynamic>> _menuItems = [
    {
      'title': 'لوحة التحكم الإجمالية',
      'icon': Icons.grid_view_rounded,
    },
    {
      'title': '🔧 الصيانة والإصلاحات',
      'icon': Icons.build_circle_rounded,
    },
    {
      'title': '🎧 إدارة الاكسسوارات',
      'icon': Icons.headset_rounded,
    },
    {
      'title': '📱 إدارة الأجهزة',
      'icon': Icons.phone_iphone_rounded,
    },
    {
      'title': '📦 المخزن والجرد',
      'icon': Icons.inventory_rounded,
    },
    {
      'title': '📥 استلام بضائع (الموردين)',
      'icon': Icons.playlist_add_check_rounded,
    },
    {
      'title': '🔄 تحويلات المخازن',
      'icon': Icons.swap_horizontal_circle_rounded,
    },
    {
      'title': '💳 حسابات العملاء الآجلة',
      'icon': Icons.account_balance_wallet_rounded,
    },
    {
      'title': '🤝 حسابات الموردين',
      'icon': Icons.people_rounded,
    },
  ];

  void _showPrinterSettings() {
    showDialog(
      context: context,
      builder: (context) => _PrinterSettingsDialog(),
    );
  }

  void _toggleTheme() async {
    final current = themeNotifier.value;
    final newMode = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    themeNotifier.value = newMode;
    await ThemeSettingsService.save(newMode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textColor = AppTheme.text(context);
    final sidebarBg = isDark ? const Color(0xFF16222F) : const Color(0xFFEAF0F6);
    final activeBg = isDark ? const Color(0xFF1E2F41) : Colors.white;
    final primaryGold = const Color(0xFFD4AF37);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        body: Row(
          children: [
            // Sidebar Navigation (Right Aligned)
            Container(
              width: 280,
              color: sidebarBg,
              child: Column(
                children: [
                  // App Branding / Header
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: DecorationImage(
                              image: AssetImage(
                                isDark
                                    ? 'assets/image/logod.jpg'
                                    : 'assets/image/logow.jpg',
                              ),
                              fit: BoxFit.cover,
                            ),
                            boxShadow: isDark
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'DESIGNED',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryGold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'BELALZAGHL0L',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryGold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5, color: Colors.grey),
                  const SizedBox(height: 16),

                  // Menu Items
                  Expanded(
                    child: ListView.builder(
                      itemCount: _menuItems.length,
                      itemBuilder: (context, index) {
                        final item = _menuItems[index];
                        final isSelected = _selectedIndex == index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: isSelected ? activeBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected
                                    ? Border.all(color: primaryGold.withValues(alpha: 0.5), width: 1)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'],
                                    color: isSelected ? primaryGold : textColor.withValues(alpha: 0.7),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      item['title'],
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? primaryGold : textColor,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Bottom Settings Bar
                  const Divider(height: 1, thickness: 0.5, color: Colors.grey),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Toggle Theme
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: primaryGold,
                            size: 20,
                          ),
                          title: Text(
                            isDark ? 'الوضع المضيء' : 'الوضع الداكن',
                            style: TextStyle(color: textColor, fontSize: 14, fontFamily: 'Cairo'),
                          ),
                          onTap: _toggleTheme,
                        ),
                        // Printer Settings
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.print_rounded,
                            color: textColor.withValues(alpha: 0.7),
                            size: 20,
                          ),
                          title: Text(
                            'إعدادات الطابعة',
                            style: TextStyle(color: textColor, fontSize: 14, fontFamily: 'Cairo'),
                          ),
                          onTap: _showPrinterSettings,
                        ),
                        // Logout
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.logout_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          title: const Text(
                            'تسجيل الخروج',
                            style: TextStyle(color: Colors.redAccent, fontSize: 14, fontFamily: 'Cairo'),
                          ),
                          onTap: widget.onLogout,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 0.5, color: Colors.grey),

            // Main View Area (Left Aligned)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey<int>(_selectedIndex),
                  child: _views[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

''';

  final newContent = content.substring(0, startIndex) +
      newMainScreenCode +
      content.substring(endIndex);
  file.writeAsStringSync(newContent, flush: true);
  print('✅ Successfully replaced MainScreen in lib/main.dart');
}
