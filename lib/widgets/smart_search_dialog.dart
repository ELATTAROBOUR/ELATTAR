// lib/widgets/smart_search_dialog.dart
// Full-featured smart search dialog for the ELATTAR Store

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/smart_search_service.dart';

/// Callback invoked when the user taps a search result.
/// [menuTitle] is the sidebar menu item title to navigate to.
/// [itemId] is the database ID of the matched entity.
typedef OnNavigateToEntity = void Function(String menuTitle, int itemId);

/// A full-screen search dialog that loads all entities in the background
/// and lets the user fuzzy-search across everything.
class SmartSearchDialog extends StatefulWidget {
  final OnNavigateToEntity onNavigate;

  const SmartSearchDialog({super.key, required this.onNavigate});

  /// Convenience method to show the dialog.
  static Future<void> show(
    BuildContext context, {
    required OnNavigateToEntity onNavigate,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      useSafeArea: false,
      builder: (_) => SmartSearchDialog(onNavigate: onNavigate),
    );
  }

  @override
  State<SmartSearchDialog> createState() => _SmartSearchDialogState();
}

class _SmartSearchDialogState extends State<SmartSearchDialog> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<SmartSearchResult> _results = [];
  bool _isLoading = true;
  bool _hasSearched = false;
  Timer? _debounce;

  static const List<String> _quickActions = [
    'بحث في تذاكر الصيانة',
    'بحث في الإكسسوارات',
    'بحث في الأجهزة',
    'بحث في قطع الغيار',
    'بحث في الموردين',
    'بحث في الحسابات الآجلة',
  ];

  static const List<IconData> _quickIcons = [
    Icons.build_circle_outlined,
    Icons.headset_outlined,
    Icons.phone_iphone_outlined,
    Icons.settings_outlined,
    Icons.people_outlined,
    Icons.account_balance_wallet_outlined,
  ];

  @override
  void initState() {
    super.initState();
    // Load data in the background while the dialog animates in
    SmartSearchService.loadAll().then((_) {
      if (mounted) setState(() => _isLoading = false);
    });
    // Focus the search field after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    SmartSearchService.clearCache();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        setState(() {
          _results = [];
          _hasSearched = false;
        });
        return;
      }
      setState(() {
        _results = SmartSearchService.search(value);
        _hasSearched = true;
      });
    });
  }

  void _onResultTapped(SmartSearchResult result) {
    widget.onNavigate(result.menuTitle ?? '', result.itemId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2F41) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // ── Header: Search field ──────────────────────────────
              _buildSearchField(isDark),
              const Divider(height: 1, thickness: 1),
              // ── Body ──────────────────────────────────────────────
              Expanded(child: _buildBody(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _focusNode,
        onChanged: _onSearchChanged,
        autofocus: false,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'ابحث في كل شيء… (عملاء، أجهزة، فواتير)',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? Colors.white12 : Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    // Loading state
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري تحميل البيانات…', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }

    // No query yet → show quick suggestions
    if (!_hasSearched) {
      return _buildSuggestions(isDark);
    }

    // Empty results
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('لا توجد نتائج',
                style: TextStyle(fontSize: 16, color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text('حاول بكلمة مختلفة',
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ],
        ),
      );
    }

    // Results → group by entity type
    return _buildResults(isDark);
  }

  /// Show quick suggestions while the user hasn't typed yet
  Widget _buildSuggestions(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ابحث عن:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_quickActions.length, (i) {
              return ActionChip(
                avatar: Icon(_quickIcons[i], size: 18),
                label: Text(_quickActions[i],
                    style: const TextStyle(fontSize: 13)),
                onPressed: () {
                  _searchCtrl.text = _quickActions[i].replaceAll('بحث في ', '');
                  _searchCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _searchCtrl.text.length),
                  );
                  _onSearchChanged(_searchCtrl.text);
                },
              );
            }),
          ),
          const SizedBox(height: 20),
          Text('نصائح:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500])),
          const SizedBox(height: 8),
          _buildTip('ابحث باسم العميل، رقم الهاتف، أو موديل الجهاز'),
          _buildTip('ابحث في المخزون: اسم المنتج، المورد، أو الكود'),
          _buildTip('ابحث في الموردين: الاسم أو رقم الهاتف'),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.tips_and_updates_outlined,
              size: 16, color: Colors.amber[700]),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  /// Group results by entity type and render them
  Widget _buildResults(bool isDark) {
    // Group by type
    final grouped = <SearchEntityType, List<SmartSearchResult>>{};
    for (final r in _results) {
      grouped.putIfAbsent(r.entityType, () => []).add(r);
    }

    // Summary counts per type
    final summary = grouped.entries.map((e) {
      final label = e.value.isNotEmpty ? e.value.first.typeLabel : '';
      return '${label} (${e.value.length})';
    }).join(' · ');

    return Column(
      children: [
        // Summary bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text(
            summary,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ),
        const Divider(height: 1),
        // Scrollable results
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: grouped.entries.expand((entry) {
              final type = entry.key;
              final items = entry.value;
              final typeLabel = items.first.typeLabel;
              final typeIcon = items.first.icon;
              final typeColor = items.first.iconColor;

              return [
                // Group header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(typeIcon, size: 18, color: typeColor),
                      const SizedBox(width: 8),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${items.length} نتيجة',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                // Items
                ...items.map((r) => _buildResultTile(r, isDark)),
              ];
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildResultTile(SmartSearchResult result, bool isDark) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: result.iconColor.withValues(alpha: 0.15),
        child: Icon(result.icon, size: 18, color: result.iconColor),
      ),
      title: Text(
        result.title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        result.subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          Icon(Icons.chevron_left_rounded, size: 18, color: Colors.grey[400]),
      onTap: () => _onResultTapped(result),
    );
  }
}
