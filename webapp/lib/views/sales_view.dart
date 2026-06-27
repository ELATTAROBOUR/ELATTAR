// lib/views/sales_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../print_service.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/custom_toast.dart';

class SalesView extends StatefulWidget {
  const SalesView({super.key});

  @override
  State<SalesView> createState() => _SalesViewState();
}

class _SalesViewState extends State<SalesView> {
  bool _isLoading = true;
  List<SaleSearchItem> _inventoryItems = [];
  final List<CartItem> _cart = [];

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  // State variables for adding a product
  SaleSearchItem? _selectedItem;
  final TextEditingController _addQtyController =
      TextEditingController(text: '1');
  final TextEditingController _addPriceController = TextEditingController();

  String _paymentMethod = 'cash';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _discountController.dispose();
    _addQtyController.dispose();
    _addPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final accessories = await DatabaseHelper.loadAccessories();
      final devices = await DatabaseHelper.loadDevices();
      final spareParts = await DatabaseHelper.loadSpareParts();

      final List<SaleSearchItem> items = [];

      for (var acc in accessories) {
        items.add(SaleSearchItem(
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
        items.add(SaleSearchItem(
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
        items.add(SaleSearchItem(
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
      debugPrint('Error loading sales inventory: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectProduct(SaleSearchItem item) {
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
      CustomToast.show(context,
          message: '⚠️ يرجى إدخال كمية صحيحة', type: ToastType.warning);
      return;
    }

    if (qty > _selectedItem!.quantity) {
      CustomToast.show(context,
          message:
              '⚠️ الكمية المدخلة أكبر من المتاحة في المخزن (${_selectedItem!.quantity})',
          type: ToastType.error);
      return;
    }

    // Check if item already exists in cart
    final existingIndex = _cart.indexWhere((cartItem) =>
        cartItem.product.type == _selectedItem!.type &&
        cartItem.product.id == _selectedItem!.id);

    if (existingIndex != -1) {
      final totalNewQty = _cart[existingIndex].quantity + qty;
      if (totalNewQty > _selectedItem!.quantity) {
        CustomToast.show(context,
            message:
                '⚠️ إجمالي الكمية بالسلة يتجاوز المتاح بمخزنك (${_selectedItem!.quantity})',
            type: ToastType.error);
        return;
      }
      setState(() {
        _cart[existingIndex].quantity = totalNewQty;
        _cart[existingIndex].price = price; // Update to latest price
      });
    } else {
      setState(() {
        _cart.add(CartItem(
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

    CustomToast.show(context,
        message: '🛒 تم إضافة المنتج إلى السلة بنجاح', type: ToastType.success);
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  double get _subtotal =>
      _cart.fold(0.0, (sum, item) => sum + (item.quantity * item.price));

  double get _discount {
    return double.tryParse(_discountController.text) ?? 0.0;
  }

  double get _total => (_subtotal - _discount).clamp(0.0, 99999999.0);

  Future<void> _completeSale(bool shouldPrint) async {
    if (_cart.isEmpty) {
      CustomToast.show(context,
          message: '⚠️ سلة المبيعات فارغة! يرجى إضافة منتجات أولاً',
          type: ToastType.warning);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // 1. Decrement Stock Quantities
      for (var item in _cart) {
        final prod = item.product;
        final int qtyToSell = item.quantity;

        if (prod.type == 'accessory') {
          final acc = prod.originalObject as Accessory;
          acc.quantity = (acc.quantity - qtyToSell).clamp(0, 999999);
          await DatabaseHelper.saveAccessory(acc);
        } else if (prod.type == 'device') {
          final dev = prod.originalObject as Device;
          dev.quantity = (dev.quantity - qtyToSell).clamp(0, 999999);
          await DatabaseHelper.saveDevice(dev);
        } else if (prod.type == 'spare_part') {
          final part = prod.originalObject as SparePart;
          part.quantity = (part.quantity - qtyToSell).clamp(0, 999999);
          await DatabaseHelper.saveSparePart(part);
        }
      }

      // 2. Prepare items JSON payload for database
      final List<Map<String, dynamic>> itemsPayload = _cart.map((item) {
        return {
          'type': item.product.type,
          'id': item.product.id,
          'name': item.product.name,
          'quantity': item.quantity,
          'price': item.price,
        };
      }).toList();

      final newSale = Sale(
        saleDate: DateTime.now(),
        customerName: _customerNameController.text.trim().isEmpty
            ? null
            : _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim().isEmpty
            ? null
            : _customerPhoneController.text.trim(),
        totalAmount: _subtotal,
        discount: _discount,
        finalAmount: _total,
        paymentMethod: _paymentMethod,
        itemsJson: jsonEncode(itemsPayload),
      );

      // 3. Save Sale Transaction to SQLite
      final int saleId = await DatabaseHelper.saveSale(newSale);
      newSale.id = saleId;

      // 4. Print sales receipt if requested
      if (shouldPrint) {
        try {
          await PrintService.printSalesReceipt(newSale);
        } catch (printErr) {
          debugPrint('Printing error: $printErr');
          if (mounted) {
            CustomToast.show(context,
                message:
                    '⚠️ تم تسجيل البيع ولكن تعذر الاتصال بالطابعة: $printErr',
                type: ToastType.error);
          }
        }
      }

      // 5. Success UI state updates
      if (mounted) {
        CustomToast.show(context,
            message: '✅ تم تسجيل عملية البيع بنجاح وتحديث كميات المخزن',
            type: ToastType.success);

        setState(() {
          _cart.clear();
          _customerNameController.clear();
          _customerPhoneController.clear();
          _discountController.clear();
          _selectedItem = null;
        });

        // Reload fresh stock inventory list
        await _loadInventory();
      }
    } catch (e) {
      debugPrint('Error saving sale: $e');
      if (mounted) {
        CustomToast.show(context,
            message: '❌ حدث خطأ أثناء إتمام عملية البيع: $e',
            type: ToastType.error);
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
    final textMuted = AppTheme.textMuted(context);
    final cardBg = AppTheme.cardBg(context);
    final primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: _isLoading
          ? SkeletonLoading.dashboardPage(context)
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.point_of_sale_rounded,
                            color: primaryGold, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💵 بيع منتج من المحل',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: textColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'اختر المنتجات من المخزن أو قطع الغيار لبيعها وتحديث الرصيد وطباعة فاتورة العميل',
                            style: TextStyle(fontSize: 15, color: textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Product Selection & Cart Summary
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Search Box
                              Card(
                                color: cardBg,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 8.0),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return Autocomplete<SaleSearchItem>(
                                        optionsBuilder: (TextEditingValue
                                            textEditingValue) {
                                          if (textEditingValue.text.isEmpty) {
                                            return const Iterable<
                                                SaleSearchItem>.empty();
                                          }
                                          final query = textEditingValue.text
                                              .trim()
                                              .toLowerCase();
                                          return _inventoryItems.where((item) {
                                            return item.name
                                                    .toLowerCase()
                                                    .contains(query) ||
                                                item.code
                                                    .toLowerCase()
                                                    .contains(query);
                                          });
                                        },
                                        displayStringForOption:
                                            (SaleSearchItem option) =>
                                                option.name,
                                        fieldViewBuilder: (context,
                                            textController,
                                            focusNode,
                                            onFieldSubmitted) {
                                          return TextField(
                                            controller: textController,
                                            focusNode: focusNode,
                                            style: TextStyle(
                                                color: textColor, fontSize: 16),
                                            decoration: InputDecoration(
                                              hintText:
                                                  'ابحث باسم المنتج، كود القطعة، الباركود أو IMEI للجهاز...',
                                              prefixIcon: Icon(Icons.search,
                                                  color: primaryGold),
                                              border: InputBorder.none,
                                              filled: false,
                                            ),
                                          );
                                        },
                                        optionsViewBuilder:
                                            (context, onSelected, options) {
                                          return Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                              color: cardBg,
                                              elevation: 4.0,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              child: SizedBox(
                                                width: constraints.maxWidth,
                                                height: 300,
                                                child: ListView.builder(
                                                  padding: EdgeInsets.zero,
                                                  itemCount: options.length,
                                                  itemBuilder:
                                                      (context, index) {
                                                    final item = options
                                                        .elementAt(index);
                                                    final category = item
                                                                .type ==
                                                            'accessory'
                                                        ? '🎧 إكسسوار'
                                                        : item.type == 'device'
                                                            ? '📱 جهاز'
                                                            : '🔧 قطعة غيار';
                                                    return ListTile(
                                                      title: Text(item.name,
                                                          style: TextStyle(
                                                              color: textColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                      subtitle: Text(
                                                        'النوع: $category | كود: ${item.code.isEmpty ? "لا يوجد" : item.code} | متاح: ${item.quantity} | المخزن: ${item.warehouse}',
                                                        style: TextStyle(
                                                            color: textMuted,
                                                            fontSize: 12),
                                                      ),
                                                      trailing: Text(
                                                          '${item.price.toStringAsFixed(2)} ج.م',
                                                          style: TextStyle(
                                                              color:
                                                                  primaryGold,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                      onTap: () =>
                                                          onSelected(item),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        onSelected: (SaleSearchItem selection) {
                                          _selectProduct(selection);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 2. Selected Item Details Form
                              if (_selectedItem != null) ...[
                                Card(
                                  color: cardBg,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                          color: primaryGold.withValues(
                                              alpha: 0.5))),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '📌 المنتج المحدد: ${_selectedItem!.name}',
                                              style: TextStyle(
                                                  color: textColor,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.clear,
                                                  color: Colors.redAccent),
                                              onPressed: () => setState(
                                                  () => _selectedItem = null),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'المخزن: ${_selectedItem!.warehouse}  |  المخزون المتوفر: ${_selectedItem!.quantity}  |  سعر البيع الافتراضي: ${_selectedItem!.price.toStringAsFixed(2)} ج.م',
                                          style: TextStyle(
                                              color: textMuted, fontSize: 14),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _addQtyController,
                                                keyboardType:
                                                    TextInputType.number,
                                                style:
                                                    TextStyle(color: textColor),
                                                decoration:
                                                    const InputDecoration(
                                                  labelText:
                                                      'الكمية المطلوبة للبيع',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: TextField(
                                                controller: _addPriceController,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                style:
                                                    TextStyle(color: textColor),
                                                decoration:
                                                    const InputDecoration(
                                                  labelText:
                                                      'سعر بيع القطعة (ج.م)',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: primaryGold,
                                                foregroundColor:
                                                    const Color(0xFF1A2A3A),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 20,
                                                        vertical: 14),
                                              ),
                                              onPressed: _addToCart,
                                              icon: const Icon(Icons
                                                  .add_shopping_cart_rounded),
                                              label: const Text('إضافة للسلة'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // 3. Cart Summary
                              Expanded(
                                child: Card(
                                  color: cardBg,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '🛒 سلة المبيعات الحالية',
                                              style: TextStyle(
                                                  color: textColor,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            if (_cart.isNotEmpty)
                                              TextButton.icon(
                                                onPressed: () => setState(
                                                    () => _cart.clear()),
                                                icon: const Icon(
                                                    Icons.delete_sweep,
                                                    color: Colors.redAccent),
                                                label: const Text('تفريغ السلة',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.redAccent)),
                                              ),
                                          ],
                                        ),
                                        const Divider(height: 20),
                                        Expanded(
                                          child: _cart.isEmpty
                                              ? Center(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                          Icons
                                                              .shopping_cart_outlined,
                                                          size: 64,
                                                          color: textMuted),
                                                      const SizedBox(
                                                          height: 16),
                                                      Text(
                                                          'السلة فارغة، قم بالبحث وإضافة منتجات للبدء بالبيع',
                                                          style: TextStyle(
                                                              color: textMuted,
                                                              fontSize: 16)),
                                                    ],
                                                  ),
                                                )
                                              : ListView.builder(
                                                  itemCount: _cart.length,
                                                  itemBuilder:
                                                      (context, index) {
                                                    final item = _cart[index];
                                                    final itemTotal =
                                                        item.quantity *
                                                            item.price;
                                                    final category = item
                                                                .product.type ==
                                                            'accessory'
                                                        ? 'إكسسوار'
                                                        : item.product.type ==
                                                                'device'
                                                            ? 'جهاز'
                                                            : 'قطعة غيار';
                                                    return ListTile(
                                                      title: Text(
                                                          item.product.name,
                                                          style: TextStyle(
                                                              color: textColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                      subtitle: Text(
                                                        'النوع: $category | الكمية: ${item.quantity} | سعر القطعة: ${item.price.toStringAsFixed(2)} ج.م',
                                                        style: TextStyle(
                                                            color: textMuted),
                                                      ),
                                                      trailing: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                              '${itemTotal.toStringAsFixed(2)} ج.م',
                                                              style: TextStyle(
                                                                  color:
                                                                      primaryGold,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      16)),
                                                          const SizedBox(
                                                              width: 8),
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons
                                                                    .remove_circle_outline,
                                                                color: Colors
                                                                    .redAccent),
                                                            onPressed: () =>
                                                                _removeFromCart(
                                                                    index),
                                                            tooltip:
                                                                'حذف من السلة',
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

                        // Right Column: Customer Details, Totals & Checkout
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            child: Card(
                              color: cardBg,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '📝 بيانات العميل والبيع',
                                      style: TextStyle(
                                          color: textColor,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const Divider(height: 20),

                                    // Customer Inputs
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
                                      controller: _discountController,
                                      style: TextStyle(color: textColor),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                        labelText:
                                            'قيمة الخصم الكلي للفاتورة (ج.م)',
                                        prefixIcon:
                                            Icon(Icons.discount_outlined),
                                      ),
                                      onChanged: (_) {
                                        setState(() {}); // Recalculate totals
                                      },
                                    ),
                                    const SizedBox(height: 20),

                                    // Payment Method selection
                                    Text(
                                      '💳 طريقة الدفع',
                                      style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String>(
                                      initialValue: _paymentMethod,
                                      dropdownColor: cardBg,
                                      style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                          fontFamily: 'Cairo'),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'cash',
                                            child: Text('💵 نقدي (كاش)')),
                                        DropdownMenuItem(
                                            value: 'vodafone_cash',
                                            child: Text('🔴 فودافون كاش')),
                                        DropdownMenuItem(
                                            value: 'instapay',
                                            child: Text('🟣 InstaPay')),
                                        DropdownMenuItem(
                                            value: 'visa',
                                            child: Text('💳 فيزا')),
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

                                    // Subtotal, Discount & Final Total Cards
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.scaffoldBg(context),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('المجموع الفرعي:',
                                                  style: TextStyle(
                                                      color: textMuted,
                                                      fontSize: 15)),
                                              Text(
                                                  '${_subtotal.toStringAsFixed(2)} ج.م',
                                                  style: TextStyle(
                                                      color: textColor,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                          if (_discount > 0) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                const Text('قيمة الخصم:',
                                                    style: TextStyle(
                                                        color: Colors.redAccent,
                                                        fontSize: 15)),
                                                Text(
                                                    '- ${_discount.toStringAsFixed(2)} ج.م',
                                                    style: const TextStyle(
                                                        color: Colors.redAccent,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ],
                                            ),
                                          ],
                                          const Divider(
                                              height: 20, thickness: 1),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('الإجمالي النهائي:',
                                                  style: TextStyle(
                                                      color: textColor,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              Text(
                                                  '${_total.toStringAsFixed(2)} ج.م',
                                                  style: TextStyle(
                                                      color: primaryGold,
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // Action Buttons
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryGold,
                                          foregroundColor:
                                              const Color(0xFF1A2A3A),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                        ),
                                        onPressed: _isSaving
                                            ? null
                                            : () => _completeSale(true),
                                        icon: _isSaving
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                                Color>(
                                                            Color(0xFF1A2A3A))))
                                            : const Icon(Icons.print_rounded),
                                        label: const Text(
                                            'إتمام البيع وطباعة الفاتورة',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: primaryGold,
                                          side: BorderSide(
                                              color: primaryGold, width: 1.5),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                        ),
                                        onPressed: _isSaving
                                            ? null
                                            : () => _completeSale(false),
                                        icon: const Icon(
                                            Icons.check_circle_outline_rounded),
                                        label: const Text(
                                            'إتمام البيع بدون طباعة',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)),
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
            ),
    );
  }
}

// Helper classes to represent items in checkout
class SaleSearchItem {
  final String type; // 'accessory', 'device', 'spare_part'
  final int id;
  final String name;
  final String code;
  final double price;
  final double cost;
  final int quantity;
  final String warehouse;
  final dynamic originalObject; // Accessory, Device, or SparePart

  SaleSearchItem({
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

class CartItem {
  final SaleSearchItem product;
  int quantity;
  double price; // unit selling price (overridable)

  CartItem({
    required this.product,
    required this.quantity,
    required this.price,
  });
}
