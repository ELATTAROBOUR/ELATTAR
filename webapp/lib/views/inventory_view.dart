// lib/views/inventory_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../platform_stub.dart' if (dart.library.io) 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../printer_settings_service.dart';

class InventoryView extends StatefulWidget {
  const InventoryView({super.key});

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  List<dynamic> _allItems = []; // List of Accessory, Device, and SparePart
  List<dynamic> _filteredItems = [];
  List<Warehouse> _warehouses = [];

  String _searchQuery = '';
  String _selectedWarehouse = 'الكل';
  String _selectedType = 'الكل'; // 'الكل', 'spare_part', 'accessory', 'device'
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
      final accessories = await DatabaseHelper.loadAccessories();
      final devices = await DatabaseHelper.loadDevices();
      final spareParts = await DatabaseHelper.loadSpareParts();
      _warehouses = await DatabaseHelper.loadWarehouses();

      _allItems = [];
      _allItems.addAll(accessories);
      _allItems.addAll(devices);
      _allItems.addAll(spareParts);

      _filterItems();
    } catch (e) {
      debugPrint('Error loading unified inventory: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredItems = _allItems.where((item) {
        String name = '';
        String type = '';
        String warehouse = 'المحل الرئيسي'; // Spare parts defaults to main
        String code = '';

        if (item is Accessory) {
          name = item.name;
          type = 'accessory';
          warehouse = item.warehouse;
          code = item.code ?? '';
        } else if (item is Device) {
          name =
              '${item.model} (${item.condition == 'new' ? 'جديد' : 'مستعمل'})';
          type = 'device';
          warehouse = item.warehouse;
          code = '${item.code ?? ''} ${item.imei}';
        } else if (item is SparePart) {
          name = item.name;
          type = 'spare_part';
          warehouse = 'المحل الرئيسي'; // Spare parts are global
        }

        final matchesSearch =
            name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            code.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesWarehouse =
            _selectedWarehouse == 'الكل' || warehouse == _selectedWarehouse;
        final matchesType = _selectedType == 'الكل' || type == _selectedType;

        return matchesSearch && matchesWarehouse && matchesType;
      }).toList();
    });
  }

  String _getItemTypeArabic(dynamic item) {
    if (item is Accessory) return 'إكسسوار';
    if (item is Device) return 'جهاز';
    if (item is SparePart) return 'قطعة غيار';
    return 'غير معروف';
  }

  double _getItemCost(dynamic item) {
    if (item is Accessory) return item.cost;
    if (item is Device) return item.cost;
    if (item is SparePart) {
      return 0.0; // Cost is not saved in spare_part originally
    }
    return 0.0;
  }

  double _getItemPrice(dynamic item) {
    if (item is Accessory) return item.price;
    if (item is Device) return item.price;
    if (item is SparePart) return item.price;
    return 0.0;
  }

  int _getItemQuantity(dynamic item) {
    if (item is Accessory) return item.quantity;
    if (item is Device) return item.quantity;
    if (item is SparePart) return item.quantity;
    return 0;
  }

  String _getItemWarehouse(dynamic item) {
    if (item is Accessory) return item.warehouse;
    if (item is Device) return item.warehouse;
    if (item is SparePart) return 'المحل الرئيسي';
    return 'غير محدد';
  }

  void _showWarehouseDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textColor = AppTheme.text(context);
          final primaryGold = const Color(0xFFD4AF37);

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '🏢 إدارة المخازن والفروع',
              style: TextStyle(
                color: primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            content: SizedBox(
              width: 400,
              height: 350,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          style: TextStyle(color: textColor),
                          decoration: const InputDecoration(
                            labelText: 'اسم المخزن الجديد',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGold,
                          foregroundColor: const Color(0xFF1A2A3A),
                        ),
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) return;
                          await DatabaseHelper.addWarehouse(
                            nameController.text.trim(),
                          );
                          nameController.clear();
                          final updated = await DatabaseHelper.loadWarehouses();
                          setDialogState(() {
                            _warehouses = updated;
                          });
                          _loadData();
                        },
                        child: const Text('إضافة'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _warehouses.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final w = _warehouses[index];
                        return ListTile(
                          title: Text(
                            w.name,
                            style: TextStyle(color: textColor, fontSize: 16),
                          ),
                          trailing:
                              w.name == 'المحل الرئيسي' || w.name == 'المخزن'
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'أساسي',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.delete_forever,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    if (w.id != null) {
                                      await DatabaseHelper.deleteWarehouse(
                                        w.id!,
                                      );
                                      final updated =
                                          await DatabaseHelper.loadWarehouses();
                                      setDialogState(() {
                                        _warehouses = updated;
                                      });
                                      _loadData();
                                    }
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إغلاق',
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAuditDialog() {
    String selectedType = 'accessory';
    dynamic selectedItem;
    List<dynamic> itemsOfType = [];
    final actualQtyController = TextEditingController();
    final auditorController = TextEditingController();
    final notesController = TextEditingController();

    void updateItemsList(String type, Function setDialogState) {
      setDialogState(() {
        if (type == 'accessory') {
          itemsOfType = _allItems.whereType<Accessory>().toList();
        } else if (type == 'device') {
          itemsOfType = _allItems.whereType<Device>().toList();
        } else if (type == 'spare_part') {
          itemsOfType = _allItems.whereType<SparePart>().toList();
        }
        selectedItem = itemsOfType.isNotEmpty ? itemsOfType.first : null;
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textColor = AppTheme.text(context);
          final primaryGold = const Color(0xFFD4AF37);

          if (itemsOfType.isEmpty) {
            updateItemsList(selectedType, setDialogState);
          }

          int expectedQty = 0;
          if (selectedItem != null) {
            expectedQty = _getItemQuantity(selectedItem);
          }

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '📊 بدء جرد المخزن المادي',
              style: TextStyle(
                color: primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type selector
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'نوع الصنف *',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'accessory',
                          child: Text('إكسسوار'),
                        ),
                        DropdownMenuItem(value: 'device', child: Text('جهاز')),
                        DropdownMenuItem(
                          value: 'spare_part',
                          child: Text('قطعة غيار'),
                        ),
                      ],
                      onChanged: (val) {
                        selectedType = val!;
                        updateItemsList(selectedType, setDialogState);
                      },
                    ),
                    const SizedBox(height: 16),
                    // Item selector
                    DropdownButtonFormField<dynamic>(
                      initialValue: selectedItem,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 15),
                      decoration: const InputDecoration(
                        labelText: 'اختر الصنف *',
                      ),
                      items: itemsOfType.map((item) {
                        String label = '';
                        if (item is Accessory) {
                          label = '${item.name} (${item.warehouse})';
                        }
                        if (item is Device) {
                          label =
                              '${item.model} (${item.condition == 'new' ? 'جديد' : 'مستعمل'})';
                        }
                        if (item is SparePart) label = item.name;
                        return DropdownMenuItem(
                          value: item,
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedItem = val;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    // Quantities info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الكمية المسجلة بالنظام:',
                            style: TextStyle(
                              color: AppTheme.textMuted(context),
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            expectedQty.toString(),
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Actual qty input
                    TextField(
                      controller: actualQtyController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(
                        labelText: 'الكمية الفعلية المكتشفة بالجرد *',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: auditorController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(
                        labelText: 'اسم الشخص القائم بالجرد',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات الجرد (اختياري)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إلغاء',
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 16,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                ),
                onPressed: () async {
                  if (selectedItem == null ||
                      actualQtyController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ يرجى تعبئة كافة الحقول المطلوبة'),
                      ),
                    );
                    return;
                  }

                  final actualQty =
                      int.tryParse(actualQtyController.text.trim()) ?? 0;
                  final diff = actualQty - expectedQty;

                  String itemName = '';
                  if (selectedItem is Accessory) itemName = selectedItem.name;
                  if (selectedItem is Device) itemName = selectedItem.model;
                  if (selectedItem is SparePart) itemName = selectedItem.name;

                  final auditRecord = InventoryAudit(
                    auditDate: DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(DateTime.now()),
                    itemType: selectedType,
                    itemName: itemName,
                    expectedQty: expectedQty,
                    actualQty: actualQty,
                    difference: diff,
                    auditor: auditorController.text.trim().isEmpty
                        ? 'غير معروف'
                        : auditorController.text.trim(),
                    notes: notesController.text.trim(),
                  );

                  await DatabaseHelper.saveInventoryAudit(auditRecord);
                  if (context.mounted) {
                    Navigator.pop(context);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✅ تم حفظ الجرد وتحديث المخزن. الفرق: $diff',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text(
                  'حفظ وتحديث المخزن',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printInventoryReport() async {
    try {
      final config = await PrinterSettingsService.load();
      final printer = await PrinterSettingsService.resolve(
        config.receiptPrinterName,
        'طابعة الفواتير',
      );

      final pdfTheme = await printServiceGetArabicTheme();
      final pdf = pw.Document();

      // Dynamic height
      final double estimatedHeightMm = 50.0 + (_filteredItems.length * 8.0);
      final pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        estimatedHeightMm * PdfPageFormat.mm,
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
                  pw.Text(
                    'محلات العطار استور',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'تقرير كشف جرد بضاعة المخزن',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'تاريخ الجرد: $dateStr',
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 4),

                  // Table Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          'اسم الصنف',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          'النوع',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 1,
                        child: pw.Text(
                          'الكمية',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          'المخزن',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 0.5),

                  // Rows
                  ..._filteredItems.map((item) {
                    String name = '';
                    String type = '';
                    String wh = '';
                    int qty = 0;

                    if (item is Accessory) {
                      name = item.name;
                      type = 'إكسسوار';
                      wh = item.warehouse;
                      qty = item.quantity;
                    } else if (item is Device) {
                      name = item.model;
                      type = 'جهاز';
                      wh = item.warehouse;
                      qty = item.quantity;
                    } else if (item is SparePart) {
                      name = item.name;
                      type = 'قطع غيار';
                      wh = 'المحل';
                      qty = item.quantity;
                    }

                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              name,
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Text(
                              type,
                              style: const pw.TextStyle(fontSize: 7.5),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Text(
                              qty.toString(),
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              wh,
                              style: const pw.TextStyle(fontSize: 7.5),
                              textAlign: pw.TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'العطار استور - نظام جرد البضائع الذكي',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'Developed By Eng:BELALZAGHL0L',
                    style: const pw.TextStyle(fontSize: 6),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final result = await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        format: pageFormat,
      );

      if (result) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إرسال كشف الجرد للطابعة بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Direct print returned false.');
      }
    } catch (e) {
      debugPrint('Failed to print inventory count: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ فشل طباعة كشف الجرد: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Duplicate getArabicTheme locally to avoid complex imports
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
                    '📦 جرد وحالة بضائع المخازن',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'عرض موحد وشامل لكل الأصناف (أجهزة، إكسسوارات، قطع غيار)، وعمل الجرد الدوري وإدارة المخازن',
                    style: TextStyle(fontSize: 15, color: textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _showWarehouseDialog,
                    icon: const Icon(Icons.storefront_rounded, size: 20),
                    label: const Text(
                      'إدارة المخازن',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGold,
                      foregroundColor: const Color(0xFF1A2A3A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _showAuditDialog,
                    icon: const Icon(Icons.inventory_rounded, size: 20),
                    label: const Text(
                      'بدء عملية الجرد',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _printInventoryReport,
                    icon: const Icon(Icons.print, size: 20),
                    label: const Text(
                      'طباعة الجرد',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Card
          Card(
            color: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'البحث باسم الصنف أو الموديل...',
                        prefixIcon: Icon(Icons.search, color: primaryGold),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
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
                    child: DropdownButton<String>(
                      value: _selectedType,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontFamily: 'Cairo',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'الكل',
                          child: Text('جميع الأنواع'),
                        ),
                        DropdownMenuItem(
                          value: 'accessory',
                          child: Text('إكسسوارات'),
                        ),
                        DropdownMenuItem(value: 'device', child: Text('أجهزة')),
                        DropdownMenuItem(
                          value: 'spare_part',
                          child: Text('قطع غيار'),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedType = val!;
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
                        color: textColor,
                        fontSize: 16,
                        fontFamily: 'Cairo',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'الكل',
                          child: Text('كل المخازن'),
                        ),
                        ..._warehouses.map(
                          (w) => DropdownMenuItem(
                            value: w.name,
                            child: Text(w.name),
                          ),
                        ),
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

          // Inventory Table
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFD4AF37),
                      ),
                    ),
                  )
                : _filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد أصناف في المخزن مطابقة للتصفية الحالية',
                          style: TextStyle(fontSize: 18, color: textMuted),
                        ),
                      ],
                    ),
                  )
                : Card(
                    color: AppTheme.cardBg(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: DataTable(
                        headingTextStyle: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: primaryGold,
                          fontSize: 16,
                        ),
                        dataTextStyle: TextStyle(
                          fontFamily: 'Cairo',
                          color: textColor,
                          fontSize: 15,
                        ),
                        columns: const [
                          DataColumn(label: Text('الاسم / الصنف')),
                          DataColumn(label: Text('الكود / الباركود')),
                          DataColumn(label: Text('النوع')),
                          DataColumn(label: Text('الكمية المتاحة')),
                          DataColumn(label: Text('سعر الشراء')),
                          DataColumn(label: Text('سعر البيع')),
                          DataColumn(label: Text('المخزن الحالي')),
                        ],
                        rows: _filteredItems.map((item) {
                          String name = '';
                          if (item is Accessory) {
                            name = item.name;
                          }
                          if (item is Device) {
                            name =
                                '${item.model} (${item.condition == 'new' ? 'جديد' : 'مستعمل'})';
                          }
                          if (item is SparePart) name = item.name;

                          final qty = _getItemQuantity(item);

                          String displayCode = '-';
                          if (item is Accessory) {
                            displayCode = item.code ?? '-';
                          }
                          if (item is Device) {
                            final parts = <String>[];
                            if (item.code != null && item.code!.isNotEmpty) {
                              parts.add(item.code!);
                            }
                            if (item.imei.isNotEmpty) parts.add(item.imei);
                            displayCode = parts.isNotEmpty
                                ? parts.join(' / ')
                                : '-';
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  displayCode,
                                  style: TextStyle(
                                    color: displayCode != '-'
                                        ? textColor
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getItemTypeBadgeColor(
                                      item,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _getItemTypeArabic(item),
                                    style: TextStyle(
                                      color: _getItemTypeBadgeColor(item),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  qty.toString(),
                                  style: TextStyle(
                                    color: qty < 3
                                        ? Colors.redAccent
                                        : textColor,
                                    fontWeight: qty < 3
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${_getItemCost(item).toStringAsFixed(2)} ج.م',
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${_getItemPrice(item).toStringAsFixed(2)} ج.م',
                                ),
                              ),
                              DataCell(Text(_getItemWarehouse(item))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _getItemTypeBadgeColor(dynamic item) {
    if (item is Accessory) return Colors.orange;
    if (item is Device) return Colors.purple;
    if (item is SparePart) return Colors.blue;
    return Colors.grey;
  }
}
