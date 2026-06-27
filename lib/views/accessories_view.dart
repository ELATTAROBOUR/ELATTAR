// lib/views/accessories_view.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/custom_toast.dart';

class AccessoriesView extends StatefulWidget {
  const AccessoriesView({super.key});

  @override
  State<AccessoriesView> createState() => _AccessoriesViewState();
}

class _AccessoriesViewState extends State<AccessoriesView> {
  List<Accessory> _accessories = [];
  List<Accessory> _filteredAccessories = [];
  List<Warehouse> _warehouses = [];
  List<Category> _categories = [];
  String _searchQuery = '';
  String _selectedWarehouse = 'الكل';
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
      _accessories = await DatabaseHelper.loadAccessories();
      _warehouses = await DatabaseHelper.loadWarehouses();
      _categories = await DatabaseHelper.loadCategories('accessory');
      _filterItems();
    } catch (e) {
      debugPrint('Error loading accessories: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredAccessories = _accessories.where((item) {
        final matchesSearch = item.name
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            (item.supplier
                    ?.toLowerCase()
                    .contains(_searchQuery.toLowerCase()) ??
                false) ||
            (item.code?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                false);
        final matchesWarehouse = _selectedWarehouse == 'الكل' ||
            item.warehouse == _selectedWarehouse;
        final matchesCategory = _selectedCategoryFilter == null ||
            item.categoryId == _selectedCategoryFilter;
        return matchesSearch && matchesWarehouse && matchesCategory;
      }).toList();
    });
  }

  void _showAddEditDialog({Accessory? item}) {
    final codeController = TextEditingController(text: item?.code);
    final nameController = TextEditingController(text: item?.name);
    final qtyController =
        TextEditingController(text: item?.quantity.toString() ?? '1');
    final priceController =
        TextEditingController(text: item?.price.toString() ?? '0.0');
    final costController =
        TextEditingController(text: item?.cost.toString() ?? '0.0');
    final supplierController = TextEditingController(text: item?.supplier);
    String selectedWarehouse = item?.warehouse ??
        (_warehouses.isNotEmpty ? _warehouses.first.name : 'المحل الرئيسي');
    int? selectedCategoryId = item?.categoryId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final primaryGold = const Color(0xFFD4AF37);
          final textColor = AppTheme.text(context);

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              item == null ? '➕ إضافة إكسسوار جديد' : '✏️ تعديل إكسسوار',
              style: TextStyle(
                  color: primaryGold,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(
                          labelText: 'كود الباركود / القطعة (اختياري)'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: textColor),
                      decoration:
                          const InputDecoration(labelText: 'اسم الإكسسوار *'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedCategoryId,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: const InputDecoration(labelText: 'التصنيف'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('بدون تصنيف')),
                        ..._categories.map((c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedCategoryId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: textColor),
                            decoration:
                                const InputDecoration(labelText: 'الكمية *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedWarehouse,
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(color: textColor, fontSize: 16),
                            decoration:
                                const InputDecoration(labelText: 'المخزن *'),
                            items: _warehouses
                                .map((w) => DropdownMenuItem(
                                    value: w.name, child: Text(w.name)))
                                .toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                selectedWarehouse = val!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: costController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                                labelText: 'سعر التكلفة (ج.م) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                                labelText: 'سعر البيع (ج.م) *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: supplierController,
                      style: TextStyle(color: textColor),
                      decoration:
                          const InputDecoration(labelText: 'المورد (اختياري)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context), fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                ),
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) {
                    CustomToast.show(context,
                        message: '⚠️ يرجى إدخال اسم الإكسسوار',
                        type: ToastType.warning);
                    return;
                  }

                  final newAcc = Accessory(
                    id: item?.id,
                    name: nameController.text.trim(),
                    quantity: int.tryParse(qtyController.text) ?? 0,
                    price: double.tryParse(priceController.text) ?? 0.0,
                    cost: double.tryParse(costController.text) ?? 0.0,
                    supplier: supplierController.text.trim().isEmpty
                        ? null
                        : supplierController.text.trim(),
                    warehouse: selectedWarehouse,
                    code: codeController.text.trim().isEmpty
                        ? null
                        : codeController.text.trim(),
                    categoryId: selectedCategoryId,
                  );

                  await DatabaseHelper.saveAccessory(newAcc);
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                },
                child: const Text('حفظ',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(Accessory item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        title: const Text('⚠️ تأكيد الحذف',
            style: TextStyle(
                color: Colors.redAccent,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف الإكسسوار "${item.name}" بالكامل؟',
            style: TextStyle(color: AppTheme.text(context), fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء',
                style: TextStyle(
                    color: AppTheme.textMuted(context), fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white),
            onPressed: () async {
              if (item.id != null) {
                await DatabaseHelper.deleteAccessory(item.id!);
              }
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
                    '🎧 إدارة قطع الإكسسوار',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إضافة وعرض وتعديل كميات وأسعار الإكسسوارات المتوفرة وتوزيعها على الفروع والمخازن',
                    style: TextStyle(fontSize: 15, color: textMuted),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                label: const Text('إضافة إكسسوار جديد',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Card
          Card(
            color: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'البحث باسم الإكسسوار أو المورد...',
                        prefixIcon: Icon(Icons.search, color: primaryGold),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
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
                      style: TextStyle(
                          color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                      hint: const Text('كل التصنيفات',
                          style: TextStyle(fontFamily: 'Cairo')),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('كل التصنيفات',
                                style: TextStyle(fontFamily: 'Cairo'))),
                        ..._categories.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name,
                                style: const TextStyle(fontFamily: 'Cairo')))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedCategoryFilter = val;
                          _filterItems();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedWarehouse,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(
                          color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                      items: [
                        const DropdownMenuItem(
                            value: 'الكل', child: Text('كل المخازن')),
                        ..._warehouses.map((w) => DropdownMenuItem(
                            value: w.name, child: Text(w.name))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedWarehouse = val!;
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

          // Accessories Table
          Expanded(
            child: _isLoading
                ? SkeletonLoading.dashboardPage(context)
                : _filteredAccessories.isEmpty
                    ? AppEmptyState.noData()
                    : Card(
                        color: AppTheme.cardBg(context),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingTextStyle: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: primaryGold,
                                fontSize: 16),
                            dataTextStyle: TextStyle(
                                fontFamily: 'Cairo',
                                color: textColor,
                                fontSize: 15),
                            columns: const [
                              DataColumn(label: Text('المعرف')),
                              DataColumn(label: Text('الاسم')),
                              DataColumn(label: Text('التصنيف')),
                              DataColumn(label: Text('الكود / الباركود')),
                              DataColumn(label: Text('الكمية بالمخزن')),
                              DataColumn(label: Text('سعر التكلفة')),
                              DataColumn(label: Text('سعر البيع')),
                              DataColumn(label: Text('المخزن الحالي')),
                              DataColumn(label: Text('المورد')),
                              DataColumn(label: Text('خيارات')),
                            ],
                            rows: _filteredAccessories.map((item) {
                              return DataRow(cells: [
                                DataCell(Text('#${item.id ?? ""}')),
                                DataCell(Text(item.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                                DataCell(Text(item.categoryName ?? 'بدون تصنيف',
                                    style: const TextStyle(
                                        color: Colors.blueAccent))),
                                DataCell(Text(item.code ?? 'بلا كود',
                                    style: TextStyle(
                                        color: item.code != null
                                            ? textColor
                                            : Colors.grey))),
                                DataCell(
                                  Text(
                                    item.quantity.toString(),
                                    style: TextStyle(
                                      color: item.quantity < 3
                                          ? Colors.redAccent
                                          : textColor,
                                      fontWeight: item.quantity < 3
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                DataCell(Text(
                                    '${item.cost.toStringAsFixed(2)} ج.م')),
                                DataCell(Text(
                                    '${item.price.toStringAsFixed(2)} ج.م')),
                                DataCell(Text(item.warehouse)),
                                DataCell(Text(item.supplier ?? 'غير محدد')),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit,
                                            color: primaryGold, size: 20),
                                        onPressed: () =>
                                            _showAddEditDialog(item: item),
                                        tooltip: 'تعديل',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.redAccent, size: 20),
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
