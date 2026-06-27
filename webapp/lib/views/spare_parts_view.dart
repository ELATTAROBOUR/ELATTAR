// lib/views/spare_parts_view.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';

class SparePartsView extends StatefulWidget {
  const SparePartsView({super.key});

  @override
  State<SparePartsView> createState() => _SparePartsViewState();
}

class _SparePartsViewState extends State<SparePartsView> {
  List<SparePart> _spareParts = [];
  List<SparePart> _filteredSpareParts = [];
  List<Category> _categories = [];
  String _searchQuery = '';
  int? _selectedCategoryFilter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      _spareParts = await DatabaseHelper.loadSpareParts();
      _categories = await DatabaseHelper.loadCategories('spare_part');
      _filterItems();
    } catch (e) {
      debugPrint('Error loading spare parts: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredSpareParts = _spareParts.where((item) {
        final matchesSearch = item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (item.supplier?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
        final matchesCategory = _selectedCategoryFilter == null || item.categoryId == _selectedCategoryFilter;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _showAddEditDialog({SparePart? item}) {
    final nameController = TextEditingController(text: item?.name);
    final qtyController = TextEditingController(text: item?.quantity.toString() ?? '1');
    final priceController = TextEditingController(text: item?.price.toString() ?? '0.0');
    final costController = TextEditingController(text: item?.cost.toString() ?? '0.0');
    final supplierController = TextEditingController(text: item?.supplier);
    int? selectedCategoryId = item?.categoryId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final primaryGold = const Color(0xFFD4AF37);
          final textColor = AppTheme.text(context);

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              item == null ? '⚙️ إضافة قطعة غيار جديدة' : '✏️ تعديل قطعة غيار',
              style: TextStyle(color: primaryGold, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(labelText: 'اسم قطعة الغيار *'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedCategoryId,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: const InputDecoration(labelText: 'التصنيف'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('بدون تصنيف')),
                        ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedCategoryId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(labelText: 'الكمية المتاحة *'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: costController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(labelText: 'سعر الشراء/التكلفة (ج.م) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(labelText: 'سعر البيع (ج.م) *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: supplierController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(labelText: 'المورد (اختياري)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                ),
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ يرجى إدخال اسم قطعة الغيار')));
                    return;
                  }

                  int finalId;
                  if (item != null) {
                    finalId = item.id;
                  } else {
                    final maxId = _spareParts.isEmpty
                        ? 0
                        : _spareParts.map((p) => p.id).reduce((a, b) => a > b ? a : b);
                    finalId = DatabaseHelper.generateNextIdFromMax(maxId);
                  }

                  final newPart = SparePart(
                    id: finalId,
                    name: nameController.text.trim(),
                    quantity: int.tryParse(qtyController.text) ?? 0,
                    price: double.tryParse(priceController.text) ?? 0.0,
                    cost: double.tryParse(costController.text) ?? 0.0,
                    supplier: supplierController.text.trim().isEmpty ? null : supplierController.text.trim(),
                    categoryId: selectedCategoryId,
                  );

                  await DatabaseHelper.saveSparePart(newPart);
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                },
                child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(SparePart item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        title: const Text('⚠️ تأكيد الحذف', style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف قطعة الغيار "${item.name}" بالكامل؟', style: TextStyle(color: AppTheme.text(context), fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseHelper.deleteSparePart(item.id);
              if (context.mounted) Navigator.pop(context);
              _loadData();
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final primaryGold = const Color(0xFFD4AF37);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚙️ إدارة قطع الغيار الصيانة',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إدارة قطع الغيار المستلمة من التجار ومتابعة كمياتها، أسعار الشراء والبيع، والموردين',
                    style: TextStyle(fontSize: 15, color: textMuted),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                label: const Text('إضافة قطعة غيار جديدة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Card
          Card(
            color: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'البحث باسم قطعة الغيار أو المورد...',
                        prefixIcon: Icon(Icons.search, color: primaryGold),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                          _filterItems();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedCategoryFilter,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                      hint: const Text('كل التصنيفات', style: TextStyle(fontFamily: 'Cairo')),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل التصنيفات', style: TextStyle(fontFamily: 'Cairo'))),
                        ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontFamily: 'Cairo')))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedCategoryFilter = val;
                          _filterItems();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Spare Parts Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))))
                : _filteredSpareParts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.settings_outlined, size: 64, color: textMuted),
                            const SizedBox(height: 16),
                            Text('لا توجد قطع غيار متوفرة حالياً بالمعايير المحددة', style: TextStyle(fontSize: 18, color: textMuted)),
                          ],
                        ),
                      )
                    : Card(
                        color: AppTheme.cardBg(context),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingTextStyle: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: primaryGold, fontSize: 16),
                            dataTextStyle: TextStyle(fontFamily: 'Cairo', color: textColor, fontSize: 15),
                            columns: const [
                              DataColumn(label: Text('المعرف')),
                              DataColumn(label: Text('اسم قطعة الغيار')),
                              DataColumn(label: Text('التصنيف')),
                              DataColumn(label: Text('الكمية المتاحة')),
                              DataColumn(label: Text('سعر الشراء')),
                              DataColumn(label: Text('سعر البيع')),
                              DataColumn(label: Text('المورد')),
                              DataColumn(label: Text('خيارات')),
                            ],
                            rows: _filteredSpareParts.map((item) {
                              return DataRow(cells: [
                                DataCell(Text('#${item.id}')),
                                DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(item.categoryName ?? 'بدون تصنيف', style: const TextStyle(color: Colors.blueAccent))),
                                DataCell(
                                  Text(
                                    item.quantity.toString(),
                                    style: TextStyle(
                                      color: item.quantity < 3 ? Colors.redAccent : textColor,
                                      fontWeight: item.quantity < 3 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                DataCell(Text('${item.cost.toStringAsFixed(2)} ج.م')),
                                DataCell(Text('${item.price.toStringAsFixed(2)} ج.م')),
                                DataCell(Text(item.supplier ?? 'غير محدد')),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit, color: primaryGold, size: 20),
                                        onPressed: () => _showAddEditDialog(item: item),
                                        tooltip: 'تعديل',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                        onPressed: () => _confirmDelete(item),
                                        tooltip: 'حذف',
                                      ),
                                    ],
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
