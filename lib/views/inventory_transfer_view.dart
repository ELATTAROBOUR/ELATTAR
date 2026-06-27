// lib/views/inventory_transfer_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../printer_settings_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InventoryTransferView extends StatefulWidget {
  const InventoryTransferView({super.key});

  @override
  State<InventoryTransferView> createState() => _InventoryTransferViewState();
}

class _InventoryTransferViewState extends State<InventoryTransferView> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  String _selectedItemType = 'accessory'; // 'accessory', 'device'
  dynamic _selectedItem;
  String _toWarehouse = 'المخزن';

  List<dynamic> _availableItems = [];
  List<Warehouse> _warehouses = [];
  List<InventoryTransfer> _transfersHistory = [];
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
      _transfersHistory = await DatabaseHelper.loadInventoryTransfers();

      // Load stock items with qty > 0
      final accessories = await DatabaseHelper.loadAccessories();
      final devices = await DatabaseHelper.loadDevices();

      _availableItems = [];
      _availableItems.addAll(accessories.where((a) => a.quantity > 0));
      _availableItems.addAll(devices.where((d) => d.quantity > 0));

      _updateDropdownItems();
    } catch (e) {
      debugPrint('Error loading transfer view data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateDropdownItems() {
    final filtered = _availableItems.where((item) {
      if (_selectedItemType == 'accessory' && item is Accessory) return true;
      if (_selectedItemType == 'device' && item is Device) return true;
      return false;
    }).toList();

    setState(() {
      _selectedItem = filtered.isNotEmpty ? filtered.first : null;
      if (_warehouses.isNotEmpty) {
        // Find destination warehouse distinct from source if possible
        String sourceWarehouse = _selectedItem != null
            ? _getSourceWarehouse(_selectedItem)
            : 'المحل الرئيسي';
        final alternate = _warehouses.firstWhere(
            (w) => w.name != sourceWarehouse,
            orElse: () => _warehouses.first);
        _toWarehouse = alternate.name;
      }
    });
  }

  String _getSourceWarehouse(dynamic item) {
    if (item is Accessory) return item.warehouse;
    if (item is Device) return item.warehouse;
    return 'المحل الرئيسي';
  }

  String _getItemName(dynamic item) {
    if (item is Accessory) return item.name;
    if (item is Device) {
      return '${item.model} (${item.condition == 'new' ? 'جديد' : 'مستعمل'})';
    }
    return '';
  }

  int _getItemQuantity(dynamic item) {
    if (item is Accessory) return item.quantity;
    if (item is Device) return item.quantity;
    return 0;
  }

  int _getItemId(dynamic item) {
    if (item is Accessory) return item.id!;
    if (item is Device) return item.id!;
    return 0;
  }

  Future<void> _printTransferNote(InventoryTransfer transfer) async {
    try {
      final config = await PrinterSettingsService.load();
      final printer = await PrinterSettingsService.resolve(
          config.receiptPrinterName, 'طابعة الفواتير');

      final pdfTheme = await printServiceGetArabicTheme();
      final pdf = pw.Document();

      final pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        140 * PdfPageFormat.mm,
        marginLeft: 4 * PdfPageFormat.mm,
        marginRight: 4 * PdfPageFormat.mm,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
      );

      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          theme: pdfTheme,
          build: (pw.Context ctx) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text('محلات العطار استور',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                  pw.Text('إذن تحويل بضاعة داخلي',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                  pw.Text('رقم التحويل: #T-${transfer.id ?? ""}',
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center),
                  pw.Text('التاريخ: $dateStr',
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 6),
                  _receiptRowHelper('الصنف المحول', transfer.itemName),
                  _receiptRowHelper('النوع',
                      transfer.itemType == 'accessory' ? 'إكسسوار' : 'جهاز'),
                  _receiptRowHelper(
                      'الكمية المحولة', transfer.quantity.toString()),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 4),
                  _receiptRowHelper('من مخزن', transfer.fromWarehouse),
                  _receiptRowHelper('إلى مخزن', transfer.toWarehouse),
                  if (transfer.notes != null && transfer.notes!.isNotEmpty)
                    _receiptRowHelper('ملاحظات', transfer.notes!),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 8),
                  pw.Text('توقيع المستلم: .....................',
                      style: const pw.TextStyle(fontSize: 8.5)),
                  pw.SizedBox(height: 12),
                  pw.Text('شكراً لثقتكم بنا - نظام العطار استور',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                  pw.Text('Developed By Eng:BELALZAGHL0L',
                      style: const pw.TextStyle(fontSize: 6),
                      textAlign: pw.TextAlign.center),
                ],
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        format: pageFormat,
      );
    } catch (e) {
      debugPrint('Failed to print transfer note: $e');
    }
  }

  pw.Widget _receiptRowHelper(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('$label:',
              style:
                  pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  static pw.ThemeData? _cachedTheme;
  Future<pw.ThemeData> printServiceGetArabicTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    pw.Font? regular;
    pw.Font? bold;

    if (Platform.isWindows) {
      final regFile = File('C:\\Windows\\Fonts\\tahoma.ttf');
      final boldFile = File('C:\\Windows\\Fonts\\tahomabd.ttf');
      if (regFile.existsSync() && boldFile.existsSync()) {
        try {
          regular = pw.Font.ttf(regFile.readAsBytesSync().buffer.asByteData());
          bold = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        } catch (_) {}
      }
    }
    regular ??= pw.Font.helvetica();
    bold ??= pw.Font.helveticaBold();
    _cachedTheme = pw.ThemeData.withFont(base: regular, bold: bold);
    return _cachedTheme!;
  }

  Future<void> _submitTransfer() async {
    if (_selectedItem == null) return;
    if (!_formKey.currentState!.validate()) return;

    final qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final sourceWarehouse = _getSourceWarehouse(_selectedItem);

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ يرجى إدخال كمية صحيحة')));
      return;
    }

    final availableQty = _getItemQuantity(_selectedItem);
    if (qty > availableQty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '⚠️ الكمية المطلوبة ($qty) أكبر من المتوفر بالمخزن ($availableQty)')));
      return;
    }

    if (sourceWarehouse == _toWarehouse) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('⚠️ لا يمكن التحويل لنفس المخزن الحالي')));
      return;
    }

    final transfer = InventoryTransfer(
      transferDate: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      itemType: _selectedItemType,
      itemName: _getItemName(_selectedItem),
      quantity: qty,
      fromWarehouse: sourceWarehouse,
      toWarehouse: _toWarehouse,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    setState(() {
      _isLoading = true;
    });

    try {
      final id = await DatabaseHelper.saveInventoryTransfer(
          transfer, _getItemId(_selectedItem));
      transfer.id = id;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ تم تحويل الكمية وإصدار إذن التحويل بنجاح!'),
            backgroundColor: Colors.green),
      );

      _notesController.clear();
      _qtyController.text = '1';

      // Print transfer note
      await _printTransferNote(transfer);

      _loadData();
    } catch (e) {
      debugPrint('Failed to save transfer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ فشل إتمام التحويل: $e'),
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

    // List of dropdown items for filtered type
    final typeFilteredItems = _availableItems.where((item) {
      if (_selectedItemType == 'accessory' && item is Accessory) return true;
      if (_selectedItemType == 'device' && item is Device) return true;
      return false;
    }).toList();

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
                                '🔄 تحويل بضاعة بين المخازن (إذن تحويل داخلي)',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: primaryGold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'قم بنقل الهواتف أو الإكسسوارات من فرع إلى فرع أو من المخزن الرئيسي إلى واجهة المحل وطباعة إذن الاستلام.',
                                style:
                                    TextStyle(fontSize: 14, color: textMuted),
                              ),
                              const Divider(height: 32),

                              // Item Type and Item dropdown
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedItemType,
                                      dropdownColor: cardBg,
                                      style: TextStyle(
                                          color: textColor, fontSize: 16),
                                      decoration: const InputDecoration(
                                          labelText: 'نوع الصنف المراد نقله *'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'accessory',
                                            child: Text('🎧 إكسسوارات')),
                                        DropdownMenuItem(
                                            value: 'device',
                                            child: Text('📱 أجهزة')),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedItemType = val!;
                                          _updateDropdownItems();
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: DropdownButtonFormField<dynamic>(
                                      initialValue: _selectedItem,
                                      dropdownColor: cardBg,
                                      style: TextStyle(
                                          color: textColor, fontSize: 15),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'اختر الصنف من المخزون المتوفر *'),
                                      items: typeFilteredItems.map((item) {
                                        final label =
                                            '${_getItemName(item)} (متوفر: ${_getItemQuantity(item)} بـ ${_getSourceWarehouse(item)})';
                                        return DropdownMenuItem(
                                            value: item, child: Text(label));
                                      }).toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedItem = val;
                                          if (_toWarehouse ==
                                              _getSourceWarehouse(
                                                  _selectedItem)) {
                                            // auto adjust to prevent same warehouse transfer
                                            final srcWh = _getSourceWarehouse(
                                                _selectedItem);
                                            final alt = _warehouses.firstWhere(
                                                (w) => w.name != srcWh,
                                                orElse: () =>
                                                    _warehouses.first);
                                            _toWarehouse = alt.name;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Warehouses transfer logic
                              if (_selectedItem != null) ...[
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
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('من المخزن الحالي:',
                                                style: TextStyle(
                                                    color: textMuted,
                                                    fontSize: 13)),
                                            const SizedBox(height: 4),
                                            Text(
                                              _getSourceWarehouse(
                                                  _selectedItem),
                                              style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_rounded,
                                          color: Colors.blueAccent, size: 28),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          initialValue: _toWarehouse,
                                          dropdownColor: cardBg,
                                          style: TextStyle(
                                              color: textColor, fontSize: 16),
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'إلى المخزن المستهدف *'),
                                          items: _warehouses
                                              .map((w) => DropdownMenuItem(
                                                  value: w.name,
                                                  child: Text(w.name)))
                                              .toList(),
                                          onChanged: (val) {
                                            setState(() {
                                              _toWarehouse = val!;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),

                              // Qty & Notes
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _qtyController,
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(color: textColor),
                                      decoration: const InputDecoration(
                                          labelText: 'الكمية المراد نقلها *'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextField(
                                      controller: _notesController,
                                      style: TextStyle(color: textColor),
                                      decoration: const InputDecoration(
                                          labelText:
                                              'ملاحظات التحويل (اختياري)'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),

                              // Submit button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryGold,
                                      foregroundColor: const Color(0xFF1A2A3A)),
                                  onPressed: _selectedItem == null
                                      ? null
                                      : _submitTransfer,
                                  icon: const Icon(Icons.swap_horiz_rounded),
                                  label: const Text(
                                      'تنفيذ التحويل المالي وبدء الطباعة الفورية',
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

                // Transfers History
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
                              Text('📋 سجل أحدث التحويلات الداخلية',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: textColor)),
                              Icon(Icons.history_rounded, color: primaryGold),
                            ],
                          ),
                          const Divider(height: 24),
                          Expanded(
                            child: _transfersHistory.isEmpty
                                ? Center(
                                    child: Text(
                                        'لا توجد عمليات تحويل مسجلة مسبقاً',
                                        style: TextStyle(
                                            color: textMuted, fontSize: 16)))
                                : ListView.separated(
                                    itemCount: _transfersHistory.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(),
                                    itemBuilder: (context, index) {
                                      final t = _transfersHistory[index];
                                      String typeBadge =
                                          t.itemType == 'accessory'
                                              ? 'إكسسوار'
                                              : 'جهاز';
                                      Color badgeColor =
                                          t.itemType == 'accessory'
                                              ? Colors.orange
                                              : Colors.purple;

                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '${t.itemName} x ${t.quantity}',
                                          style: TextStyle(
                                              color: textColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                        ),
                                        subtitle: Text(
                                          'من: ${t.fromWarehouse} ➔ إلى: ${t.toWarehouse}',
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
                                              t.transferDate.split(' ')[0],
                                              style: TextStyle(
                                                  color: textMuted,
                                                  fontSize: 11),
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
