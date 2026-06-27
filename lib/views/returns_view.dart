// lib/views/returns_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';

class ReturnsView extends StatefulWidget {
  const ReturnsView({super.key});

  @override
  State<ReturnsView> createState() => _ReturnsViewState();
}

class _ReturnsViewState extends State<ReturnsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<ReturnSearchItem> _inventoryItems = [];
  final List<ReturnCartItem> _cart = [];
  List<ReturnTransaction> _pastReturns = [];

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  
  // Selected item state
  ReturnSearchItem? _selectedItem;
  final TextEditingController _addQtyController = TextEditingController(text: '1');
  final TextEditingController _addPriceController = TextEditingController();

  String _paymentMethod = 'cash';
  bool _isSaving = false;

  // Custom Return Form State
  bool _isCustomReturn = false;
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customCodeController = TextEditingController();
  final TextEditingController _customQtyController = TextEditingController(text: '1');
  final TextEditingController _customPriceController = TextEditingController();
  final TextEditingController _customCostController = TextEditingController(text: '0.0');

  String _customType = 'accessory';
  int? _customCategoryId;
  String? _customWarehouse;
  String? _customCondition;

  List<Category> _accessoryCategories = [];
  List<Category> _sparePartCategories = [];
  List<Category> _deviceBrands = [];
  List<Category> _deviceConditions = [];
  List<Warehouse> _warehouses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _loadPastReturns();
      }
    });
    _loadInventory();
    _loadFormData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _notesController.dispose();
    _addQtyController.dispose();
    _addPriceController.dispose();
    _customNameController.dispose();
    _customCodeController.dispose();
    _customQtyController.dispose();
    _customPriceController.dispose();
    _customCostController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    try {
      final accessoryCats = await DatabaseHelper.loadCategories('accessory');
      final sparePartCats = await DatabaseHelper.loadCategories('spare_part');
      final deviceBrandsList = await DatabaseHelper.loadCategories('device_brand');
      final deviceConds = await DatabaseHelper.loadCategories('device_condition');
      final whList = await DatabaseHelper.loadWarehouses();

      setState(() {
        _accessoryCategories = accessoryCats;
        _sparePartCategories = sparePartCats;
        _deviceBrands = deviceBrandsList;
        _deviceConditions = deviceConds;
        _warehouses = whList;

        if (_warehouses.isNotEmpty) {
          _customWarehouse = _warehouses.first.name;
        } else {
          _customWarehouse = 'المحل الرئيسي';
        }
        _customCondition = _deviceConditions.isNotEmpty ? _deviceConditions.first.name : 'جديد';
      });
    } catch (e) {
      debugPrint('Error loading returns form categories: $e');
    }
  }

  void _addCustomToCart() {
    final String name = _customNameController.text.trim();
    final String code = _customCodeController.text.trim();
    final int qty = int.tryParse(_customQtyController.text.trim()) ?? 0;
    final double price = double.tryParse(_customPriceController.text.trim()) ?? 0.0;
    final double cost = double.tryParse(_customCostController.text.trim()) ?? 0.0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ يرجى إدخال اسم المنتج المرتجع', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
      );
      return;
    }

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ يرجى إدخال كمية صحيحة', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
      );
      return;
    }

    final customItem = ReturnSearchItem(
      type: _customType,
      id: -1,
      name: name,
      code: code,
      price: price,
      cost: cost,
      quantity: qty,
      warehouse: _customType == 'spare_part' ? 'قسم الصيانة' : (_customWarehouse ?? 'المحل الرئيسي'),
      originalObject: CustomReturnInfo(
        categoryId: _customCategoryId,
        condition: _customType == 'device' ? (_customCondition ?? 'جديد') : null,
      ),
    );

    setState(() {
      _cart.add(ReturnCartItem(
        product: customItem,
        quantity: qty,
        price: price,
      ));

      // Reset form
      _customNameController.clear();
      _customCodeController.clear();
      _customPriceController.clear();
      _customCostController.text = '0.0';
      _customQtyController.text = '1';
      _customCategoryId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔄 تم إضافة الصنف غير المسجل لسلة المرتجعات', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.green, duration: Duration(milliseconds: 700)),
    );
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final accessories = await DatabaseHelper.loadAccessories();
      final devices = await DatabaseHelper.loadDevices();
      final spareParts = await DatabaseHelper.loadSpareParts();

      final List<ReturnSearchItem> items = [];

      for (var acc in accessories) {
        items.add(ReturnSearchItem(
          type: 'accessory',
          id: acc.id ?? 0,
          name: acc.name,
          code: acc.code ?? '',
          price: acc.price,
          cost: acc.cost,
          quantity: acc.quantity,
          warehouse: acc.warehouse,
          originalObject: acc,
        ));
      }

      for (var dev in devices) {
        items.add(ReturnSearchItem(
          type: 'device',
          id: dev.id ?? 0,
          name: '${dev.model} (${dev.condition == 'new' ? 'جديد' : 'مستعمل'})',
          code: dev.code ?? dev.imei,
          price: dev.price,
          cost: dev.cost,
          quantity: dev.quantity,
          warehouse: dev.warehouse,
          originalObject: dev,
        ));
      }

      for (var part in spareParts) {
        items.add(ReturnSearchItem(
          type: 'spare_part',
          id: part.id,
          name: 'قطعة غيار: ${part.name}',
          code: '',
          price: part.price,
          cost: part.cost,
          quantity: part.quantity,
          warehouse: 'قسم الصيانة',
          originalObject: part,
        ));
      }

      setState(() {
        _inventoryItems = items;
      });
    } catch (e) {
      debugPrint('Error loading returns inventory: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPastReturns() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final returns = await DatabaseHelper.loadReturns();
      setState(() {
        _pastReturns = returns;
      });
    } catch (e) {
      debugPrint('Error loading past returns: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectProduct(ReturnSearchItem item) {
    setState(() {
      _selectedItem = item;
      _addQtyController.text = '1';
      _addPriceController.text = item.price.toStringAsFixed(2);
      _searchController.clear();
    });
  }

  void _addToCart() {
    if (_selectedItem == null) return;

    final int qty = int.tryParse(_addQtyController.text) ?? 0;
    final double price = double.tryParse(_addPriceController.text) ?? 0.0;

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ يرجى إدخال كمية صحيحة للمرتجع'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Check if item already exists in return cart
    final existingIndex = _cart.indexWhere((cartItem) =>
        cartItem.product.type == _selectedItem!.type && cartItem.product.id == _selectedItem!.id);

    if (existingIndex != -1) {
      setState(() {
        _cart[existingIndex].quantity += qty;
        _cart[existingIndex].price = price; // Update price
      });
    } else {
      setState(() {
        _cart.add(ReturnCartItem(
          product: _selectedItem!,
          quantity: qty,
          price: price,
        ));
      });
    }

    setState(() {
      _selectedItem = null;
      _addPriceController.clear();
      _addQtyController.text = '1';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔄 تم إضافة الصنف لسلة المرتجعات'), backgroundColor: Colors.green, duration: Duration(milliseconds: 700)),
    );
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  double get _totalRefund => _cart.fold(0.0, (sum, item) => sum + (item.quantity * item.price));

  Future<void> _completeReturn() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ سلة المرتجعات فارغة!'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // 1. Increment Stock Quantities (Return to inventory)
      for (var item in _cart) {
        final prod = item.product;
        final int qtyToReturn = item.quantity;

        if (prod.id == -1) {
          final customInfo = prod.originalObject as CustomReturnInfo;
          if (prod.type == 'accessory') {
            final acc = Accessory(
              name: prod.name,
              quantity: qtyToReturn,
              price: prod.price,
              cost: prod.cost,
              warehouse: prod.warehouse,
              code: prod.code.isEmpty ? null : prod.code,
              categoryId: customInfo.categoryId,
            );
            await DatabaseHelper.saveAccessory(acc);
          } else if (prod.type == 'device') {
            final dev = Device(
              model: prod.name,
              imei: prod.code, // use code as IMEI/serial
              condition: customInfo.condition == 'جديد' ? 'new' : 'used',
              quantity: qtyToReturn,
              price: prod.price,
              cost: prod.cost,
              warehouse: prod.warehouse,
              code: prod.code.isEmpty ? null : prod.code,
              categoryId: customInfo.categoryId,
            );
            await DatabaseHelper.saveDevice(dev);
          } else if (prod.type == 'spare_part') {
            final sparePartsList = await DatabaseHelper.loadSpareParts();
            final maxId = sparePartsList.isEmpty
                ? 0
                : sparePartsList.map((p) => p.id).reduce((a, b) => a > b ? a : b);
            final finalId = DatabaseHelper.generateNextIdFromMax(maxId);

            final part = SparePart(
              id: finalId,
              name: prod.name,
              quantity: qtyToReturn,
              price: prod.price,
              cost: prod.cost,
              categoryId: customInfo.categoryId,
            );
            await DatabaseHelper.saveSparePart(part);
          }
        } else {
          if (prod.type == 'accessory') {
            final acc = prod.originalObject as Accessory;
            acc.quantity = acc.quantity + qtyToReturn;
            await DatabaseHelper.saveAccessory(acc);
          } else if (prod.type == 'device') {
            final dev = prod.originalObject as Device;
            dev.quantity = dev.quantity + qtyToReturn;
            await DatabaseHelper.saveDevice(dev);
          } else if (prod.type == 'spare_part') {
            final part = prod.originalObject as SparePart;
            part.quantity = part.quantity + qtyToReturn;
            await DatabaseHelper.saveSparePart(part);
          }
        }
      }

      // 2. Prepare items JSON payload
      final List<Map<String, dynamic>> itemsPayload = _cart.map((item) {
        return {
          'type': item.product.type,
          'id': item.product.id,
          'name': item.product.name,
          'quantity': item.quantity,
          'price': item.price,
        };
      }).toList();

      final newReturn = ReturnTransaction(
        returnDate: DateTime.now(),
        customerName: _customerNameController.text.trim().isEmpty ? null : _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim().isEmpty ? null : _customerPhoneController.text.trim(),
        totalAmount: _totalRefund,
        paymentMethod: _paymentMethod,
        itemsJson: jsonEncode(itemsPayload),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      // 3. Save Return to database
      await DatabaseHelper.saveReturn(newReturn);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تسجيل المرتجع بنجاح وإعادة إضافة الكميات للمخزون'), backgroundColor: Colors.green),
        );

        setState(() {
          _cart.clear();
          _customerNameController.clear();
          _customerPhoneController.clear();
          _notesController.clear();
          _selectedItem = null;
        });

        await _loadInventory();
      }
    } catch (e) {
      debugPrint('Error saving return transaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ حدث خطأ أثناء تسجيل المرتجع: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          color: AppTheme.cardBg(context),
          child: SafeArea(
            child: TabBar(
              controller: _tabController,
              labelColor: primaryGold,
              unselectedLabelColor: textColor.withValues(alpha: 0.6),
              indicatorColor: primaryGold,
              labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 15),
              tabs: const [
                Tab(icon: Icon(Icons.assignment_return_rounded, size: 20), text: 'تسجيل مرتجع جديد'),
                Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'سجل المرتجعات السابقة'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewReturnTab(),
          _buildReturnsHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildNewReturnTab() {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final cardBg = AppTheme.cardBg(context);
    final primaryGold = const Color(0xFFD4AF37);

    if (_isLoading && _inventoryItems.isEmpty) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_isCustomReturn ? Icons.add_box_rounded : Icons.assignment_return_rounded, color: primaryGold, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCustomReturn ? '📝 إضافة مرتجع جديد غير مسجل' : '🔄 تسجيل مرتجع جديد',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: textColor, fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isCustomReturn
                          ? 'أدخل بيانات الصنف غير المسجل لإضافته للمخزن وتوثيق عملية استرجاعه'
                          : 'ابحث عن المنتج المراد إرجاعه لإضافته للمخزن مرة أخرى وتوثيق العملية مالياً',
                      style: TextStyle(fontSize: 15, color: textMuted, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: primaryGold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: () {
                  setState(() {
                    _isCustomReturn = !_isCustomReturn;
                    _selectedItem = null;
                  });
                },
                icon: Icon(_isCustomReturn ? Icons.search_rounded : Icons.add_box_rounded, color: primaryGold),
                label: Text(
                  _isCustomReturn ? 'البحث في المخزن' : 'مرتجع صنف غير مسجل',
                  style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      if (!_isCustomReturn) ...[
                        // Search Autocomplete
                        Card(
                          color: cardBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return Autocomplete<ReturnSearchItem>(
                                  optionsBuilder: (TextEditingValue textEditingValue) {
                                    if (textEditingValue.text.isEmpty) {
                                      return const Iterable<ReturnSearchItem>.empty();
                                    }
                                    final query = textEditingValue.text.trim().toLowerCase();
                                    return _inventoryItems.where((item) {
                                      return item.name.toLowerCase().contains(query) ||
                                          item.code.toLowerCase().contains(query);
                                    });
                                  },
                                  displayStringForOption: (ReturnSearchItem option) => option.name,
                                  fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                                    return TextField(
                                      controller: textController,
                                      focusNode: focusNode,
                                      style: TextStyle(color: textColor, fontSize: 16),
                                      decoration: InputDecoration(
                                        hintText: 'ابحث باسم المنتج، الكود، الباركود أو IMEI للجهاز...',
                                        prefixIcon: Icon(Icons.search, color: primaryGold),
                                        border: InputBorder.none,
                                        filled: false,
                                      ),
                                    );
                                  },
                                  optionsViewBuilder: (context, onSelected, options) {
                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        color: cardBg,
                                        elevation: 4.0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        child: SizedBox(
                                          width: constraints.maxWidth,
                                          height: 300,
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            itemCount: options.length,
                                            itemBuilder: (context, index) {
                                              final item = options.elementAt(index);
                                              final category = item.type == 'accessory'
                                                  ? '🎧 إكسسوار'
                                                  : item.type == 'device'
                                                      ? '📱 جهاز'
                                                      : '🔧 قطعة غيار';
                                              return ListTile(
                                                title: Text(item.name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                                subtitle: Text(
                                                  'النوع: $category | كود: ${item.code.isEmpty ? "لا يوجد" : item.code} | متاح بالمخزن: ${item.quantity} | المخزن: ${item.warehouse}',
                                                  style: TextStyle(color: textMuted, fontSize: 12),
                                                ),
                                                trailing: Text('${item.price.toStringAsFixed(2)} ج.م', style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold)),
                                                onTap: () => onSelected(item),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  onSelected: (ReturnSearchItem selection) {
                                    _selectProduct(selection);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Selected Item details for return
                        if (_selectedItem != null) ...[
                          Card(
                            color: cardBg,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: primaryGold.withValues(alpha: 0.5))),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '📌 المنتج المراد إرجاعه: ${_selectedItem!.name}',
                                        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.redAccent),
                                        onPressed: () => setState(() => _selectedItem = null),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'المخزن الحالي: ${_selectedItem!.warehouse}  |  المخزون المتوفر: ${_selectedItem!.quantity}  |  سعر البيع الافتراضي: ${_selectedItem!.price.toStringAsFixed(2)} ج.م',
                                    style: TextStyle(color: textMuted, fontSize: 14),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _addQtyController,
                                          keyboardType: TextInputType.number,
                                          style: TextStyle(color: textColor),
                                          decoration: const InputDecoration(
                                            labelText: 'كمية المرتجع',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextField(
                                          controller: _addPriceController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: TextStyle(color: textColor),
                                          decoration: const InputDecoration(
                                            labelText: 'سعر الاسترداد للقطعة (ج.م)',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryGold,
                                          foregroundColor: const Color(0xFF1A2A3A),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                        ),
                                        onPressed: _addToCart,
                                        icon: const Icon(Icons.add_circle_outline_rounded),
                                        label: const Text('إضافة للمرتجعات'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ] else ...[
                        // Custom Return Entry Form
                        Card(
                          color: cardBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: primaryGold.withValues(alpha: 0.3))),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.edit_note_rounded, color: primaryGold, size: 22),
                                    const SizedBox(width: 8),
                                    Text(
                                      'إدخال بيانات صنف مرتجع جديد (غير مسجل)',
                                      style: TextStyle(color: primaryGold, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _customNameController,
                                        style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'اسم المنتج المرتجع *',
                                          labelStyle: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextField(
                                        controller: _customCodeController,
                                        style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'الكود / السيريال (اختياري)',
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
                                        initialValue: _customType,
                                        dropdownColor: cardBg,
                                        style: TextStyle(color: textColor, fontSize: 15, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'نوع المنتج المرتجع *',
                                          labelStyle: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'accessory', child: Text('🎧 إكسسوار', style: TextStyle(fontFamily: 'Cairo'))),
                                          DropdownMenuItem(value: 'spare_part', child: Text('🔧 قطعة غيار', style: TextStyle(fontFamily: 'Cairo'))),
                                          DropdownMenuItem(value: 'device', child: Text('📱 جهاز موبايل', style: TextStyle(fontFamily: 'Cairo'))),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              _customType = val;
                                              _customCategoryId = null; // Reset category selection
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Categories (dynamically loaded by type)
                                    Expanded(
                                      child: DropdownButtonFormField<int?>(
                                        initialValue: _customCategoryId,
                                        dropdownColor: cardBg,
                                        style: TextStyle(color: textColor, fontSize: 15, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'تصنيف المنتج (ترشيح)',
                                          labelStyle: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                        items: [
                                          const DropdownMenuItem(value: null, child: Text('بدون تصنيف', style: TextStyle(fontFamily: 'Cairo'))),
                                          if (_customType == 'accessory')
                                            ..._accessoryCategories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontFamily: 'Cairo')))),
                                          if (_customType == 'spare_part')
                                            ..._sparePartCategories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontFamily: 'Cairo')))),
                                          if (_customType == 'device')
                                            ..._deviceBrands.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontFamily: 'Cairo')))),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            _customCategoryId = val;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    // Warehouse dropdown (only for accessories and devices)
                                    if (_customType != 'spare_part') ...[
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _customWarehouse,
                                          dropdownColor: cardBg,
                                          style: TextStyle(color: textColor, fontSize: 15, fontFamily: 'Cairo'),
                                          decoration: const InputDecoration(
                                            labelText: 'المخزن *',
                                            labelStyle: TextStyle(fontFamily: 'Cairo'),
                                          ),
                                          items: _warehouses.map((w) => DropdownMenuItem(value: w.name, child: Text(w.name, style: const TextStyle(fontFamily: 'Cairo')))).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _customWarehouse = val;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                    ],
                                    // Device Condition dropdown (only for devices)
                                    if (_customType == 'device') ...[
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _customCondition,
                                          dropdownColor: cardBg,
                                          style: TextStyle(color: textColor, fontSize: 15, fontFamily: 'Cairo'),
                                          decoration: const InputDecoration(
                                            labelText: 'حالة الجهاز *',
                                            labelStyle: TextStyle(fontFamily: 'Cairo'),
                                          ),
                                          items: _deviceConditions.isNotEmpty
                                              ? _deviceConditions.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name, style: const TextStyle(fontFamily: 'Cairo')))).toList()
                                              : const [
                                                  DropdownMenuItem(value: 'جديد', child: Text('جديد', style: TextStyle(fontFamily: 'Cairo'))),
                                                  DropdownMenuItem(value: 'مستعمل', child: Text('مستعمل', style: TextStyle(fontFamily: 'Cairo'))),
                                                ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _customCondition = val;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                    ],
                                    Expanded(
                                      child: TextField(
                                        controller: _customQtyController,
                                        keyboardType: TextInputType.number,
                                        style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'الكمية *',
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
                                      child: TextField(
                                        controller: _customPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر الاسترداد للقطعة *',
                                          labelStyle: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextField(
                                        controller: _customCostController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر التكلفة للقطعة',
                                          labelStyle: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryGold,
                                        foregroundColor: const Color(0xFF1A2A3A),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: _addCustomToCart,
                                      icon: const Icon(Icons.add_circle_outline_rounded),
                                      label: const Text('إضافة للمرتجعات', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Cart List
                      Expanded(
                        child: Card(
                          color: cardBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '📦 قائمة أصناف المرتجع الحالية',
                                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    if (_cart.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () => setState(() => _cart.clear()),
                                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                                        label: const Text('تفريغ القائمة', style: TextStyle(color: Colors.redAccent)),
                                      ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Expanded(
                                  child: _cart.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.assignment_return_outlined, size: 64, color: textMuted),
                                              const SizedBox(height: 16),
                                              Text('لم يتم إضافة أي أصناف مرتجعة بعد. ابحث وأضف منتجات للبدء.', style: TextStyle(color: textMuted, fontSize: 16)),
                                            ],
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: _cart.length,
                                          itemBuilder: (context, index) {
                                            final item = _cart[index];
                                            final itemTotal = item.quantity * item.price;
                                            final category = item.product.type == 'accessory'
                                                ? 'إكسسوار'
                                                : item.product.type == 'device'
                                                    ? 'جهاز'
                                                    : 'قطعة غيار';
                                            return ListTile(
                                              title: Text(item.product.name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                              subtitle: Text(
                                                'النوع: $category | الكمية المسترجعة: ${item.quantity} | سعر استرداد القطعة: ${item.price.toStringAsFixed(2)} ج.م',
                                                style: TextStyle(color: textMuted),
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text('${itemTotal.toStringAsFixed(2)} ج.م', style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 16)),
                                                  const SizedBox(width: 8),
                                                  IconButton(
                                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                                    onPressed: () => _removeFromCart(index),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
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
                const SizedBox(width: 24),

                // Right Column
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: Card(
                      color: cardBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📝 تفاصيل عملية المرتجع والعميل',
                              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const Divider(height: 20),

                            TextField(
                              controller: _customerNameController,
                              style: TextStyle(color: textColor),
                              decoration: const InputDecoration(
                                labelText: 'اسم العميل (اختياري)',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _customerPhoneController,
                              style: TextStyle(color: textColor),
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'رقم هاتف العميل (اختياري)',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _notesController,
                              style: TextStyle(color: textColor),
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'سبب الإرجاع / ملاحظات',
                                prefixIcon: Icon(Icons.edit_note_rounded),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Text(
                              '💵 طريقة رد المبلغ',
                              style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: _paymentMethod,
                              dropdownColor: cardBg,
                              style: TextStyle(color: textColor, fontSize: 16, fontFamily: 'Cairo'),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('💵 نقدي (كاش)')),
                                DropdownMenuItem(value: 'vodafone_cash', child: Text('🔴 فودافون كاش')),
                                DropdownMenuItem(value: 'instapay', child: Text('🟣 InstaPay')),
                                DropdownMenuItem(value: 'visa', child: Text('💳 فيزا')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _paymentMethod = val;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 24),

                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.scaffoldBg(context),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('إجمالي القيمة المستردة:', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text('${_totalRefund.toStringAsFixed(2)} ج.م', style: TextStyle(color: primaryGold, fontSize: 20, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryGold,
                                  foregroundColor: const Color(0xFF1A2A3A),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                onPressed: _isSaving ? null : _completeReturn,
                                icon: _isSaving
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1A2A3A))))
                                    : const Icon(Icons.check_circle_rounded),
                                label: const Text('تأكيد وإتمام المرتجع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnsHistoryTab() {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final cardBg = AppTheme.cardBg(context);
    final primaryGold = const Color(0xFFD4AF37);

    if (_isLoading && _pastReturns.isEmpty) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📜 سجل المرتجعات السابقة',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            'قائمة بعمليات الإرجاع التي تم تسجيلها في النظام واسترداد قيمتها للمشترين',
            style: TextStyle(fontSize: 15, color: textMuted),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: _pastReturns.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_outlined, size: 64, color: textMuted),
                        const SizedBox(height: 16),
                        Text('لا توجد عمليات مرتجع مسجلة مسبقاً', style: TextStyle(color: textMuted, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _pastReturns.length,
                    itemBuilder: (context, index) {
                      final ret = _pastReturns[index];
                      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(ret.returnDate);
                      
                      List<dynamic> itemsList = [];
                      try {
                        itemsList = jsonDecode(ret.itemsJson);
                      } catch (_) {}

                      String refundMethodName = 'كاش';
                      switch (ret.paymentMethod) {
                        case 'cash': refundMethodName = 'نقدي (كاش)'; break;
                        case 'vodafone_cash': refundMethodName = 'فودافون كاش'; break;
                        case 'instapay': refundMethodName = 'InstaPay'; break;
                        case 'visa': refundMethodName = 'فيزا'; break;
                      }

                      return Card(
                        color: cardBg,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ExpansionTile(
                          iconColor: primaryGold,
                          collapsedIconColor: textMuted,
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'مرتجع رقم #${ret.id}  |  $dateStr',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                '${ret.totalAmount.toStringAsFixed(2)} ج.م',
                                style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'العميل: ${ret.customerName ?? "عميل مرتجع"} | طريقة رد المبلغ: $refundMethodName',
                            style: TextStyle(color: textMuted, fontSize: 13),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ret.customerPhone != null && ret.customerPhone!.isNotEmpty) ...[
                                    Text('📞 هاتف العميل: ${ret.customerPhone}', style: TextStyle(color: textColor, fontSize: 14)),
                                    const SizedBox(height: 8),
                                  ],
                                  if (ret.notes != null && ret.notes!.isNotEmpty) ...[
                                    Text('📝 سبب الإرجاع: ${ret.notes}', style: TextStyle(color: textColor, fontSize: 14)),
                                    const SizedBox(height: 8),
                                  ],
                                  const Divider(),
                                  Text(
                                    '📦 الأصناف المرجعة:',
                                    style: TextStyle(color: primaryGold, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  ...itemsList.map((item) {
                                    final type = item['type'] == 'accessory'
                                        ? 'إكسسوار'
                                        : item['type'] == 'device'
                                            ? 'جهاز'
                                            : 'قطعة غيار';
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '• ${item['name']} ($type)',
                                            style: TextStyle(color: textColor, fontSize: 14),
                                          ),
                                          Text(
                                            'الكمية: ${item['quantity']} | سعر الاسترداد: ${item['price']} ج.م',
                                            style: TextStyle(color: textMuted, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ReturnSearchItem {
  final String type; // 'accessory', 'device', 'spare_part'
  final int id;
  final String name;
  final String code;
  final double price;
  final double cost;
  final int quantity;
  final String warehouse;
  final dynamic originalObject;

  ReturnSearchItem({
    required this.type,
    required this.id,
    required this.name,
    required this.code,
    required this.price,
    required this.cost,
    required this.quantity,
    required this.warehouse,
    required this.originalObject,
  });
}

class ReturnCartItem {
  final ReturnSearchItem product;
  int quantity;
  double price; // unit refund price

  ReturnCartItem({
    required this.product,
    required this.quantity,
    required this.price,
  });
}

class CustomReturnInfo {
  final int? categoryId;
  final String? condition;

  CustomReturnInfo({
    this.categoryId,
    this.condition,
  });
}
