// lib/views/branches_view.dart
// Multi-Branch Management View

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';

class BranchesView extends StatefulWidget {
  const BranchesView({super.key});

  @override
  State<BranchesView> createState() => _BranchesViewState();
}

class _BranchesViewState extends State<BranchesView> {
  List<StoreBranch> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      _branches = await DatabaseHelper.loadBranches();
    } catch (e) {
      debugPrint('Error loading branches: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final current = DatabaseHelper.currentBranch;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الفروع'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'إضافة فرع جديد',
            onPressed: _showAddBranchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'تحديث',
            onPressed: _loadBranches,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _branches.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_mall_directory,
                          size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('لا توجد فروع بعد',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة الفرع الأول'),
                        onPressed: _showAddBranchDialog,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBranches,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _branches.length + 1, // +1 for header card
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildInfoCard(current, isRtl);
                      }
                      final branch = _branches[index - 1];
                      final isActive =
                          current != null && branch.id == current.id;
                      return _buildBranchCard(branch, isActive, isRtl);
                    },
                  ),
                ),
    );
  }

  Widget _buildInfoCard(StoreBranch? current, bool isRtl) {
    final activeName = current?.name ?? '—';
    return Card(
      color: Colors.blue[50],
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الفرع النشط حالياً:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  Text(activeName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                      'قاعدة بيانات: ${current?.dbFileName ?? 'ELATTAR_STORE.db'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchCard(StoreBranch branch, bool isActive, bool isRtl) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: Colors.blue[400]!, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Branch icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive ? Colors.blue[100] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.store,
                color: isActive ? Colors.blue[700] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 12),
            // Branch details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(branch.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      if (isActive)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('نشط',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green[800],
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('الكود: ${branch.code}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  Text('Machine ID: ${branch.machineId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  if (branch.phone != null && branch.phone!.isNotEmpty)
                    Text('هاتف: ${branch.phone}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  if (branch.address != null && branch.address!.isNotEmpty)
                    Text('عنوان: ${branch.address}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            // Action buttons
            if (!isActive)
              TextButton(
                onPressed: () => _switchToBranch(branch),
                child: const Text('تبديل'),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'تعديل',
              onPressed: () => _showEditBranchDialog(branch),
            ),
            if (branch.id > 1 || _branches.length > 1)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.red),
                tooltip: 'حذف',
                onPressed: () => _confirmDeleteBranch(branch),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Switch Branch ──────────────────────────────────────────────────────
  Future<void> _switchToBranch(StoreBranch branch) async {
    try {
      await DatabaseHelper.switchBranch(branch.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم التبديل إلى فرع "${branch.name}" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadBranches();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التبديل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── Add Branch ─────────────────────────────────────────────────────────
  void _showAddBranchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _BranchFormDialog(
        onSaved: (branch) async {
          await DatabaseHelper.addBranch(branch);
          await _loadBranches();
        },
      ),
    );
  }

  // ─── Edit Branch ────────────────────────────────────────────────────────
  void _showEditBranchDialog(StoreBranch branch) {
    showDialog(
      context: context,
      builder: (ctx) => _BranchFormDialog(
        existing: branch,
        onSaved: (updated) async {
          await DatabaseHelper.updateBranch(updated);
          await _loadBranches();
        },
      ),
    );
  }

  // ─── Delete Branch ──────────────────────────────────────────────────────
  void _confirmDeleteBranch(StoreBranch branch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف فرع "${branch.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await DatabaseHelper.deleteBranch(branch.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حذف الفرع'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                await _loadBranches();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('خطأ: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Branch Add/Edit Form Dialog
// ═══════════════════════════════════════════════════════════════════════════

class _BranchFormDialog extends StatefulWidget {
  final StoreBranch? existing;
  final Future<void> Function(StoreBranch branch) onSaved;

  const _BranchFormDialog({this.existing, required this.onSaved});

  @override
  State<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<_BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _machineIdCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _managerCtrl;
  late TextEditingController _dbFileCtrl;
  late TextEditingController _repoUrlCtrl;
  late TextEditingController _gitBranchCtrl;
  late TextEditingController _storeNameCtrl;
  late TextEditingController _storeEmailCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _codeCtrl = TextEditingController(text: b?.code ?? '');
    _machineIdCtrl =
        TextEditingController(text: (b?.machineId ?? 1).toString());
    _phoneCtrl = TextEditingController(text: b?.phone ?? '');
    _addressCtrl = TextEditingController(text: b?.address ?? '');
    _managerCtrl = TextEditingController(text: b?.managerName ?? '');
    _dbFileCtrl = TextEditingController(
        text: b?.dbFileName ?? 'ELATTAR_STORE_${b?.id ?? ''}.db');
    _repoUrlCtrl = TextEditingController(text: b?.repoUrl ?? '');
    _gitBranchCtrl = TextEditingController(text: b?.gitBranchName ?? 'main');
    _storeNameCtrl = TextEditingController(text: b?.storeName ?? '');
    _storeEmailCtrl = TextEditingController(text: b?.storeEmail ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _machineIdCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _managerCtrl.dispose();
    _dbFileCtrl.dispose();
    _repoUrlCtrl.dispose();
    _gitBranchCtrl.dispose();
    _storeNameCtrl.dispose();
    _storeEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(isEdit ? 'تعديل الفرع' : 'إضافة فرع جديد'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField('اسم الفرع', _nameCtrl, required: true),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildField('الكود', _codeCtrl,
                            required: true, hint: 'main, obour, nasr...')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildField('Machine ID', _machineIdCtrl,
                            required: true,
                            keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildField('رقم الهاتف', _phoneCtrl,
                            keyboardType: TextInputType.phone)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('المدير', _managerCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                _buildField('العنوان', _addressCtrl),
                const SizedBox(height: 8),
                _buildField('اسم ملف قاعدة البيانات', _dbFileCtrl,
                    required: true, hint: 'ELATTAR_STORE_2.db'),
                const SizedBox(height: 12),
                const Divider(),
                const Text('إعدادات المزامنة (اختياري)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildField('رابط المستودع (Git)', _repoUrlCtrl,
                    hint: 'https://github.com/...'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _buildField('فرع Git', _gitBranchCtrl,
                            hint: 'main')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildField('اسم المتجر', _storeNameCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                _buildField('البريد الإلكتروني', _storeEmailCtrl,
                    keyboardType: TextInputType.emailAddress),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl,
      {bool required = false,
      TextInputType keyboardType = TextInputType.text,
      String? hint}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null
          : null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final branch = StoreBranch(
        id: widget.existing?.id ?? await DatabaseHelper.nextBranchId(),
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
        machineId: int.tryParse(_machineIdCtrl.text.trim()) ?? 1,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        address:
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        managerName:
            _managerCtrl.text.trim().isEmpty ? null : _managerCtrl.text.trim(),
        dbFileName: _dbFileCtrl.text.trim().isEmpty
            ? 'ELATTAR_STORE.db'
            : _dbFileCtrl.text.trim(),
        repoUrl:
            _repoUrlCtrl.text.trim().isEmpty ? null : _repoUrlCtrl.text.trim(),
        gitBranchName: _gitBranchCtrl.text.trim().isEmpty
            ? null
            : _gitBranchCtrl.text.trim(),
        storeName: _storeNameCtrl.text.trim().isEmpty
            ? null
            : _storeNameCtrl.text.trim(),
        storeEmail: _storeEmailCtrl.text.trim().isEmpty
            ? null
            : _storeEmailCtrl.text.trim(),
      );
      await widget.onSaved(branch);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
