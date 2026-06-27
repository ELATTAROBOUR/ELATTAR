// lib/views/goods_receipt_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';

class GoodsReceiptView extends StatefulWidget {
  const GoodsReceiptView({super.key});

  @override
  State<GoodsReceiptView> createState() => _GoodsReceiptViewState();
}

class _GoodsReceiptViewState extends State<GoodsReceiptView> {
  final _formKey = GlobalKey<FormState>();
  final _itemNameController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController(text: '0.0');
  final _priceController = TextEditingController(text: '0.0');
  final _supplierController = TextEditingController();
  final _initialPaymentController = TextEditingController(text: '0.0');
  final _notesController = TextEditingController();

  String _selectedItemType = 'accessory'; // 'spare_part', 'accessory', 'device'
  String _paymentType = 'cash'; // 'cash', 'deferred'
  String _selectedWarehouse = 'المحل الرئيسي';
  DateTime? _dueDate;

  List<Warehouse> _warehouses = [];
  List<GoodsReceipt> _receiptsHistory = [];
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
      _warehouses = await DatabaseHelper.loadWarehouses();
      _receiptsHistory = await DatabaseHelper.loadGoodsReceipts();
      if (_warehouses.isNotEmpty &&
          !_warehouses.any((w) => w.name == _selectedWarehouse)) {
        _selectedWarehouse = _warehouses.first.name;
      }
    } catch (e) {
      debugPrint('Error loading goods receipt data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar', 'EG'),
    );
    if (picked != null) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _submitReceipt() async {
    if (!_formKey.currentState!.validate()) return;

    final itemName = _itemNameController.text.trim();
    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final cost = double.tryParse(_costController.text.trim()) ?? 0.0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final supplierName = _supplierController.text.trim();
    final initialPayment =
        double.tryParse(_initialPaymentController.text.trim()) ?? 0.0;

    if (itemName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ يرجى إدخال اسم الصنف')));
      return;
    }
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠️ يرجى إدخال كمية صحيحة أكبر من الصفر')));
      return;
    }

    final receipt = GoodsReceipt(
      receiptDate: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      itemType: _selectedItemType,
      itemName: itemName,
      quantity: qty,
      cost: cost,
      price: price,
      supplier: supplierName.isEmpty ? null : supplierName,
      warehouse: _selectedWarehouse,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseHelper.saveGoodsReceipt(
        receipt,
        isDeferred: _paymentType == 'deferred',
        initialPayment: initialPayment,
        dueDate: _dueDate != null
            ? DateFormat('yyyy-MM-dd').format(_dueDate!)
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ تم استلام البضائع وتحديث كميات المخزن بنجاح!'),
            backgroundColor: Colors.green),
      );

      // Reset form
      _itemNameController.clear();
      _qtyController.text = '1';
      _costController.text = '0.0';
      _priceController.text = '0.0';
      _supplierController.clear();
      _initialPaymentController.text = '0.0';
      _notesController.clear();
      setState(() {
        _paymentType = 'cash';
        _dueDate = null;
      });

      _loadData();
    } catch (e) {
      debugPrint('Failed to save receipt: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ فشل حفظ التوريد: $e'),
            backgroundColor: Colors.red));
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

    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))))
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Input Form
                Expanded(
                  flex: 3,
                  child: Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '📥 استلام بضاعة جديدة (توريد للمخازن)',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: primaryGold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'تتيح لك هذه الواجهة توريد وتعبئة كميات جديدة من الإكسسوارات أو الأجهزة أو قطع الغيار مباشرة في مخازنك وحساب مديونيات الموردين.',
                                style:
                                    TextStyle(fontSize: 14, color: textMuted),
                              ),
                              const Divider(height: 32),

                              // Item Type
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedItemType,
                                      dropdownColor: cardBg,
                                      style: TextStyle(
                                          color: textColor, fontSize: 16),
                                      decoration: const InputDecoration(
                                          labelText: 'نوع الصنف المورد *'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'accessory',
                                            child: Text('🎧 إكسسوارات')),
                                        DropdownMenuItem(
                                            value: 'device',
                                            child: Text('📱 أجهزة جديدة')),
                                        DropdownMenuItem(
                                            value: 'spare_part',
                                            child: Text('🔧 قطع غيار')),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedItemType = val!;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedWarehouse,
                                      dropdownColor: cardBg,
                                      style: TextStyle(
                                          color: textColor, fontSize: 16),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'مخزن الاستلام المستهدف *'),
                                      items: _warehouses
                                          .map((w) => DropdownMenuItem(
                                              value: w.name,
                                              child: Text(w.name)))
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

                              // Item Name
                              TextField(
                                controller: _itemNameController,
                                style: TextStyle(color: textColor),
                                decoration: const InputDecoration(
                                  labelText: 'اسم الصنف المورد *',
                                  hintText:
                                      'مثال: شاحن أبل 20 واط، iPhone 13 Pro Max، شاشة ايفون 11...',
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Qty, Cost, Price
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _qtyController,
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(color: textColor),
                                      decoration: const InputDecoration(
                                          labelText: 'الكمية الموردة *'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _costController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      style: TextStyle(color: textColor),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'سعر تكلفة القطعة الواحد (ج.م) *'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _priceController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      style: TextStyle(color: textColor),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'سعر بيع القطعة المقترح (ج.م) *'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Supplier Name
                              TextField(
                                controller: _supplierController,
                                style: TextStyle(color: textColor),
                                decoration: const InputDecoration(
                                  labelText:
                                      'اسم المورد (ضروري للتوريد الآجل) *',
                                  hintText: 'اكتب اسم المورد أو جهة التوريد...',
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Payment Type
                              Text('طريقة دفع فاتورة التوريد:',
                                  style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              const SizedBox(height: 8),
                              RadioGroup<String>(
                                groupValue: _paymentType,
                                onChanged: (val) {
                                  if (val == null) return;
                                  setState(() {
                                    _paymentType = val;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: RadioListTile<String>(
                                        title: Text('فوري (كاش)',
                                            style: TextStyle(color: textColor)),
                                        value: 'cash',
                                        activeColor: primaryGold,
                                      ),
                                    ),
                                    Expanded(
                                      child: RadioListTile<String>(
                                        title: Text('آجل (على الحساب)',
                                            style: TextStyle(color: textColor)),
                                        value: 'deferred',
                                        activeColor: primaryGold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Deferred Options
                              if (_paymentType == 'deferred') ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                      color:
                                          primaryGold.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: primaryGold.withValues(
                                              alpha: 0.2))),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _initialPaymentController,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          style: TextStyle(color: textColor),
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'المقدم المدفوع للمورد (ج.م)'),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _dueDate == null
                                                    ? 'لم يتم تحديد تاريخ الاستحقاق'
                                                    : 'تاريخ الاستحقاق: ${DateFormat('yyyy/MM/dd').format(_dueDate!)}',
                                                style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 15),
                                              ),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor: primaryGold,
                                                  foregroundColor:
                                                      const Color(0xFF1A2A3A)),
                                              onPressed: _selectDueDate,
                                              child: const Text('اختر التاريخ'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 32),

                              // Submit button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryGold,
                                      foregroundColor: const Color(0xFF1A2A3A)),
                                  onPressed: _submitReceipt,
                                  icon: const Icon(
                                      Icons.check_circle_outline_rounded),
                                  label: const Text(
                                      'تسجيل التوريد وتحديث المخزن والديون',
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
                ),
                const SizedBox(width: 24),

                // Receipts History
                Expanded(
                  flex: 2,
                  child: Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('📋 أحدث عمليات التوريد المسجلة',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: textColor)),
                              Icon(Icons.history_rounded, color: primaryGold),
                            ],
                          ),
                          const Divider(height: 24),
                          Expanded(
                            child: _receiptsHistory.isEmpty
                                ? Center(
                                    child: Text(
                                        'لا توجد عمليات توريد مسجلة مسبقاً',
                                        style: TextStyle(
                                            color: textMuted, fontSize: 16)))
                                : ListView.separated(
                                    itemCount: _receiptsHistory.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(),
                                    itemBuilder: (context, index) {
                                      final r = _receiptsHistory[index];
                                      String typeBadge = '';
                                      Color badgeColor = Colors.grey;
                                      if (r.itemType == 'accessory') {
                                        typeBadge = 'إكسسوار';
                                        badgeColor = Colors.orange;
                                      } else if (r.itemType == 'device') {
                                        typeBadge = 'جهاز';
                                        badgeColor = Colors.purple;
                                      } else if (r.itemType == 'spare_part') {
                                        typeBadge = 'قطعة غيار';
                                        badgeColor = Colors.blue;
                                      }

                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '${r.itemName} x ${r.quantity}',
                                          style: TextStyle(
                                              color: textColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                        subtitle: Text(
                                          'المورد: ${r.supplier ?? "غير معروف"} | تكلفة: ${r.cost.toStringAsFixed(0)} ج.م | المخزن: ${r.warehouse}',
                                          style: TextStyle(
                                              color: textMuted, fontSize: 13),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                  color: badgeColor.withValues(
                                                      alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              child: Text(typeBadge,
                                                  style: TextStyle(
                                                      color: badgeColor,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              r.receiptDate.split(' ')[0],
                                              style: TextStyle(
                                                  color: textMuted,
                                                  fontSize: 12),
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
          );
  }
}
