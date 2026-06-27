// lib/views/add_product_view.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';

class AddProductView extends StatefulWidget {
  const AddProductView({super.key});

  @override
  State<AddProductView> createState() => _AddProductViewState();
}

class _AddProductViewState extends State<AddProductView> {
  final _formKey = GlobalKey<FormState>();

  // Product type: 'accessory', 'spare_part', 'device'
  String _selectedType = 'accessory';

  // Controllers
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController(text: '0.0');
  final _priceController = TextEditingController(text: '0.0');
  final _supplierController = TextEditingController();

  // Device specific controllers
  final _modelController = TextEditingController();
  final _imeiController = TextEditingController();

  // Category selections
  int? _selectedCategoryId;
  String? _selectedCondition;
  String? _selectedWarehouse;

  // DB Data lists
  List<Category> _accessoryCategories = [];
  List<Category> _sparePartCategories = [];
  List<Category> _deviceBrands = [];
  List<Category> _deviceConditions = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _supplierController.dispose();
    _modelController.dispose();
    _imeiController.dispose();
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
      _deviceConditions =
          await DatabaseHelper.loadCategories('device_condition');
      _warehouses = await DatabaseHelper.loadWarehouses();

      _resetSelections();
    } catch (e) {
      debugPrint('Error loading form data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _resetSelections() {
    if (_selectedType == 'accessory') {
      _selectedCategoryId = _accessoryCategories.isNotEmpty
          ? _accessoryCategories.first.id
          : null;
    } else if (_selectedType == 'spare_part') {
      _selectedCategoryId = _sparePartCategories.isNotEmpty
          ? _sparePartCategories.first.id
          : null;
    } else if (_selectedType == 'device') {
      _selectedCategoryId =
          _deviceBrands.isNotEmpty ? _deviceBrands.first.id : null;
      _selectedCondition =
          _deviceConditions.isNotEmpty ? _deviceConditions.first.name : 'جديد';
    }

    if (_warehouses.isNotEmpty) {
      _selectedWarehouse = _warehouses.first.name;
    } else {
      _selectedWarehouse = 'المحل الرئيسي';
    }
  }

  void _clearForm() {
    _nameController.clear();
    _codeController.clear();
    _qtyController.text = '1';
    _costController.text = '0.0';
    _priceController.text = '0.0';
    _supplierController.clear();
    _modelController.clear();
    _imeiController.clear();
    _resetSelections();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
      final cost = double.tryParse(_costController.text.trim()) ?? 0.0;
      final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
      final supplier = _supplierController.text.trim().isEmpty
          ? null
          : _supplierController.text.trim();
      final code = _codeController.text.trim().isEmpty
          ? null
          : _codeController.text.trim();

      if (_selectedType == 'accessory') {
        final name = _nameController.text.trim();
        if (name.isEmpty) throw Exception('يرجى إدخال اسم الإكسسوار');

        final accessory = Accessory(
          name: name,
          quantity: qty,
          price: price,
          cost: cost,
          supplier: supplier,
          warehouse: _selectedWarehouse ?? 'المحل الرئيسي',
          code: code,
          categoryId: _selectedCategoryId,
        );
        await DatabaseHelper.saveAccessory(accessory);
      } else if (_selectedType == 'spare_part') {
        final name = _nameController.text.trim();
        if (name.isEmpty) throw Exception('يرجى إدخال اسم قطعة الغيار');

        // Generating a sequential ID for spare part
        final sparePartsList = await DatabaseHelper.loadSpareParts();
        final maxId = sparePartsList.isEmpty
            ? 0
            : sparePartsList.map((p) => p.id).reduce((a, b) => a > b ? a : b);
        final finalId = DatabaseHelper.generateNextIdFromMax(maxId);

        final sparePart = SparePart(
          id: finalId,
          name: name,
          quantity: qty,
          price: price,
          cost: cost,
          supplier: supplier,
          categoryId: _selectedCategoryId,
        );
        await DatabaseHelper.saveSparePart(sparePart);
      } else if (_selectedType == 'device') {
        final model = _modelController.text.trim();
        if (model.isEmpty) throw Exception('يرجى إدخال موديل الهاتف');

        final device = Device(
          model: model,
          imei: _imeiController.text.trim(),
          condition: _selectedCondition ?? 'جديد',
          quantity: qty,
          price: price,
          cost: cost,
          supplier: supplier,
          warehouse: _selectedWarehouse ?? 'المحل الرئيسي',
          code: code,
          categoryId: _selectedCategoryId,
        );
        await DatabaseHelper.saveDevice(device);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إضافة المنتج بنجاح وتحديث المخزن!',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
        ),
      );

      _clearForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في الإضافة: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.redAccent,
        ),
      );
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
    final primaryGold = const Color(0xFFD4AF37);
    final cardBg = AppTheme.cardBg(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                '➕ إضافة منتج جديد شامل للمخزن',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 4),
              Text(
                'قم بإضافة إكسسوارات أو أجهزة أو قطع غيار مباشرة إلى أقسام البرنامج والمخازن المناسبة.',
                style: TextStyle(
                    fontSize: 15, color: textMuted, fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 24),

              // dynamic Row / Segmented selections for type
              Row(
                children: [
                  _buildTypeCard(
                    title: 'إكسسوار',
                    type: 'accessory',
                    icon: Icons.headphones_rounded,
                    color: Colors.orangeAccent,
                    isSelected: _selectedType == 'accessory',
                  ),
                  const SizedBox(width: 16),
                  _buildTypeCard(
                    title: 'قطعة غيار',
                    type: 'spare_part',
                    icon: Icons.settings_suggest_rounded,
                    color: Colors.blueAccent,
                    isSelected: _selectedType == 'spare_part',
                  ),
                  const SizedBox(width: 16),
                  _buildTypeCard(
                    title: 'جهاز موبايل',
                    type: 'device',
                    icon: Icons.phone_iphone_rounded,
                    color: Colors.purpleAccent,
                    isSelected: _selectedType == 'device',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Form inputs card
              Card(
                color: cardBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _selectedType == 'accessory'
                                  ? Icons.headphones_rounded
                                  : (_selectedType == 'spare_part'
                                      ? Icons.settings_suggest_rounded
                                      : Icons.phone_iphone_rounded),
                              color: primaryGold,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedType == 'accessory'
                                  ? 'بيانات الإكسسوار الجديد'
                                  : (_selectedType == 'spare_part'
                                      ? 'بيانات قطعة الغيار الجديدة'
                                      : 'بيانات الهاتف/الجهاز الجديد'),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGold,
                                  fontFamily: 'Cairo'),
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        if (_selectedType == 'accessory')
                          _buildAccessoryFields(textColor),
                        if (_selectedType == 'spare_part')
                          _buildSparePartFields(textColor),
                        if (_selectedType == 'device')
                          _buildDeviceFields(textColor),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryGold,
                                    foregroundColor: const Color(0xFF1A2A3A),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  onPressed: _submitForm,
                                  icon: const Icon(
                                      Icons.check_circle_outline_rounded),
                                  label: const Text(
                                    'حفظ وإضافة للمخزن',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo'),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              height: 50,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: textMuted.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _clearForm,
                                icon: Icon(Icons.clear_all_rounded,
                                    color: textColor),
                                label: Text(
                                  'تفريغ الحقول',
                                  style: TextStyle(
                                      color: textColor,
                                      fontFamily: 'Cairo',
                                      fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildTypeCard({
    required String title,
    required String type,
    required IconData icon,
    required Color color,
    required bool isSelected,
  }) {
    final cardBg = AppTheme.cardBg(context);
    final textColor = AppTheme.text(context);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedType = type;
            _resetSelections();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: isSelected ? color : textColor.withValues(alpha: 0.6),
                  size: 28),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color:
                      isSelected ? textColor : textColor.withValues(alpha: 0.8),
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ACCESSORY FORM FIELDS ---
  Widget _buildAccessoryFields(Color textColor) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _nameController,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'اسم الإكسسوار *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? '⚠️ يرجى إدخال اسم الإكسسوار'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _codeController,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'كود الباركود / القطعة (اختياري)',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedCategoryId,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                    color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('بدون تصنيف',
                          style: TextStyle(fontFamily: 'Cairo'))),
                  ..._accessoryCategories.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name,
                          style: const TextStyle(fontFamily: 'Cairo')))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedCategoryId = val;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedWarehouse,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                    color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'المخزن *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                items: _warehouses
                    .map((w) => DropdownMenuItem(
                        value: w.name,
                        child: Text(w.name,
                            style: const TextStyle(fontFamily: 'Cairo'))))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedWarehouse = val!;
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
              child: TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'الكمية *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || int.tryParse(val) == null
                    ? '⚠️ الكمية غير صحيحة'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'سعر التكلفة (ج.م) *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null
                    ? '⚠️ سعر التكلفة غير صحيح'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'سعر البيع (ج.م) *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null
                    ? '⚠️ سعر البيع غير صحيح'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _supplierController,
          style: TextStyle(color: textColor, fontFamily: 'Cairo'),
          decoration: const InputDecoration(
            labelText: 'المورد (اختياري)',
            labelStyle: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      ],
    );
  }

  // --- SPARE PART FORM FIELDS ---
  Widget _buildSparePartFields(Color textColor) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _nameController,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'اسم قطعة الغيار *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? '⚠️ يرجى إدخال اسم قطعة الغيار'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedCategoryId,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                    color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('بدون تصنيف',
                          style: TextStyle(fontFamily: 'Cairo'))),
                  ..._sparePartCategories.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name,
                          style: const TextStyle(fontFamily: 'Cairo')))),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedCategoryId = val;
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
              child: TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'الكمية المتاحة *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || int.tryParse(val) == null
                    ? '⚠️ الكمية غير صحيحة'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'سعر الشراء/التكلفة (ج.م) *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null
                    ? '⚠️ سعر الشراء غير صحيح'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'سعر البيع (ج.م) *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null
                    ? '⚠️ سعر البيع غير صحيح'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _supplierController,
          style: TextStyle(color: textColor, fontFamily: 'Cairo'),
          decoration: const InputDecoration(
            labelText: 'المورد (اختياري)',
            labelStyle: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      ],
    );
  }

  // --- DEVICE FORM FIELDS ---
  Widget _buildDeviceFields(Color textColor) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedCategoryId,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                    color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'الماركة / البراند *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                items: _deviceBrands
                    .map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text(b.name,
                            style: const TextStyle(fontFamily: 'Cairo'))))
                    .toList(),
                validator: (val) =>
                    val == null ? '⚠️ يرجى اختيار البراند' : null,
                onChanged: (val) {
                  setState(() {
                    _selectedCategoryId = val;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _modelController,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'موديل الهاتف/الجهاز *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? '⚠️ يرجى إدخال موديل الهاتف'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _imeiController,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'رقم السيريال / IMEI (اختياري)',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _codeController,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'كود الباركود / الجهاز (اختياري)',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCondition,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                    color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'الحالة *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                items: _deviceConditions.isEmpty
                    ? const [
                        DropdownMenuItem(
                            value: 'جديد',
                            child: Text('جديد',
                                style: TextStyle(fontFamily: 'Cairo'))),
                        DropdownMenuItem(
                            value: 'مستعمل',
                            child: Text('مستعمل',
                                style: TextStyle(fontFamily: 'Cairo'))),
                      ]
                    : _deviceConditions
                        .map((c) => DropdownMenuItem(
                            value: c.name,
                            child: Text(c.name,
                                style: const TextStyle(fontFamily: 'Cairo'))))
                        .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCondition = val!;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedWarehouse,
                dropdownColor: AppTheme.cardBg(context),
                style: TextStyle(
                    color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'المخزن المستهدف *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                items: _warehouses
                    .map((w) => DropdownMenuItem(
                        value: w.name,
                        child: Text(w.name,
                            style: const TextStyle(fontFamily: 'Cairo'))))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedWarehouse = val!;
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
              child: TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'الكمية بالمخزن *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || int.tryParse(val) == null
                    ? '⚠️ الكمية غير صحيحة'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'سعر الشراء/التكلفة (ج.م) *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null
                    ? '⚠️ سعر التكلفة غير صحيح'
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                decoration: const InputDecoration(
                  labelText: 'سعر البيع المقترح (ج.م) *',
                  labelStyle: TextStyle(fontFamily: 'Cairo'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null
                    ? '⚠️ سعر البيع غير صحيح'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _supplierController,
          style: TextStyle(color: textColor, fontFamily: 'Cairo'),
          decoration: const InputDecoration(
            labelText: 'المورد (اختياري)',
            labelStyle: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      ],
    );
  }
}
