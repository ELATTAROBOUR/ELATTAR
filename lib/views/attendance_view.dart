import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../models.dart';

/// 🌟 Attendance View - نظام الحضور والانصراف
class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Attendance> _todayRecords = [];
  List<Attendance> _historyRecords = [];
  List<AppUser> _users = [];
  List<Map<String, String>> _technicians = [];
  AppUser? _currentUser;
  bool _loading = true;
  String? _currentUserName;
  String? _currentUserRole;

  // Date range for history
  DateTime _historyStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _historyEnd = DateTime.now();

  // Stats
  Map<String, dynamic> _stats = {};
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadData();
    // Auto-refresh the attendance tables and stats every 5 seconds in the background
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _autoRefresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _autoRefresh() async {
    if (_isRefreshing || _loading) return;
    _isRefreshing = true;
    try {
      final todayRecs = await DatabaseHelper.getTodayAttendance();
      final historyRecs = await DatabaseHelper.getAttendanceByDateRange(
        DateFormat('yyyy-MM-dd').format(_historyStart),
        DateFormat('yyyy-MM-dd').format(_historyEnd),
      );
      final stats = await DatabaseHelper.getAttendanceStats(
        DateFormat('yyyy-MM-dd').format(_historyStart),
        DateFormat('yyyy-MM-dd').format(_historyEnd),
      );
      if (mounted) {
        setState(() {
          _todayRecords = todayRecs;
          _historyRecords = historyRecs;
          _stats = stats;
        });
      }
    } catch (e) {
      debugPrint('Error auto-refreshing attendance: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _users = await DatabaseHelper.loadUsers();
      _technicians = await DatabaseHelper.loadTechnicians();
      _todayRecords = await DatabaseHelper.getTodayAttendance();
      _historyRecords = await DatabaseHelper.getAttendanceByDateRange(
        DateFormat('yyyy-MM-dd').format(_historyStart),
        DateFormat('yyyy-MM-dd').format(_historyEnd),
      );
      _stats = await DatabaseHelper.getAttendanceStats(
        DateFormat('yyyy-MM-dd').format(_historyStart),
        DateFormat('yyyy-MM-dd').format(_historyEnd),
      );
      _currentUser = DatabaseHelper.currentLoggedInUser;
      final rawName = _currentUser?.name ?? _currentUser?.email ?? '';
      _currentUserName = _getDisplayName(rawName);
      _currentUserRole = _currentUser?.role ?? 'staff';
    } catch (e) {
      debugPrint('Error loading attendance data: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Get today's status for a user
  Attendance? _getTodayRecord(String userName) {
    try {
      // 1. Try direct match (userName could be name or email)
      return _todayRecords.firstWhere(
        (r) => r.userName.trim().toLowerCase() == userName.trim().toLowerCase()
      );
    } catch (_) {
      // 2. Fallback: If the user is a technician, look up their email from the technicians table
      // and check if they have an attendance record under that email.
      try {
        final tech = _technicians.firstWhere(
          (t) => (t['name'] ?? '').trim().toLowerCase() == userName.trim().toLowerCase(),
          orElse: () => {},
        );
        if (tech.isNotEmpty && tech['email'] != null && tech['email']!.isNotEmpty) {
          final email = tech['email']!.trim().toLowerCase();
          return _todayRecords.firstWhere(
            (r) => r.userName.trim().toLowerCase() == email
          );
        }
      } catch (_) {}
      return null;
    }
  }

  /// Get display name for a user name / email
  String _getDisplayName(String userName) {
    if (userName.contains('@')) {
      try {
        final tech = _technicians.firstWhere(
          (t) => (t['email'] ?? '').trim().toLowerCase() == userName.trim().toLowerCase(),
          orElse: () => {},
        );
        if (tech.isNotEmpty && tech['name'] != null && tech['name']!.isNotEmpty) {
          return tech['name']!;
        }
      } catch (_) {}
      
      try {
        final user = _users.firstWhere(
          (u) => u.email.trim().toLowerCase() == userName.trim().toLowerCase(),
        );
        if (user.name != null && user.name!.trim().isNotEmpty) {
          return user.name!;
        }
      } catch (_) {}
    }
    return userName;
  }

  /// Get combined list of all people (users + technicians)
  List<_Person> get _allPeople {
    final people = <_Person>[];
    final seen = <String>{};

    for (var u in _users) {
      var name = u.name ?? u.email;
      if (u.role == 'technician') {
        try {
          final tech = _technicians.firstWhere(
            (t) => (t['email'] ?? '').trim().toLowerCase() == u.email.trim().toLowerCase(),
            orElse: () => {},
          );
          if (tech.isNotEmpty && tech['name'] != null && tech['name']!.isNotEmpty) {
            name = tech['name']!;
          }
        } catch (_) {}
      }
      if (name.isNotEmpty && !seen.contains(name)) {
        seen.add(name);
        people.add(_Person(name: name, role: u.role, userId: u.id));
      }
    }

    // Include technicians not already covered by users
    for (var t in _technicians) {
      final name = t['name'] ?? '';
      if (name.isNotEmpty && !seen.contains(name)) {
        seen.add(name);
        people.add(_Person(name: name, role: 'technician'));
      }
    }

    // If no people found, add a default "current user" entry
    if (people.isEmpty &&
        _currentUserName != null &&
        _currentUserName!.isNotEmpty) {
      people.add(_Person(
        name: _currentUserName!,
        role: _currentUserRole ?? 'staff',
      ));
    }

    return people;
  }

  Future<void> _checkIn(String userName, String userRole) async {
    final result = await DatabaseHelper.checkIn(userName, userRole);
    if (result != null) {
      _showSnackBar('✅ تم تسجيل الحضور بنجاح');
      _loadData();
    } else {
      _showSnackBar('⚠️ حدث خطأ أثناء تسجيل الحضور');
    }
  }

  Future<void> _checkOut(String userName) async {
    final success = await DatabaseHelper.checkOut(userName);
    if (success) {
      _showSnackBar('✅ تم تسجيل الانصراف بنجاح');
      _loadData();
    } else {
      _showSnackBar('⚠️ لم يتم العثور على تسجيل حضور اليوم');
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayStr =
        DateFormat('yyyy/MM/dd - EEEE', 'ar').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📋 نظام الحضور والانصراف',
                style: TextStyle(fontSize: 18)),
            Text(todayStr,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.today), text: 'اليوم'),
            Tab(icon: Icon(Icons.history), text: 'السجل'),
            Tab(icon: Icon(Icons.analytics), text: 'الإحصائيات'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTodayTab(),
                _buildHistoryTab(),
                _buildStatsTab(),
              ],
            ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TODAY TAB
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTodayTab() {
    final people = _allPeople;

    return Column(
      children: [
        // Current user quick check-in/out card
        if (_currentUserName != null && _currentUserName!.isNotEmpty)
          _buildCurrentUserCard(),

        const Divider(height: 1),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.people, size: 20),
              const SizedBox(width: 8),
              Text('الموظفون والفنيون (${people.length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              Text(
                'الحاضر: ${_todayRecords.where((r) => r.checkOut == null).length}',
                style: TextStyle(
                    color: Colors.green[700], fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        // People list
        Expanded(
          child: people.isEmpty
              ? const Center(
                  child: Text('لا يوجد موظفون أو فنيون بعد',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (context, index) {
                      final person = people[index];
                      final record = _getTodayRecord(person.name);
                      final isCheckedIn = record != null;
                      final isCheckedOut =
                          isCheckedIn && record!.checkOut != null;
                      final isCurrentUser = person.name == _currentUserName;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCheckedOut
                                ? Colors.grey[300]
                                : isCheckedIn
                                    ? Colors.green[100]
                                    : Colors.orange[100],
                            child: Icon(
                              isCheckedOut
                                  ? Icons.logout
                                  : isCheckedIn
                                      ? Icons.check_circle
                                      : Icons.access_time,
                              color: isCheckedOut
                                  ? Colors.grey
                                  : isCheckedIn
                                      ? Colors.green
                                      : Colors.orange,
                            ),
                          ),
                          title: Text(
                            person.name,
                            style: TextStyle(
                              fontWeight: isCurrentUser
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            isCheckedOut
                                ? 'انصراف: ${record!.formattedCheckOut} (${record.formattedDuration})'
                                : isCheckedIn
                                    ? 'حضور: ${record!.formattedCheckIn}'
                                    : 'لم يسجل الحضور بعد',
                            style: TextStyle(
                              color: isCheckedOut
                                  ? Colors.grey
                                  : isCheckedIn
                                      ? Colors.green[700]
                                      : Colors.orange[700],
                            ),
                          ),
                          trailing: isCurrentUser
                              ? _buildCheckButton(
                                  person, isCheckedIn, isCheckedOut)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Card showing current user's status with big check-in/out button
  Widget _buildCurrentUserCard() {
    final person = _allPeople.cast<_Person?>().firstWhere(
          (p) => p!.name == _currentUserName,
          orElse: () => null,
        );
    final record = person != null ? _getTodayRecord(person.name) : null;
    final isCheckedIn = record != null;
    final isCheckedOut = isCheckedIn && record!.checkOut != null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCheckedOut
              ? [Colors.grey[100]!, Colors.grey[200]!]
              : isCheckedIn
                  ? [Colors.green[50]!, Colors.green[100]!]
                  : [Colors.orange[50]!, Colors.orange[100]!],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCheckedOut
              ? Colors.grey
              : isCheckedIn
                  ? Colors.green
                  : Colors.orange,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isCheckedOut
                    ? Icons.logout
                    : isCheckedIn
                        ? Icons.check_circle
                        : Icons.access_time,
                color: isCheckedOut
                    ? Colors.grey
                    : isCheckedIn
                        ? Colors.green
                        : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرحباً، $_currentUserName',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      isCheckedOut
                          ? 'تم الانصراف الساعة ${record!.formattedCheckOut}'
                          : isCheckedIn
                              ? 'تم الحضور الساعة ${record!.formattedCheckIn}'
                              : 'لم تسجل الحضور بعد',
                      style: TextStyle(
                        color: isCheckedOut
                            ? Colors.grey[600]
                            : isCheckedIn
                                ? Colors.green[700]
                                : Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                if (isCheckedOut) {
                  _checkIn(_currentUserName!, _currentUserRole ?? 'staff');
                } else if (isCheckedIn) {
                  _checkOut(_currentUserName!);
                } else {
                  _checkIn(_currentUserName!, _currentUserRole ?? 'staff');
                }
              },
              icon: Icon(isCheckedOut
                  ? Icons.login
                  : isCheckedIn
                      ? Icons.logout
                      : Icons.login),
              label: Text(
                isCheckedOut
                    ? 'تسجيل حضور مرة أخرى'
                    : isCheckedIn
                        ? 'تسجيل انصراف'
                        : 'تسجيل حضور',
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isCheckedOut
                    ? Colors.grey
                    : isCheckedIn
                        ? Colors.orange
                        : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildCheckButton(
      _Person person, bool isCheckedIn, bool isCheckedOut) {
    if (isCheckedOut) {
      return const Icon(Icons.done_all, color: Colors.grey);
    }
    if (isCheckedIn) {
      return IconButton(
        icon: const Icon(Icons.logout, color: Colors.orange),
        tooltip: 'تسجيل انصراف',
        onPressed: () => _checkOut(person.name),
      );
    }
    return IconButton(
      icon: const Icon(Icons.login, color: Colors.green),
      tooltip: 'تسجيل حضور',
      onPressed: () => _checkIn(person.name, person.role),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HISTORY TAB
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Date range picker
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'من تاريخ',
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: Text(
                      DateFormat('yyyy/MM/dd').format(_historyStart),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('→'),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(false),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'إلى تاريخ',
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    child: Text(
                      DateFormat('yyyy/MM/dd').format(_historyEnd),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _loadHistory,
                tooltip: 'بحث',
              ),
            ],
          ),
        ),

        // Records count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('إجمالي السجلات: ${_historyRecords.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),

        // History list
        Expanded(
          child: _historyRecords.isEmpty
              ? const Center(
                  child: Text('لا توجد سجلات في هذه الفترة',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    itemCount: _historyRecords.length,
                    itemBuilder: (context, index) {
                      final r = _historyRecords[index];
                      final statusIcon = _getStatusIcon(r.status);
                      final statusColor = _getStatusColor(r.status);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withAlpha(50),
                            child: Text(statusIcon,
                                style: TextStyle(fontSize: 20)),
                          ),
                           title: Text(_getDisplayName(r.userName)),
                          subtitle: Text(
                            '${r.date} | حضور: ${r.formattedCheckIn} | انصراف: ${r.formattedCheckOut} | ${r.formattedDuration}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Text(
                            _getStatusLabel(r.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          onLongPress: _currentUserRole == 'manager'
                              ? () => _showEditDialog(r)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _historyStart : _historyEnd,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _historyStart = picked;
        } else {
          _historyEnd = picked;
        }
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    _historyRecords = await DatabaseHelper.getAttendanceByDateRange(
      DateFormat('yyyy-MM-dd').format(_historyStart),
      DateFormat('yyyy-MM-dd').format(_historyEnd),
    );
    _stats = await DatabaseHelper.getAttendanceStats(
      DateFormat('yyyy-MM-dd').format(_historyStart),
      DateFormat('yyyy-MM-dd').format(_historyEnd),
    );
    if (mounted) setState(() => _loading = false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STATS TAB
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStatsTab() {
    final total = (_stats['present'] as int? ?? 0) +
        (_stats['late'] as int? ?? 0) +
        (_stats['absent'] as int? ?? 0) +
        (_stats['halfDay'] as int? ?? 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Text(
            'ملخص ${DateFormat('yyyy/MM/dd').format(_historyStart)} - ${DateFormat('yyyy/MM/dd').format(_historyEnd)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              _buildStatCard('أيام', '${_stats['totalDays'] ?? 0}',
                  Icons.date_range, Colors.blue),
              const SizedBox(width: 8),
              _buildStatCard('موظفين', '${_stats['totalUsers'] ?? 0}',
                  Icons.people, Colors.purple),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatCard('حضور', '${_stats['present'] ?? 0}',
                  Icons.check_circle, Colors.green),
              const SizedBox(width: 8),
              _buildStatCard('متأخر', '${_stats['late'] ?? 0}', Icons.warning,
                  Colors.orange),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatCard(
                  'غياب', '${_stats['absent'] ?? 0}', Icons.cancel, Colors.red),
              const SizedBox(width: 8),
              _buildStatCard('نصف يوم', '${_stats['halfDay'] ?? 0}',
                  Icons.cloud, Colors.teal),
            ],
          ),

          const SizedBox(height: 24),
          const Text('نسبة الحضور',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          if (total > 0)
            LinearProgressIndicator(
              value: ((_stats['present'] as int? ?? 0) +
                      (_stats['late'] as int? ?? 0)) /
                  total,
              backgroundColor: Colors.red[100],
              color: Colors.green,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
            ),
          const SizedBox(height: 8),
          Text(
            total > 0
                ? '${(((_stats['present'] as int? ?? 0) + (_stats['late'] as int? ?? 0)) * 100 / total).toStringAsFixed(1)}% نسبة الحضور الإجمالية'
                : 'لا توجد بيانات',
            style: const TextStyle(color: Colors.grey),
          ),

          if (_currentUserRole == 'manager') ...[
            const SizedBox(height: 24),
            const Text('إدارة السجلات',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showManualEntryDialog(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة تسجيل يدوي'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DIALOGS
  // ───────────────────────────────────────────────────────────────────────────

  /// Edit attendance record dialog (admin only)
  Future<void> _showEditDialog(Attendance record) async {
    final statusController = TextEditingController(text: record.status);
    final notesController = TextEditingController(text: record.notes ?? '');
    String selectedStatus = record.status;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل تسجيل حضور'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الموظف: ${_getDisplayName(record.userName)}'),
                Text('التاريخ: ${record.date}'),
                Text('الحضور: ${record.formattedCheckIn}'),
                Text('الانصراف: ${record.formattedCheckOut}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'present', child: Text('✅ حاضر')),
                    DropdownMenuItem(value: 'late', child: Text('⚠️ متأخر')),
                    DropdownMenuItem(value: 'absent', child: Text('❌ غائب')),
                    DropdownMenuItem(
                        value: 'half_day', child: Text('🌤️ نصف يوم')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedStatus = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                record.status = selectedStatus;
                record.notes = notesController.text;
                await DatabaseHelper.updateAttendance(record);
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _showSnackBar('✅ تم تحديث السجل');
      _loadData();
    }
  }

  /// Manual attendance entry dialog (admin only)
  Future<void> _showManualEntryDialog() async {
    final people = _allPeople;
    String? selectedPerson;
    String selectedStatus = 'present';
    final dateController = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final timeInController =
        TextEditingController(text: DateFormat('HH:mm').format(DateTime.now()));
    final timeOutController = TextEditingController();
    final notesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة تسجيل حضور يدوي'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedPerson,
                  decoration: const InputDecoration(
                    labelText: 'الموظف',
                    border: OutlineInputBorder(),
                  ),
                  items: people
                      .map((p) =>
                          DropdownMenuItem(value: p.name, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedPerson = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: 'التاريخ (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeInController,
                  decoration: const InputDecoration(
                    labelText: 'وقت الحضور (HH:mm)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeOutController,
                  decoration: const InputDecoration(
                    labelText: 'وقت الانصراف (HH:mm) - اختياري',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'present', child: Text('✅ حاضر')),
                    DropdownMenuItem(value: 'late', child: Text('⚠️ متأخر')),
                    DropdownMenuItem(value: 'absent', child: Text('❌ غائب')),
                    DropdownMenuItem(
                        value: 'half_day', child: Text('🌤️ نصف يوم')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedStatus = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (selectedPerson == null) {
                  _showSnackBar('⚠️ الرجاء اختيار الموظف');
                  return;
                }
                final person = people.firstWhere(
                    (p) => p.name == selectedPerson,
                    orElse: () => _Person(name: '', role: ''));
                final date = dateController.text.trim();
                final timeIn = timeInController.text.trim();
                final timeOut = timeOutController.text.trim();

                if (date.isEmpty || timeIn.isEmpty) {
                  _showSnackBar('⚠️ الرجاء إدخال التاريخ ووقت الحضور');
                  return;
                }

                final checkInDt = DateTime.tryParse('${date}T$timeIn:00');
                if (checkInDt == null) {
                  _showSnackBar('⚠️ صيغة التاريخ أو الوقت غير صحيحة');
                  return;
                }

                try {
                  final db = await DatabaseHelper.db;
                  await db.insert('attendance', {
                    'userName': selectedPerson,
                    'userRole': person.role,
                    'date': date,
                    'checkIn': checkInDt.toIso8601String(),
                    'checkOut': timeOut.isNotEmpty
                        ? DateTime.tryParse('${date}T$timeOut:00')
                            ?.toIso8601String()
                        : null,
                    'status': selectedStatus,
                    if (notesController.text.trim().isNotEmpty)
                      'notes': notesController.text.trim(),
                  });
                  await DatabaseHelper.syncDatabase();
                  if (context.mounted) Navigator.pop(context);
                  _showSnackBar('✅ تم إضافة التسجيل');
                  _loadData();
                } catch (e) {
                  _showSnackBar('⚠️ خطأ: $e');
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ───────────────────────────────────────────────────────────────────────────

  String _getStatusIcon(String status) {
    switch (status) {
      case 'present':
        return '✅';
      case 'late':
        return '⚠️';
      case 'absent':
        return '❌';
      case 'half_day':
        return '🌤️';
      default:
        return '❓';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'half_day':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'present':
        return 'حاضر';
      case 'late':
        return 'متأخر';
      case 'absent':
        return 'غائب';
      case 'half_day':
        return 'نصف يوم';
      default:
        return status;
    }
  }
}

/// Internal helper to represent a person (user or technician)
class _Person {
  final String name;
  final String role;
  final int? userId;

  _Person({
    required this.name,
    required this.role,
    this.userId,
  });
}
