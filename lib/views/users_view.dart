// lib/views/users_view.dart
// مقسومة إلى قسمين: إدارة المستخدمين + إدارة الفنيين (مثل صفحة إضافة منتج)

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../widgets/skeleton_loading.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/custom_toast.dart';

class UsersView extends StatefulWidget {
  const UsersView({super.key});

  @override
  State<UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<UsersView> {
  // ─── Section Selection ──────────────────────────────────────
  String _selectedSection = 'users'; // 'users' | 'technicians'

  // ─── Users State ────────────────────────────────────────────
  List<AppUser> _users = [];
  bool _isLoadingUsers = true;

  // ─── Technicians State ──────────────────────────────────────
  List<Map<String, dynamic>> _technicians = [];
  bool _isLoadingTechs = true;

  // ─── Sync State ─────────────────────────────────────────────
  bool _isSyncing = false;

  // ─── Constants ──────────────────────────────────────────────
  static const _gold = Color(0xFFD4AF37);
  static const _darkText = Color(0xFF1A2A3A);

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadTechnicians();
  }

  // ═══════════════════════════════════════════════════════════════
  //  USERS — إدارة المستخدمين
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final list = await DatabaseHelper.loadUsers();
      if (mounted) setState(() => _users = list);
    } catch (e) {
      debugPrint('Error loading users: $e');
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  bool _isValidEmail(String email) {
    final regExp =
        RegExp(r'^[a-zA-Z0-9\._%+-]+@[a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$');
    return regExp.hasMatch(email.trim().toLowerCase());
  }

  void _showAddUserDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String selectedRole = 'staff';
    bool passVisible = false;
    bool confirmVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.person_add_alt_1_rounded, color: _gold),
              const SizedBox(width: 10),
              const Text('إضافة مستخدم جديد للنظام',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ]),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: emailCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني *',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    style: TextStyle(
                        color: AppTheme.text(context),
                        fontFamily: 'Cairo',
                        fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'الصلاحيات / الدور *',
                      labelStyle: TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'manager',
                        child: Text('مدير (كامل الصلاحيات)',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                      DropdownMenuItem(
                        value: 'staff',
                        child: Text('فني أو بائع (صلاحيات محدودة)',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                      DropdownMenuItem(
                        value: 'technician',
                        child: Text('فني صيانة (صيانة وقطع غيار فقط)',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlg(() => selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passCtrl,
                    obscureText: !passVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                          icon: Icon(passVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => passVisible = !passVisible)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: !confirmVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_clock_outlined),
                      suffixIcon: IconButton(
                          icon: Icon(confirmVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => confirmVisible = !confirmVisible)),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontFamily: 'Cairo',
                        fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: _darkText),
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  final password = passCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();
                  if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
                    _snack(ctx, '⚠️ يرجى ملء كافة الحقول المطلوبة',
                        Colors.redAccent);
                    return;
                  }
                  if (!_isValidEmail(email)) {
                    _snack(ctx, '⚠️ يرجى إدخال بريد إلكتروني صالح',
                        Colors.redAccent);
                    return;
                  }
                  if (password.length < 8) {
                    _snack(ctx, '⚠️ يجب ألا تقل كلمة المرور عن 8 خانات',
                        Colors.redAccent);
                    return;
                  }
                  if (password != confirm) {
                    _snack(
                        ctx, '⚠️ كلمتا المرور غير متطابقتين', Colors.redAccent);
                    return;
                  }
                  final existingUser =
                      await DatabaseHelper.getUserByEmail(email);
                  if (existingUser != null) {
                    _snack(ctx, '⚠️ هذا البريد الإلكتروني مسجل مسبقاً!',
                        Colors.redAccent);
                    return;
                  }
                  final hashed = hashPassword(password);
                  await DatabaseHelper.saveUser(AppUser(
                      email: email, passwordHash: hashed, role: selectedRole));
                  if (ctx.mounted) {
                    _snack(ctx, '✅ تم إضافة المستخدم بنجاح!', Colors.green);
                    Navigator.pop(ctx);
                  }
                  _loadUsers();
                },
                child: const Text('حفظ الحساب',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(AppUser user) {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool passVisible = false;
    bool confirmVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.lock_reset_rounded, color: _gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text('تغيير كلمة المرور لـ: ${user.email}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ]),
            content: SizedBox(
              width: 400,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: passCtrl,
                  obscureText: !passVisible,
                  style: TextStyle(
                      color: AppTheme.text(context), fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور الجديدة *',
                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                        icon: Icon(passVisible
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setDlg(() => passVisible = !passVisible)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmCtrl,
                  obscureText: !confirmVisible,
                  style: TextStyle(
                      color: AppTheme.text(context), fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'تأكيد كلمة المرور الجديدة *',
                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                    prefixIcon: const Icon(Icons.lock_clock_outlined),
                    suffixIcon: IconButton(
                        icon: Icon(confirmVisible
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setDlg(() => confirmVisible = !confirmVisible)),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontFamily: 'Cairo',
                        fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: _darkText),
                onPressed: () async {
                  final password = passCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();
                  if (password.isEmpty || confirm.isEmpty) {
                    _snack(ctx, '⚠️ يرجى إدخال كلمة المرور وتأكيدها',
                        Colors.redAccent);
                    return;
                  }
                  if (password.length < 8) {
                    _snack(ctx, '⚠️ يجب ألا تقل كلمة المرور عن 8 خانات',
                        Colors.redAccent);
                    return;
                  }
                  if (password != confirm) {
                    _snack(
                        ctx, '⚠️ كلمتا المرور غير متطابقتين', Colors.redAccent);
                    return;
                  }
                  user.passwordHash = hashPassword(password);
                  await DatabaseHelper.saveUser(user);
                  if (currentLoggedInUser?.id == user.id) {
                    currentLoggedInUser = user;
                  }
                  if (ctx.mounted) {
                    _snack(ctx, '✅ تم تحديث كلمة المرور بنجاح!', Colors.green);
                    Navigator.pop(ctx);
                  }
                  _loadUsers();
                },
                child: const Text('تحديث كلمة المرور',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditRoleDialog(AppUser user) {
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.manage_accounts_rounded, color: _gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text('تعديل صلاحيات: ${user.email}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ]),
            content: DropdownButtonFormField<String>(
              initialValue: selectedRole,
              style: TextStyle(
                  color: AppTheme.text(context),
                  fontFamily: 'Cairo',
                  fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'الدور الصلاحي الحالي',
                labelStyle: TextStyle(fontFamily: 'Cairo'),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'manager',
                  child: Text('مدير (كامل الصلاحيات)',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
                DropdownMenuItem(
                  value: 'staff',
                  child: Text('فني أو بائع (صلاحيات محدودة)',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
                DropdownMenuItem(
                  value: 'technician',
                  child: Text('فني صيانة (صيانة وقطع غيار فقط)',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
              onChanged: (val) {
                if (val != null) setDlg(() => selectedRole = val);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontFamily: 'Cairo',
                        fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: _darkText),
                onPressed: () async {
                  if (user.role == 'manager' && selectedRole != 'manager') {
                    final otherManagers = _users
                        .where((u) => u.role == 'manager' && u.id != user.id);
                    if (otherManagers.isEmpty) {
                      _snack(
                          ctx,
                          '⚠️ لا يمكن تغيير رتبتك لأنك المدير الوحيد في النظام!',
                          Colors.redAccent);
                      return;
                    }
                  }
                  user.role = selectedRole;
                  await DatabaseHelper.saveUser(user);
                  if (currentLoggedInUser?.id == user.id) {
                    currentLoggedInUser = user;
                  }
                  if (ctx.mounted) {
                    _snack(ctx, '✅ تم تعديل الصلاحية بنجاح!', Colors.green);
                    Navigator.pop(ctx);
                  }
                  _loadUsers();
                },
                child: const Text('حفظ',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteUser(AppUser user) {
    if (currentLoggedInUser != null && currentLoggedInUser!.id == user.id) {
      _snack(context, '⚠️ لا يمكنك حذف حسابك الشخصي أثناء تسجيل الدخول!',
          Colors.redAccent);
      return;
    }
    if (user.role == 'manager') {
      final otherManagers =
          _users.where((u) => u.role == 'manager' && u.id != user.id);
      if (otherManagers.isEmpty) {
        _snack(context, '⚠️ يجب أن يتبقى مدير واحد على الأقل في النظام!',
            Colors.redAccent);
        return;
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg(context),
          title: const Text('⚠️ تأكيد الحذف',
              style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Text(
              'هل أنت متأكد من حذف الحساب "${user.email}" نهائياً من النظام؟',
              style: TextStyle(
                  color: AppTheme.text(context),
                  fontSize: 16,
                  fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 16,
                        fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (user.id != null) {
                  await DatabaseHelper.deleteUser(user.id!);
                }
                if (ctx.mounted) {
                  _snack(ctx, '✅ تم حذف الحساب بنجاح!', Colors.green);
                  Navigator.pop(ctx);
                }
                _loadUsers();
              },
              child: const Text('حذف الحساب',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SYNC
  // ═══════════════════════════════════════════════════════════════

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      await DatabaseHelper.syncDatabase();
      await _loadTechnicians();
      if (mounted) {
        CustomToast.show(context,
            message: '✅ تمت المزامنة بنجاح!', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        CustomToast.show(context,
            message: '⚠️ خطأ أثناء المزامنة: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  TECHNICIANS — إدارة الفنيين
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadTechnicians() async {
    setState(() => _isLoadingTechs = true);
    try {
      final list = await DatabaseHelper.loadTechniciansRaw();
      if (mounted) setState(() => _technicians = list);
    } catch (e) {
      debugPrint('Error loading technicians: $e');
    } finally {
      if (mounted) setState(() => _isLoadingTechs = false);
    }
  }

  void _showAddTechnicianDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool passVisible = false;
    bool confirmVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.engineering_rounded, color: _gold),
              const SizedBox(width: 10),
              const Text('إضافة فني صيانة جديد',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ]),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'اسم الفني *',
                        hintText: 'يُستخدم للدخول على تطبيق الموبايل',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني *',
                        hintText: 'للدخول على تطبيق الموبايل',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'رقم الهاتف *',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(Icons.phone_android_rounded, size: 16, color: _gold),
                      const SizedBox(width: 6),
                      const Text('بيانات الدخول للموبايل',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: _gold,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  TextField(
                    controller: passCtrl,
                    obscureText: !passVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                          icon: Icon(passVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => passVisible = !passVisible)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: !confirmVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_clock_outlined),
                      suffixIcon: IconButton(
                          icon: Icon(confirmVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => confirmVisible = !confirmVisible)),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontFamily: 'Cairo',
                        fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: _darkText),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();
                  final email = emailCtrl.text.trim().toLowerCase();
                  final pass = passCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();
                  if (name.isEmpty || phone.isEmpty || email.isEmpty || pass.isEmpty) {
                    _snack(
                        ctx,
                        '⚠️ الاسم ورقم الهاتف والبريد الإلكتروني وكلمة المرور مطلوبة',
                        Colors.redAccent);
                    return;
                  }
                  if (!RegExp(
                          r'^[a-zA-Z0-9\._%+-]+@[a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$')
                      .hasMatch(email)) {
                    _snack(ctx, '⚠️ يرجى إدخال بريد إلكتروني صالح',
                        Colors.redAccent);
                    return;
                  }
                  final existingEmail = _technicians.any((t) =>
                      (t['email'] as String? ?? '').trim().toLowerCase() ==
                      email);
                  if (existingEmail) {
                    _snack(
                        ctx,
                        '⚠️ هذا البريد الإلكتروني مستخدم من قبل فني آخر!',
                        Colors.redAccent);
                    return;
                  }
                  if (pass.length < 6) {
                    _snack(ctx, '⚠️ كلمة المرور يجب ألا تقل عن 6 خانات',
                        Colors.redAccent);
                    return;
                  }
                  if (pass != confirm) {
                    _snack(
                        ctx, '⚠️ كلمتا المرور غير متطابقتين', Colors.redAccent);
                    return;
                  }
                  final existing = _technicians.any((t) =>
                      (t['name'] as String).trim().toLowerCase() ==
                      name.toLowerCase());
                  if (existing) {
                    _snack(ctx, '⚠️ يوجد فني بهذا الاسم مسبقاً!',
                        Colors.redAccent);
                    return;
                  }
                  final hash = pass.isNotEmpty ? hashPassword(pass) : null;
                  await DatabaseHelper.addTechnician(name, phone,
                      mobilePasswordHash: hash, email: email);
                  if (ctx.mounted) {
                    _snack(ctx, '✅ تم إضافة الفني بنجاح!', Colors.green);
                    Navigator.pop(ctx);
                  }
                  _loadTechnicians();
                },
                child: const Text('حفظ الفني',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditTechnicianDialog(Map<String, dynamic> tech) {
    final int id = tech['id'] as int;
    final String oldName = tech['name'] as String;
    final String oldPhone = tech['phone'] as String;
    final String? oldEmail = tech['email'] as String?;
    final nameCtrl = TextEditingController(text: oldName);
    final phoneCtrl = TextEditingController(text: oldPhone);
    final emailCtrl = TextEditingController(text: oldEmail ?? '');
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool passVisible = false;
    bool confirmVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.edit_rounded, color: _gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text('تعديل بيانات الفني: $oldName',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ]),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: nameCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'اسم الفني *',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني *',
                        hintText: 'للدخول على تطبيق الموبايل',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneCtrl,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'رقم الهاتف *',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _gold.withValues(alpha: 0.3)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline, color: _gold, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'اترك حقلي كلمة المرور فارغين إذا كنت لا تريد تغييرها',
                          style: TextStyle(
                              fontFamily: 'Cairo', fontSize: 12, color: _gold),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: !passVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                          icon: Icon(passVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => passVisible = !passVisible)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: !confirmVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور الجديدة',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_clock_outlined),
                      suffixIcon: IconButton(
                          icon: Icon(confirmVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => confirmVisible = !confirmVisible)),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontFamily: 'Cairo',
                        fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: _darkText),
                onPressed: () async {
                  final newName = nameCtrl.text.trim();
                  final newPhone = phoneCtrl.text.trim();
                  final newEmail = emailCtrl.text.trim().toLowerCase();
                  final newPass = passCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();
                  if (newName.isEmpty || newPhone.isEmpty || newEmail.isEmpty) {
                    _snack(ctx, '⚠️ جميع الحقول المطلوبة يجب أن تمتلئ',
                        Colors.redAccent);
                    return;
                  }
                  if (!RegExp(
                          r'^[a-zA-Z0-9\._%+-]+@[a-zA-Z0-9\.-]+\.[a-zA-Z]{2,}$')
                      .hasMatch(newEmail)) {
                    _snack(ctx, '⚠️ يرجى إدخال بريد إلكتروني صالح',
                        Colors.redAccent);
                    return;
                  }
                  final emailExists = _technicians.any((t) =>
                      (t['id'] as int) != id &&
                      (t['email'] as String? ?? '').trim().toLowerCase() ==
                          newEmail);
                  if (emailExists) {
                    _snack(
                        ctx,
                        '⚠️ هذا البريد الإلكتروني مستخدم من قبل فني آخر!',
                        Colors.redAccent);
                    return;
                  }
                  final nameExists = _technicians.any((t) =>
                      (t['id'] as int) != id &&
                      (t['name'] as String).trim().toLowerCase() ==
                          newName.toLowerCase());
                  if (nameExists) {
                    _snack(ctx, '⚠️ يوجد فني آخر بهذا الاسم مسبقاً!',
                        Colors.redAccent);
                    return;
                  }
                  if (newPass.isNotEmpty) {
                    if (newPass.length < 6) {
                      _snack(ctx, '⚠️ كلمة المرور يجب ألا تقل عن 6 خانات',
                          Colors.redAccent);
                      return;
                    }
                    if (newPass != confirm) {
                      _snack(ctx, '⚠️ كلمتا المرور غير متطابقتين',
                          Colors.redAccent);
                      return;
                    }
                  }
                  final hash =
                      newPass.isNotEmpty ? hashPassword(newPass) : null;
                  await DatabaseHelper.updateTechnician(
                    id,
                    newName,
                    newPhone,
                    email: newEmail,
                    mobilePasswordHash: hash,
                  );
                  if (ctx.mounted) {
                    _snack(ctx, '✅ تم تعديل بيانات الفني بنجاح!', Colors.green);
                    Navigator.pop(ctx);
                  }
                  _loadTechnicians();
                },
                child: const Text('حفظ التعديلات',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSetMobilePasswordDialog(Map<String, dynamic> tech) {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool passVisible = false;
    bool confirmVisible = false;
    final int id = tech['id'] as int;
    final String name = tech['name'] as String;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.phone_android_rounded, color: _gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text('كلمة مرور الموبايل لـ: $name',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ]),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _gold.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: _gold, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'يدخل الفني باسمه "$name" وهذه الكلمة على تطبيق الموبايل',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12, color: _gold),
                        ),
                      ),
                    ]),
                  ),
                  TextField(
                    controller: passCtrl,
                    obscureText: !passVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                          icon: Icon(passVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => passVisible = !passVisible)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: !confirmVisible,
                    style: TextStyle(
                        color: AppTheme.text(context), fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور *',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.lock_clock_outlined),
                      suffixIcon: IconButton(
                          icon: Icon(confirmVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setDlg(() => confirmVisible = !confirmVisible)),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontFamily: 'Cairo',
                        fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _gold, foregroundColor: _darkText),
                onPressed: () async {
                  final pass = passCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();
                  if (pass.isEmpty) {
                    _snack(ctx, '⚠️ يرجى إدخال كلمة المرور', Colors.redAccent);
                    return;
                  }
                  if (pass.length < 6) {
                    _snack(ctx, '⚠️ كلمة المرور يجب ألا تقل عن 6 خانات',
                        Colors.redAccent);
                    return;
                  }
                  if (pass != confirm) {
                    _snack(
                        ctx, '⚠️ كلمتا المرور غير متطابقتين', Colors.redAccent);
                    return;
                  }
                  await DatabaseHelper.setTechnicianMobilePassword(
                      id, hashPassword(pass));
                  if (ctx.mounted) {
                    _snack(ctx, '✅ تم تعيين كلمة المرور بنجاح!', Colors.green);
                    Navigator.pop(ctx);
                  }
                  _loadTechnicians();
                },
                child: const Text('حفظ كلمة المرور',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteTechnician(Map<String, dynamic> tech) {
    final int id = tech['id'] as int;
    final String name = tech['name'] as String;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg(context),
          title: const Text('⚠️ تأكيد حذف الفني',
              style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          content: Text(
              'هل أنت متأكد من حذف الفني "$name" من النظام؟\nلن يتمكن من الدخول على تطبيق الموبايل.',
              style: TextStyle(
                  color: AppTheme.text(context),
                  fontSize: 16,
                  fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context),
                        fontSize: 16,
                        fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white),
              onPressed: () async {
                await DatabaseHelper.deleteTechnician(id, name);
                if (ctx.mounted) {
                  _snack(ctx, '✅ تم حذف الفني بنجاح!', Colors.green);
                  Navigator.pop(ctx);
                }
                _loadTechnicians();
              },
              child: const Text('حذف الفني',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════

  void _snack(BuildContext ctx, String msg, [Color? bg]) {
    if (!ctx.mounted) return;
    final type = bg == Colors.green
        ? ToastType.success
        : bg == Colors.redAccent || bg == Colors.red
            ? ToastType.error
            : ToastType.warning;
    CustomToast.show(ctx, message: msg, type: type);
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final cardBg = AppTheme.cardBg(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────
            Text(
              _selectedSection == 'users'
                  ? '👥 إدارة المستخدمين والصلاحيات'
                  : '🔧 إدارة فنيي الصيانة',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedSection == 'users'
                  ? 'إنشاء وإدارة حسابات الموظفين والمديرين وتوزيع الأدوار في النظام.'
                  : 'إضافة وتعديل الفنيين مع البريد الإلكتروني وكلمة المرور لتسجيل الدخول من الموبايل.',
              style: TextStyle(
                  fontSize: 15, color: textMuted, fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 24),

            // ── Section Selection Cards (مثل إضافة منتج) ──────────
            Row(
              children: [
                Expanded(
                  child: _buildSectionCard(
                    title: 'إدارة المستخدمين',
                    section: 'users',
                    icon: Icons.admin_panel_settings_rounded,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSectionCard(
                    title: 'إدارة الفنيين',
                    section: 'technicians',
                    icon: Icons.engineering_rounded,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Action Bar ────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Spacer(),
                if (_selectedSection == 'technicians')
                  Row(children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _isSyncing
                          ? const SizedBox(
                              width: 40,
                              height: 40,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _gold),
                              ),
                            )
                          : Tooltip(
                              message: 'مزامنة قاعدة البيانات الآن مع GitHub',
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: _gold),
                                  foregroundColor: _gold,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                                onPressed: _syncNow,
                                icon: const Icon(Icons.sync_rounded, size: 20),
                                label: const Text('مزامنة الآن',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                  ]),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _darkText,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                  onPressed: _selectedSection == 'users'
                      ? _showAddUserDialog
                      : _showAddTechnicianDialog,
                  icon: Icon(
                      _selectedSection == 'users'
                          ? Icons.person_add_rounded
                          : Icons.add_rounded,
                      size: 22),
                  label: Text(
                    _selectedSection == 'users'
                        ? 'إضافة مستخدم جديد'
                        : 'إضافة فني',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Content ───────────────────────────────────────────
            Expanded(
              child: _selectedSection == 'users'
                  ? _buildUsersContent(textColor, textMuted, cardBg)
                  : _buildTechniciansContent(textColor, textMuted, cardBg),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Section Selection Card ─────────────────────
  Widget _buildSectionCard({
    required String title,
    required String section,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedSection == section;
    final cardBg = AppTheme.cardBg(context);
    final textColor = AppTheme.text(context);

    return GestureDetector(
      onTap: () => setState(() => _selectedSection = section),
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
    );
  }

  // ─────────────────── Users Table ────────────────────────────────
  Widget _buildUsersContent(Color textColor, Color textMuted, Color cardBg) {
    if (_isLoadingUsers) {
      return SkeletonLoading.dashboardPage(context);
    }
    if (_users.isEmpty) {
      return AppEmptyState.noData(
        message: 'لا يوجد مستخدمون حالياً في النظام',
      );
    }
    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            headingTextStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: _gold,
                fontSize: 15),
            dataTextStyle:
                TextStyle(fontFamily: 'Cairo', color: textColor, fontSize: 14),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('البريد الإلكتروني')),
              DataColumn(label: Text('الصلاحية / الدور')),
              DataColumn(label: Text('خيارات الإدارة')),
            ],
            rows: _users.map((user) {
              final isMe = currentLoggedInUser?.id == user.id;
              String roleName = user.role == 'manager'
                  ? 'مدير'
                  : user.role == 'technician'
                      ? 'فني صيانة'
                      : 'فني أو بائع';
              Color roleColor = user.role == 'manager'
                  ? Colors.green
                  : user.role == 'technician'
                      ? Colors.orange
                      : Colors.blueAccent;
              return DataRow(cells: [
                DataCell(Text('#${user.id ?? ""}')),
                DataCell(Row(children: [
                  Text(user.email,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (isMe) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _gold),
                      ),
                      child: Text('أنت',
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Cairo',
                              color: _gold,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
                DataCell(Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: roleColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(roleName,
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Cairo',
                          color: roleColor,
                          fontWeight: FontWeight.bold)),
                )),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.lock_reset_rounded,
                        color: _gold, size: 20),
                    onPressed: () => _showChangePasswordDialog(user),
                    tooltip: 'تغيير كلمة المرور',
                  ),
                  IconButton(
                    icon: const Icon(Icons.manage_accounts_rounded,
                        color: Colors.blueAccent, size: 20),
                    onPressed: () => _showEditRoleDialog(user),
                    tooltip: 'تعديل الصلاحيات',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete,
                        color: Colors.redAccent, size: 20),
                    onPressed: () => _confirmDeleteUser(user),
                    tooltip: 'حذف المستخدم',
                  ),
                ])),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ─────────────────── Technicians Table ──────────────────────────
  Widget _buildTechniciansContent(
      Color textColor, Color textMuted, Color cardBg) {
    if (_isLoadingTechs) {
      return SkeletonLoading.dashboardPage(context);
    }
    if (_technicians.isEmpty) {
      return AppEmptyState.noData(
        message: 'لا يوجد فنيون مضافون بعد',
      );
    }
    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            headingTextStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: _gold,
                fontSize: 15),
            dataTextStyle:
                TextStyle(fontFamily: 'Cairo', color: textColor, fontSize: 14),
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('البريد الإلكتروني')),
              DataColumn(label: Text('رقم الهاتف')),
              DataColumn(label: Text('كلمة مرور الموبايل')),
              DataColumn(label: Text('الإجراءات')),
            ],
            rows: _technicians.map((tech) {
              final String name = tech['name'] as String;
              final String phone = tech['phone'] as String;
              final String? email = tech['email'] as String?;
              final bool hasPass =
                  (tech['mobilePasswordHash'] as String?)?.isNotEmpty ?? false;
              return DataRow(cells: [
                DataCell(Text('#${tech['id']}')),
                DataCell(Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(email ?? '',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: textColor, fontSize: 13))),
                DataCell(Text(phone)),
                DataCell(Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasPass
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: hasPass
                            ? Colors.green.withValues(alpha: 0.5)
                            : Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(hasPass ? Icons.lock_rounded : Icons.lock_open_rounded,
                        size: 14,
                        color: hasPass ? Colors.green : Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      hasPass ? 'مُعيَّنة' : 'غير مُعيَّنة',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: hasPass ? Colors.green : Colors.orange),
                    ),
                  ]),
                )),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      icon: const Icon(Icons.edit,
                          color: Colors.blueAccent, size: 20),
                      onPressed: () => _showEditTechnicianDialog(tech),
                      tooltip: 'تعديل بيانات الفني'),
                  IconButton(
                      icon: const Icon(Icons.phone_android_rounded,
                          color: _gold, size: 20),
                      onPressed: () => _showSetMobilePasswordDialog(tech),
                      tooltip: 'تعيين كلمة مرور الموبايل'),
                  IconButton(
                      icon: const Icon(Icons.delete,
                          color: Colors.redAccent, size: 20),
                      onPressed: () => _confirmDeleteTechnician(tech),
                      tooltip: 'حذف الفني'),
                ])),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}
