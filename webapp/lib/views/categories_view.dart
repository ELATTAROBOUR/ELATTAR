// lib/views/categories_view.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';

class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Category> _accessoryCategories = [];
  List<Category> _sparePartCategories = [];
  List<Category> _deviceBrands = [];
  List<Category> _deviceConditions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      _accessoryCategories = await DatabaseHelper.loadCategories('accessory');
      _sparePartCategories = await DatabaseHelper.loadCategories('spare_part');
      _deviceBrands = await DatabaseHelper.loadCategories('device_brand');
      _deviceConditions = await DatabaseHelper.loadCategories('device_condition');
    } catch (e) {
      debugPrint('Error loading categories: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAddEditDialog({Category? category, required String type}) {
    final nameController = TextEditingController(text: category?.name);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final primaryGold = const Color(0xFFD4AF37);
          final textColor = AppTheme.text(context);

          String title = '';
          String label = 'اسم التصنيف *';
          if (category == null) {
            if (type == 'accessory') title = '➕ إضافة تصنيف إكسسوارات جديد';
            if (type == 'spare_part') title = '➕ إضافة تصنيف قطع غيار جديد';
            if (type == 'device_brand') {
              title = '➕ إضافة ماركة جديدة';
              label = 'اسم الماركة / البراند *';
            }
            if (type == 'device_condition') {
              title = '➕ إضافة حالة جهاز جديدة';
              label = 'حالة الجهاز *';
            }
          } else {
            if (type == 'accessory') title = '✏️ تعديل تصنيف إكسسوارات';
            if (type == 'spare_part') title = '✏️ تعديل تصنيف قطع غيار';
            if (type == 'device_brand') {
              title = '✏️ تعديل ماركة الجهاز';
              label = 'اسم الماركة / البراند *';
            }
            if (type == 'device_condition') {
              title = '✏️ تعديل حالة الجهاز';
              label = 'حالة الجهاز *';
            }
          }

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              title,
              style: TextStyle(color: primaryGold, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        labelText: label,
                        labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 16, fontFamily: 'Cairo')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                ),
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ يرجى إدخال الاسم')));
                    return;
                  }

                  final newCat = Category(
                    id: category?.id,
                    name: nameController.text.trim(),
                    type: type,
                  );

                  await DatabaseHelper.saveCategory(newCat);
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                },
                child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        title: const Text('⚠️ تأكيد الحذف', style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد من حذف "${category.name}"؟ قد يؤثر هذا على تصنيف وعرض المنتجات أو الأجهزة المرتبطة به.', style: TextStyle(color: AppTheme.text(context), fontSize: 16, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 16, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              if (category.id != null) {
                await DatabaseHelper.deleteCategory(category.id!);
              }
              if (context.mounted) Navigator.pop(context);
              _loadData();
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  String _getActiveType() {
    switch (_tabController.index) {
      case 0:
        return 'accessory';
      case 1:
        return 'spare_part';
      case 2:
        return 'device_brand';
      case 3:
        return 'device_condition';
      default:
        return 'accessory';
    }
  }

  String _getAddButtonLabel() {
    switch (_tabController.index) {
      case 0:
        return 'إضافة تصنيف إكسسوار';
      case 1:
        return 'إضافة تصنيف قطع غيار';
      case 2:
        return 'إضافة ماركة جهاز';
      case 3:
        return 'إضافة حالة جهاز';
      default:
        return 'إضافة تصنيف';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final primaryGold = const Color(0xFFD4AF37);
    final cardBg = AppTheme.cardBg(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '🗂️ إدارة تصنيفات المحل الشاملة',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إدارة تصنيفات الاكسسوارات، قطع الغيار، ماركات الأجهزة، وحالات الهواتف في مكان واحد.',
                    style: TextStyle(fontSize: 15, color: textMuted, fontFamily: 'Cairo'),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: () {
                  _showAddEditDialog(type: _getActiveType());
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                label: Text(
                  _getAddButtonLabel(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            Card(
              color: cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tabController,
                indicatorColor: primaryGold,
                labelColor: primaryGold,
                unselectedLabelColor: textMuted,
                labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                tabs: const [
                  Tab(icon: Icon(Icons.headset_rounded), text: 'تصنيفات الاكسسوارات'),
                  Tab(icon: Icon(Icons.settings_suggest_rounded), text: 'تصنيفات قطع الغيار'),
                  Tab(icon: Icon(Icons.phone_iphone_rounded), text: 'ماركات الأجهزة'),
                  Tab(icon: Icon(Icons.star_half_rounded), text: 'حالات الأجهزة'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCategoryTab(categories: _accessoryCategories, type: 'accessory'),
                        _buildCategoryTab(categories: _sparePartCategories, type: 'spare_part'),
                        _buildCategoryTab(categories: _deviceBrands, type: 'device_brand'),
                        _buildCategoryTab(categories: _deviceConditions, type: 'device_condition'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTab({required List<Category> categories, required String type}) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final primaryGold = const Color(0xFFD4AF37);
    final cardBg = AppTheme.cardBg(context);

    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: textMuted),
            const SizedBox(height: 16),
            Text(
              'لا توجد تصنيفات حالياً في هذا القسم',
              style: TextStyle(fontSize: 18, color: textMuted, fontFamily: 'Cairo'),
            ),
          ],
        ),
      );
    }

    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: DataTable(
          headingTextStyle: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: primaryGold, fontSize: 16),
          dataTextStyle: TextStyle(fontFamily: 'Cairo', color: textColor, fontSize: 15),
          columns: [
            const DataColumn(label: Text('المعرف')),
            DataColumn(label: Text(type == 'device_brand' ? 'اسم الماركة' : (type == 'device_condition' ? 'حالة الجهاز' : 'اسم التصنيف'))),
            const DataColumn(label: Text('خيارات')),
          ],
          rows: categories.map((cat) {
            return DataRow(cells: [
              DataCell(Text('#${cat.id ?? ""}')),
              DataCell(Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit, color: primaryGold, size: 20),
                      onPressed: () => _showAddEditDialog(category: cat, type: type),
                      tooltip: 'تعديل',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                      onPressed: () => _confirmDelete(cat),
                      tooltip: 'حذف',
                    ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
