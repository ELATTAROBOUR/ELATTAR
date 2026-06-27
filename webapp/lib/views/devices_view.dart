// lib/views/devices_view.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';

class DevicesView extends StatefulWidget {
  const DevicesView({super.key});

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  List<Device> _devices = [];
  List<Device> _filteredDevices = [];
  List<Warehouse> _warehouses = [];
  List<Category> _brands = [];
  List<Category> _conditions = [];
  String _searchQuery = '';
  String _selectedWarehouse = 'الكل';
  String _selectedCondition = 'الكل'; 
  int? _selectedBrandFilter;
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
      _devices = await DatabaseHelper.loadDevices();
      _warehouses = await DatabaseHelper.loadWarehouses();
      _brands = await DatabaseHelper.loadCategories('device_brand');
      _conditions = await DatabaseHelper.loadCategories('device_condition');
      _filterItems();
    } catch (e) {
      debugPrint('Error loading devices: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredDevices = _devices.where((item) {
        final matchesSearch = item.model.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            item.imei.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (item.supplier?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            (item.code?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
            
        final matchesWarehouse = _selectedWarehouse == 'الكل' || item.warehouse == _selectedWarehouse;
        final matchesCondition = _selectedCondition == 'الكل' || 
            item.condition == _selectedCondition ||
            (item.condition == 'new' && _selectedCondition == 'جديد') ||
            (item.condition == 'used' && _selectedCondition == 'مستعمل');
        final matchesBrand = _selectedBrandFilter == null || item.categoryId == _selectedBrandFilter;
        
        return matchesSearch && matchesWarehouse && matchesCondition && matchesBrand;
      }).toList();
    });
  }

  void _showAddEditDialog({Device? item}) {
    final codeController = TextEditingController(text: item?.code);
    final modelController = TextEditingController(text: item?.model);
    final imeiController = TextEditingController(text: item?.imei);
    final qtyController = TextEditingController(text: item?.quantity.toString() ?? '1');
    final priceController = TextEditingController(text: item?.price.toString() ?? '0.0');
    final costController = TextEditingController(text: item?.cost.toString() ?? '0.0');
    final supplierController = TextEditingController(text: item?.supplier);
    String selectedWarehouse = item?.warehouse ?? (_warehouses.isNotEmpty ? _warehouses.first.name : 'المحل الرئيسي');
    String selectedCondition = item?.condition ?? (_conditions.isNotEmpty ? _conditions.first.name : 'جديد');
    int? selectedBrandId = item?.categoryId;

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
              item == null ? '➕ إضافة جهاز جديد/مستعمل' : '✏️ تعديل بيانات الجهاز',
              style: TextStyle(color: primaryGold, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(labelText: 'كود الباركود / الجهاز (اختياري)'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedBrandId,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: const InputDecoration(labelText: 'الماركة / البراند'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('بدون تحديد')),
                        ..._brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedBrandId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modelController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(labelText: 'موديل الهاتف/الجهاز *'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: imeiController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(labelText: 'رقم السيريال / IMEI (اختياري)'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _conditions.any((c) => c.name == selectedCondition) 
                                ? selectedCondition 
                                : (_conditions.isNotEmpty ? _conditions.first.name : selectedCondition),
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(color: textColor, fontSize: 16),
                            decoration: const InputDecoration(labelText: 'الحالة *'),
                            items: _conditions.isEmpty
                                ? const [
                                    DropdownMenuItem(value: 'new', child: Text('جديد')),
                                    DropdownMenuItem(value: 'used', child: Text('مستعمل')),
                                  ]
                                : _conditions.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                selectedCondition = val!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(labelText: 'الكمية بالمخزن *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedWarehouse,
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(color: textColor, fontSize: 16),
                            decoration: const InputDecoration(labelText: 'المخزن *'),
                            items: _warehouses.map((w) => DropdownMenuItem(value: w.name, child: Text(w.name))).toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                selectedWarehouse = val!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: costController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(labelText: 'سعر الشراء/التكلفة (ج.م) *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(labelText: 'سعر البيع المقترح (ج.م) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: supplierController,
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(labelText: 'المورد'),
                          ),
                        ),
                      ],
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
                  if (modelController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ يرجى إدخال اسم الموديل')));
                    return;
                  }

                  final newDevice = Device(
                    id: item?.id,
                    model: modelController.text.trim(),
                    imei: imeiController.text.trim(),
                    condition: selectedCondition,
                    quantity: int.tryParse(qtyController.text) ?? 1,
                    price: double.tryParse(priceController.text) ?? 0.0,
                    cost: double.tryParse(costController.text) ?? 0.0,
                    supplier: supplierController.text.trim().isEmpty ? null : supplierController.text.trim(),
                    warehouse: selectedWarehouse,
                    code: codeController.text.trim().isEmpty ? null : codeController.text.trim(),
                    categoryId: selectedBrandId,
                  );

                  await DatabaseHelper.saveDevice(newDevice);
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

  void _confirmDelete(Device item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        title: const Text('⚠️ تأكيد الحذف', style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف الجهاز "${item.model}"؟', style: TextStyle(color: AppTheme.text(context), fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              if (item.id != null) {
                await DatabaseHelper.deleteDevice(item.id!);
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
                    '📱 إدارة الأجهزة الجديدة والمستعملة',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تتبع الهواتف المتوفرة للبيع (جديد ومستعمل) وإدخال السيريال/IMEI وتوزيعها على المخازن',
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
                label: const Text('إضافة جهاز جديد/مستعمل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                        hintText: 'البحث بالموديل، السيريال IMEI، أو المورد...',
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
                      value: _selectedBrandFilter,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                      hint: const Text('كل الماركات', style: TextStyle(fontFamily: 'Cairo')),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('كل الماركات', style: TextStyle(fontFamily: 'Cairo'))),
                        ..._brands.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name, style: const TextStyle(fontFamily: 'Cairo')))),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedBrandFilter = val;
                          _filterItems();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCondition,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                      items: [
                        const DropdownMenuItem(value: 'الكل', child: Text('جميع الحالات')),
                        ..._conditions.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))),
                        const DropdownMenuItem(value: 'new', child: Text('جديد (القديم)')),
                        const DropdownMenuItem(value: 'used', child: Text('مستعمل (القديم)')),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedCondition = val!;
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
                      style: TextStyle(color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                      items: [
                        const DropdownMenuItem(value: 'الكل', child: Text('كل المخازن')),
                        ..._warehouses.map((w) => DropdownMenuItem(value: w.name, child: Text(w.name))),
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

          // Devices Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))))
                : _filteredDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_iphone_rounded, size: 64, color: textMuted),
                            const SizedBox(height: 16),
                            Text('لا توجد أجهزة متوفرة حالياً بالمعايير المحددة', style: TextStyle(fontSize: 18, color: textMuted)),
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
                              DataColumn(label: Text('الماركة')),
                              DataColumn(label: Text('الموديل')),
                              DataColumn(label: Text('الكود / الباركود')),
                              DataColumn(label: Text('الحالة')),
                              DataColumn(label: Text('السيريال / IMEI')),
                              DataColumn(label: Text('الكمية')),
                              DataColumn(label: Text('تكلفة الشراء')),
                              DataColumn(label: Text('سعر البيع')),
                              DataColumn(label: Text('المخزن')),
                              DataColumn(label: Text('المورد')),
                              DataColumn(label: Text('خيارات')),
                            ],
                            rows: _filteredDevices.map((item) {
                              return DataRow(cells: [
                                DataCell(Text('#${item.id ?? ""}')),
                                DataCell(Text(item.categoryName ?? 'بدون تحديد', style: const TextStyle(color: Colors.blueAccent))),
                                DataCell(Text(item.model, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(item.code ?? 'بلا كود', style: TextStyle(color: item.code != null ? textColor : Colors.grey))),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: item.condition == 'new' || item.condition == 'جديد'
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : (item.condition == 'used' || item.condition == 'مستعمل'
                                              ? Colors.blue.withValues(alpha: 0.15)
                                              : Colors.orange.withValues(alpha: 0.15)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      item.condition == 'new'
                                          ? 'جديد'
                                          : (item.condition == 'used' ? 'مستعمل' : item.condition),
                                      style: TextStyle(
                                        color: item.condition == 'new' || item.condition == 'جديد'
                                            ? Colors.green
                                            : (item.condition == 'used' || item.condition == 'مستعمل'
                                                ? Colors.blue
                                                : Colors.orange),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(item.imei.isEmpty ? '—' : item.imei)),
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
                                DataCell(Text(item.warehouse)),
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
