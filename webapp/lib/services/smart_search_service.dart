// lib/services/smart_search_service.dart
// Smart Search – searches all entities and groups results by type

import 'dart:async';
import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Data model for a single search result
// ─────────────────────────────────────────────────────────────────────────────

enum SearchEntityType {
  ticket,
  accessory,
  device,
  sparePart,
  supplier,
  deferredPayment,
  sale,
  return_,
}

class SmartSearchResult {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final SearchEntityType entityType;
  final int itemId;
  final String? menuTitle;

  SmartSearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.entityType,
    required this.itemId,
    this.menuTitle,
  });

  /// Human-readable Arabic name for the entity type
  String get typeLabel {
    switch (entityType) {
      case SearchEntityType.ticket:
        return 'تذكرة صيانة';
      case SearchEntityType.accessory:
        return 'إكسسوار';
      case SearchEntityType.device:
        return 'جهاز';
      case SearchEntityType.sparePart:
        return 'قطعة غيار';
      case SearchEntityType.supplier:
        return 'مورد';
      case SearchEntityType.deferredPayment:
        return 'حساب آجل';
      case SearchEntityType.sale:
        return 'فاتورة بيع';
      case SearchEntityType.return_:
        return 'مرتجع';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Cached data loaded once per search session
// ─────────────────────────────────────────────────────────────────────────────

class _SearchCache {
  List<Ticket>? tickets;
  List<Accessory>? accessories;
  List<Device>? devices;
  List<SparePart>? spareParts;
  List<Supplier>? suppliers;
  List<DeferredPayment>? deferredPayments;
  List<Sale>? sales;
  List<ReturnTransaction>? returns;
}

// ─────────────────────────────────────────────────────────────────────────────
//  The search service
// ─────────────────────────────────────────────────────────────────────────────

class SmartSearchService {
  SmartSearchService._();

  static final _cache = _SearchCache();
  static bool _isLoading = false;

  /// Load all data into the cache (called once when the dialog opens)
  static Future<void> loadAll() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      await Future.wait([
        DatabaseHelper.loadTickets().then((v) => _cache.tickets = v),
        DatabaseHelper.loadAccessories().then((v) => _cache.accessories = v),
        DatabaseHelper.loadDevices().then((v) => _cache.devices = v),
        DatabaseHelper.loadSpareParts().then((v) => _cache.spareParts = v),
        DatabaseHelper.loadSuppliers().then((v) => _cache.suppliers = v),
        DatabaseHelper.loadDeferredPayments()
            .then((v) => _cache.deferredPayments = v),
        DatabaseHelper.loadSales().then((v) => _cache.sales = v),
        DatabaseHelper.loadReturns().then((v) => _cache.returns = v),
      ]);
    } finally {
      _isLoading = false;
    }
  }

  /// Clear cached data (called when dialog closes)
  static void clearCache() {
    _cache.tickets = null;
    _cache.accessories = null;
    _cache.devices = null;
    _cache.spareParts = null;
    _cache.suppliers = null;
    _cache.deferredPayments = null;
    _cache.sales = null;
    _cache.returns = null;
  }

  /// Perform a fuzzy search over the cached data.
  /// Returns results sorted by relevance.
  static List<SmartSearchResult> search(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();

    final List<SmartSearchResult> results = [];

    // 1. Tickets
    if (_cache.tickets != null) {
      for (final t in _cache.tickets!) {
        if (_matches(q, [
          t.customerName,
          t.customerPhone,
          t.deviceModel,
          t.problem,
          t.technicianName ?? '',
          t.notes,
        ])) {
          results.add(SmartSearchResult(
            title: '#${t.id} - ${t.customerName}',
            subtitle: '${t.deviceModel} | ${t.status} | ${t.customerPhone}',
            icon: Icons.build_circle_outlined,
            iconColor: Colors.orange[700]!,
            entityType: SearchEntityType.ticket,
            itemId: t.id ?? 0,
            menuTitle: '🔧 الصيانة والإصلاحات',
          ));
        }
      }
    }

    // 2. Accessories
    if (_cache.accessories != null) {
      for (final a in _cache.accessories!) {
        if (_matches(q, [
          a.name,
          a.supplier ?? '',
          a.warehouse,
          a.code ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: a.name,
            subtitle:
                'متوفر: ${a.quantity} | السعر: ${a.price} | ${a.supplier ?? ''}',
            icon: Icons.headset_outlined,
            iconColor: Colors.teal[700]!,
            entityType: SearchEntityType.accessory,
            itemId: a.id ?? 0,
            menuTitle: '🎧 إدارة الاكسسوارات',
          ));
        }
      }
    }

    // 3. Devices
    if (_cache.devices != null) {
      for (final d in _cache.devices!) {
        if (_matches(q, [
          d.model,
          d.imei,
          d.supplier ?? '',
          d.warehouse,
          d.code ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: d.model,
            subtitle:
                'IMEI: ${d.imei} | متوفر: ${d.quantity} | ${d.supplier ?? ''}',
            icon: Icons.phone_iphone_outlined,
            iconColor: Colors.indigo[700]!,
            entityType: SearchEntityType.device,
            itemId: d.id ?? 0,
            menuTitle: '📱 إدارة الأجهزة',
          ));
        }
      }
    }

    // 4. Spare Parts
    if (_cache.spareParts != null) {
      for (final s in _cache.spareParts!) {
        if (_matches(q, [
          s.name,
          s.supplier ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: s.name,
            subtitle:
                'متوفر: ${s.quantity} | السعر: ${s.price} | ${s.supplier ?? ''}',
            icon: Icons.settings_outlined,
            iconColor: Colors.brown[700]!,
            entityType: SearchEntityType.sparePart,
            itemId: s.id ?? 0,
            menuTitle: '⚙️ قطع غيار الصيانة',
          ));
        }
      }
    }

    // 5. Suppliers
    if (_cache.suppliers != null) {
      for (final s in _cache.suppliers!) {
        if (_matches(q, [
          s.name,
          s.phone ?? '',
          s.address ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: s.name,
            subtitle:
                '${s.phone ?? ''}${s.address != null && s.address!.isNotEmpty ? ' | ${s.address}' : ''}',
            icon: Icons.people_outlined,
            iconColor: Colors.green[700]!,
            entityType: SearchEntityType.supplier,
            itemId: s.id ?? 0,
            menuTitle: '🤝 حسابات الموردين',
          ));
        }
      }
    }

    // 6. Deferred Payments
    if (_cache.deferredPayments != null) {
      for (final d in _cache.deferredPayments!) {
        if (_matches(q, [
          d.customerName,
          d.customerPhone,
          d.notes ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: d.customerName,
            subtitle:
                'متبقي: ${d.remainingAmount} | ${d.transactionType ?? ''} | ${d.customerPhone}',
            icon: Icons.account_balance_wallet_outlined,
            iconColor: Colors.purple[700]!,
            entityType: SearchEntityType.deferredPayment,
            itemId: d.id ?? 0,
            menuTitle: '💳 حسابات العملاء الآجلة',
          ));
        }
      }
    }

    // 7. Sales
    if (_cache.sales != null) {
      for (final s in _cache.sales!) {
        if (_matches(q, [
          s.customerName ?? '',
          s.customerPhone ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: '#${s.id} - ${s.customerName ?? 'نقدي'}',
            subtitle:
                'المبلغ: ${s.finalAmount} | ${s.paymentMethod} | ${s.saleDate.toLocal().toString().substring(0, 10)}',
            icon: Icons.receipt_outlined,
            iconColor: Colors.blue[700]!,
            entityType: SearchEntityType.sale,
            itemId: s.id ?? 0,
            menuTitle: '💵 بيع منتج من المحل',
          ));
        }
      }
    }

    // 8. Returns
    if (_cache.returns != null) {
      for (final r in _cache.returns!) {
        if (_matches(q, [
          r.customerName ?? '',
          r.customerPhone ?? '',
          r.notes ?? '',
        ])) {
          results.add(SmartSearchResult(
            title: '#${r.id} - ${r.customerName ?? ''}',
            subtitle:
                'المبلغ: ${r.totalAmount} | ${r.paymentMethod} | ${r.returnDate.toLocal().toString().substring(0, 10)}',
            icon: Icons.assignment_return_outlined,
            iconColor: Colors.red[700]!,
            entityType: SearchEntityType.return_,
            itemId: r.id ?? 0,
            menuTitle: '🔄 المرتجعات',
          ));
        }
      }
    }

    // Sort: prioritise exact matches and shorter results first
    results.sort((a, b) {
      final aExact = a.title.toLowerCase().contains(q) ? 0 : 1;
      final bExact = b.title.toLowerCase().contains(q) ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);
      return a.title.length.compareTo(b.title.length);
    });

    return results;
  }

  /// Check if any of [fields] contains [query] (case-insensitive)
  static bool _matches(String query, List<String> fields) {
    for (final f in fields) {
      if (f.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}
