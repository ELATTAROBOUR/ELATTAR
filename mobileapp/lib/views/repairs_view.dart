import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../print_service.dart';
import 'repair_widgets.dart';

class RepairsView extends StatefulWidget {
  final String?
  technicianFilter; // email of logged-in technician, null = show all
  const RepairsView({super.key, this.technicianFilter});

  @override
  State<RepairsView> createState() => _RepairsViewState();
}

class _RepairsViewState extends State<RepairsView> {
  List<Ticket> tickets = [];
  List<SparePart> spareParts = [];
  List<Ticket> filteredTickets = [];
  String searchQuery = '';
  int nextTicketId = 1;
  int nextPartId = 1;

  DateTime? startDate;
  DateTime? endDate;
  String selectedDateFilter = 'الكل';
  String selectedStatusFilter = 'الكل';

  List<Map<String, String>> technicians = [];

  final String cloudApiUrl = 'https://api.sms-gate.app/3rdparty/v1';
  final String smsUsername = '2UOQVM';
  final String smsPassword = 'nbzkeqb5xe2aq8';

  bool _isDialogOpen = false;
  final bool enableSMS = false;

  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadData();

    // Set up a periodic timer to sync and refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) return;
      if (_isRefreshing) return;

      _isRefreshing = true;
      try {
        // 1. Perform background database sync with GitHub
        await DatabaseHelper.syncDatabase();

        if (!mounted) return;

        // 2. Reload tickets, spare parts, and technicians from the newly merged database
        await _loadTickets();
        await _loadSpareParts();
        await _loadTechnicians();

        // 3. Filter and update the UI
        _filterTickets();
      } catch (e) {
        debugPrint('Error in periodic refresh: $e');
      } finally {
        _isRefreshing = false;
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _loadTickets();
    await _loadSpareParts();
    await _loadTechnicians();
    _filterTickets();
  }

  Future<void> _loadTickets() async {
    try {
      tickets = await DatabaseHelper.loadTickets();
      final maxId = tickets.isEmpty
          ? 0
          : tickets.map((t) => t.id).reduce((a, b) => a > b ? a : b);
      nextTicketId = DatabaseHelper.generateNextIdFromMax(maxId);
    } catch (e) {
      debugPrint('Error loading tickets: $e');
    }
  }

  Future<void> _loadSpareParts() async {
    try {
      spareParts = await DatabaseHelper.loadSpareParts();
      final maxId = spareParts.isEmpty
          ? 0
          : spareParts.map((p) => p.id).reduce((a, b) => a > b ? a : b);
      nextPartId = DatabaseHelper.generateNextIdFromMax(maxId);
    } catch (e) {
      debugPrint('Error loading spare parts: $e');
    }
  }

  Future<void> _loadTechnicians() async {
    try {
      final loadedTechs = await DatabaseHelper.loadTechnicians();
      if (loadedTechs.isNotEmpty) {
        setState(() {
          technicians = loadedTechs;
        });
      }
    } catch (e) {
      debugPrint('Error loading technicians: $e');
    }
  }

  Future<void> saveTickets() async {
    try {
      await DatabaseHelper.saveTickets(tickets);
    } catch (e) {
      debugPrint('Error saving tickets: $e');
    }
  }

  Future<void> saveSpareParts() async {
    try {
      await DatabaseHelper.saveSpareParts(spareParts);
    } catch (e) {
      debugPrint('Error saving spare parts: $e');
    }
  }

  void _filterTickets() {
    setState(() {
      filteredTickets = tickets.where((t) {
        // Role-based filter: if technicianFilter is set, only show tickets for this technician
        bool matchesTechnician = true;
        if (widget.technicianFilter != null) {
          final filterVal = widget.technicianFilter!.trim().toLowerCase();

          // Resolve the technician's name and email
          String? techName;
          String? techEmail;

          if (filterVal.contains('@')) {
            // The filter passed in is an email
            techEmail = filterVal;
            // 1. Try looking up in the technicians list FIRST (authoritative source)
            final techMatch = technicians.firstWhere(
              (tech) => tech['email']?.toLowerCase() == techEmail,
              orElse: () => <String, String>{},
            );
            if (techMatch.isNotEmpty &&
                techMatch['name'] != null &&
                techMatch['name']!.isNotEmpty) {
              techName = techMatch['name'];
            }
            // 2. Fallback to name from currentLoggedInUser if technicians lookup didn't work
            if ((techName == null || techName!.isEmpty) &&
                currentLoggedInUser?.email.toLowerCase() == techEmail) {
              techName = currentLoggedInUser?.name;
            }
            // 3. Smart Fallback: Match by transliterating Arabic names and comparing with email prefix
            if (techName == null || techName.isEmpty) {
              final emailPrefix = techEmail
                  .split('@')
                  .first
                  .trim()
                  .toLowerCase();
              final cleanPrefix = _toVowelFreeTransliterated(emailPrefix);

              if (cleanPrefix.isNotEmpty) {
                for (var tech in technicians) {
                  final tName = tech['name'] ?? '';
                  if (tName.isNotEmpty) {
                    final cleanTName = _toVowelFreeTransliterated(tName);
                    if (cleanTName.contains(cleanPrefix) ||
                        cleanPrefix.contains(cleanTName)) {
                      techName = tName;
                      debugPrint(
                        'Smart Match: Matched email $techEmail to technician $tName',
                      );
                      break;
                    }
                  }
                }
              }
            }
          } else {
            // The filter passed in is already a name
            techName = filterVal;
            // Try to find the email in technicians table just in case we need it
            final techMatch = technicians.firstWhere(
              (tech) => tech['name']?.toLowerCase() == techName?.toLowerCase(),
              orElse: () => {},
            );
            techEmail = techMatch['email']?.toLowerCase();
          }

          // Robust Matching
          matchesTechnician = false;

          // 1. Match by resolved techName
          if (techName != null && techName.isNotEmpty) {
            if (_namesMatch(t.technicianName, techName)) {
              matchesTechnician = true;
            }
          }

          // 2. Fallback: Match by resolved techEmail (partial match with username part)
          if (!matchesTechnician && techEmail != null && techEmail.isNotEmpty) {
            final emailPrefix = techEmail.split('@').first.trim().toLowerCase();
            if (t.technicianName != null &&
                _namesMatch(t.technicianName, emailPrefix)) {
              matchesTechnician = true;
            }
          }

          // 3. Extreme fallback: Match ticket's technicianName against the raw filter value
          if (!matchesTechnician) {
            if (_namesMatch(t.technicianName, filterVal)) {
              matchesTechnician = true;
            }
          }
        }

        bool matchesSearch = true;
        if (searchQuery.isNotEmpty) {
          final query = searchQuery.trim().toLowerCase();
          int? idSearch = int.tryParse(query);
          matchesSearch =
              (idSearch != null && t.id == idSearch) ||
              t.customerName.toLowerCase().contains(query) ||
              t.customerPhone.contains(query) ||
              t.deviceModel.toLowerCase().contains(query) ||
              (t.technicianName?.toLowerCase().contains(query) ?? false);
        }

        bool matchesStatus = true;
        if (selectedStatusFilter != 'الكل') {
          matchesStatus = t.status == selectedStatusFilter;
        }

        bool matchesDate = true;
        if (startDate != null) {
          final tDate = DateTime(
            t.receivedDate.year,
            t.receivedDate.month,
            t.receivedDate.day,
          );
          final start = DateTime(
            startDate!.year,
            startDate!.month,
            startDate!.day,
          );
          if (tDate.isBefore(start)) matchesDate = false;
        }
        if (endDate != null && matchesDate) {
          final tDate = DateTime(
            t.receivedDate.year,
            t.receivedDate.month,
            t.receivedDate.day,
          );
          final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
          if (tDate.isAfter(end)) matchesDate = false;
        }

        return matchesTechnician &&
            matchesSearch &&
            matchesStatus &&
            matchesDate;
      }).toList();
    });
  }

  String _toVowelFreeTransliterated(String text) {
    // 1. Transliterate common Arabic characters to English
    final Map<String, String> map = {
      'أ': 'a',
      'إ': 'a',
      'آ': 'a',
      'ا': 'a',
      'ع': 'a',
      'ب': 'b',
      'ت': 't',
      'ة': 't',
      'ط': 't',
      'ث': 's',
      'س': 's',
      'ص': 's',
      'ج': 'j',
      'ح': 'h',
      'خ': 'h',
      'ه': 'h',
      'د': 'd',
      'ض': 'd',
      'ذ': 'z',
      'ز': 'z',
      'ظ': 'z',
      'ر': 'r',
      'ش': 'sh',
      'ف': 'f',
      'ق': 'q',
      'ك': 'k',
      'ل': 'l',
      'م': 'm',
      'ن': 'n',
      'و': 'w',
      'ي': 'y',
      'ى': 'y',
      'ئ': 'y',
      'ء': 'a',
    };

    String transliterated = "";
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      transliterated += map[char] ?? char;
    }

    // 2. Remove vowels and spaces/special characters
    final vowels = RegExp(r'[aeiouy\s\-_.]');
    return transliterated.toLowerCase().replaceAll(vowels, '');
  }

  String _normalizeArabic(String text) {
    // Remove common diacritics and normalize characters
    final Map<String, String> normMap = {
      'أ': 'ا',
      'إ': 'ا',
      'آ': 'ا',
      'ة': 'ه',
      'ى': 'ي',
    };

    String normalized = "";
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      normalized += normMap[char] ?? char;
    }

    // Remove tatweel, diacritics, and all spaces to allow perfect matches
    return normalized
        .replaceAll(RegExp(r'[\u064B-\u0652]'), '') // remove diacritics
        .replaceAll('ـ', '') // remove kashida
        .replaceAll(RegExp(r'\s+'), '') // remove all spaces
        .trim()
        .toLowerCase();
  }

  bool _namesMatch(String? name1, String? name2) {
    if (name1 == null || name2 == null) return false;
    final n1 = name1.trim().toLowerCase();
    final n2 = name2.trim().toLowerCase();
    if (n1 == n2) return true;

    final norm1 = _normalizeArabic(n1);
    final norm2 = _normalizeArabic(n2);
    if (norm1.isNotEmpty && norm2.isNotEmpty) {
      if (norm1 == norm2 || norm1.contains(norm2) || norm2.contains(norm1)) {
        return true;
      }
    }

    final trans1 = _toVowelFreeTransliterated(n1);
    final trans2 = _toVowelFreeTransliterated(n2);
    if (trans1.isNotEmpty && trans2.isNotEmpty) {
      if (trans1 == trans2 ||
          trans1.contains(trans2) ||
          trans2.contains(trans1)) {
        return true;
      }
    }

    return false;
  }

  void filterByDateRange() {
    setState(() {
      if (selectedDateFilter == 'الكل') {
        startDate = null;
        endDate = null;
      } else if (selectedDateFilter == 'اليوم') {
        final now = DateTime.now();
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (selectedDateFilter == 'هذا الشهر') {
        final now = DateTime.now();
        startDate = DateTime(now.year, now.month, 1);
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        endDate = nextMonth.subtract(const Duration(days: 1));
      }
      _filterTickets();
    });
  }

  Future<void> selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      locale: const Locale('ar', 'EG'),
      helpText: 'اختر نطاق التاريخ',
      saveText: 'حفظ',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFD4AF37),
              onPrimary: Color(0xFF1A2A3A),
              surface: Color(0xFF1A2A3A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        startDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        selectedDateFilter = 'مخصص';
        _filterTickets();
      });
    }
  }

  void clearDateFilter() {
    setState(() {
      startDate = null;
      endDate = null;
      selectedDateFilter = 'الكل';
      _filterTickets();
    });
  }

  void deductParts(String? partsUsedJson) {
    if (partsUsedJson == null || partsUsedJson.isEmpty) return;
    try {
      final List decoded = jsonDecode(partsUsedJson);
      for (var item in decoded) {
        final int partId = item['partId'];
        final int qtyUsed = item['quantity'];
        final index = spareParts.indexWhere((p) => p.id == partId);
        if (index != -1) {
          spareParts[index].quantity = (spareParts[index].quantity - qtyUsed)
              .clamp(0, 999999);
        }
      }
      saveSpareParts();
    } catch (e) {
      debugPrint('Error deducting parts: $e');
    }
  }

  void adjustPartsInventory(String? oldPartsJson, String? newPartsJson) {
    if (oldPartsJson != null && oldPartsJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(oldPartsJson);
        for (var item in decoded) {
          final int partId = item['partId'];
          final int qtyUsed = item['quantity'];
          final index = spareParts.indexWhere((p) => p.id == partId);
          if (index != -1) {
            spareParts[index].quantity += qtyUsed;
          }
        }
      } catch (e) {
        debugPrint('Error restoring old parts: $e');
      }
    }
    if (newPartsJson != null && newPartsJson.isNotEmpty) {
      try {
        final List decoded = jsonDecode(newPartsJson);
        for (var item in decoded) {
          final int partId = item['partId'];
          final int qtyUsed = item['quantity'];
          final index = spareParts.indexWhere((p) => p.id == partId);
          if (index != -1) {
            spareParts[index].quantity = (spareParts[index].quantity - qtyUsed)
                .clamp(0, 999999);
          }
        }
      } catch (e) {
        debugPrint('Error deducting new parts: $e');
      }
    }
    saveSpareParts();
  }

  void restoreParts(String? partsUsedJson) {
    if (partsUsedJson == null || partsUsedJson.isEmpty) return;
    try {
      final List decoded = jsonDecode(partsUsedJson);
      for (var item in decoded) {
        final int partId = item['partId'];
        final int qtyUsed = item['quantity'];
        final index = spareParts.indexWhere((p) => p.id == partId);
        if (index != -1) {
          spareParts[index].quantity += qtyUsed;
        }
      }
      saveSpareParts();
    } catch (e) {
      debugPrint('Error restoring parts: $e');
    }
  }

  Future<void> sendSMS(
    String phoneNumber,
    String customerName,
    int ticketId,
    String deviceModel,
    String technicianName,
    String technicianPhone,
    String complaintNumber,
  ) async {
    if (!enableSMS) return;
    final message =
        "🌹 مرحباً $customerName، \n🌹 اهلاً وسهلاً بكم في محلات العطار استور\n✅ تم استلام جهازكم ( $deviceModel ) بنجاح\n🆔 رقم الايصال: $ticketId\n👨‍🔧 الفني المسؤول: $technicianName\n🔧 جاري العمل علي اصلاح العطل\nشكراً لثقتكم بنا 🌹";

    String cleanNumber = phoneNumber.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNumber.startsWith('0')) cleanNumber = cleanNumber.substring(1);
    final String formattedPhone = '+20$cleanNumber';
    final String basicAuth =
        'Basic ${base64Encode(utf8.encode('$smsUsername:$smsPassword'))}';

    try {
      await http
          .post(
            Uri.parse('$cloudApiUrl/messages'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': basicAuth,
            },
            body: json.encode({
              'phoneNumbers': [formattedPhone],
              'textMessage': {'text': message},
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('SMS gateway post failed: $e');
    }
  }

  Future<void> sendReadySMS(
    String phoneNumber,
    String customerName,
    int ticketId,
    String deviceModel,
    String technicianName,
    String technicianPhone,
    String complaintNumber,
  ) async {
    if (!enableSMS) return;
    final message =
        "🌹 مرحباً $customerName، \n🌹 اهلاً وسهلاً بكم في محلات العطار استور\n✅ تم الانتهاء من اصلاح جهازكم ( $deviceModel ) بنجاح\n🆔 رقم الايصال: $ticketId\n📦 جهازكم جاهز للتسليم\nشكراً لثقتكم بنا 🌹";

    String cleanNumber = phoneNumber.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanNumber.startsWith('0')) cleanNumber = cleanNumber.substring(1);
    final String formattedPhone = '+20$cleanNumber';
    final String basicAuth =
        'Basic ${base64Encode(utf8.encode('$smsUsername:$smsPassword'))}';

    try {
      await http
          .post(
            Uri.parse('$cloudApiUrl/messages'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': basicAuth,
            },
            body: json.encode({
              'phoneNumbers': [formattedPhone],
              'textMessage': {'text': message},
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Ready SMS post failed: $e');
    }
  }

  void showAddTicketDialog() {
    if (_isDialogOpen) return;
    _isDialogOpen = true;
    showDialog(
      context: context,
      builder: (context) => TicketDialog(
        technicians: technicians,
        existingTickets: tickets,
        spareParts: spareParts,
        onSave: (ticketData) async {
          final newTicket = Ticket(
            id: nextTicketId,
            customerName: ticketData['customerName'],
            customerPhone: ticketData['customerPhone'],
            deviceModel: ticketData['deviceModel'],
            problem: ticketData['problem'],
            status: ticketData['status'],
            receivedDate: DateTime.now(),
            cost: ticketData['cost'],
            notes: ticketData['notes'],
            agent: ticketData['agent'],
            deviceCondition: ticketData['deviceCondition'] ?? '',
            technicianName: ticketData['technicianName'],
            technicianPhone: ticketData['technicianPhone'],
            complaintNumber: DatabaseHelper.complaintNumber,
            partsCost: ticketData['partsCost'] ?? 0.0,
            partsUsed: ticketData['partsUsed'],
            commissionRate: ticketData['commissionRate'] ?? 50.0,
            isClosed: 0,
            expectedDelivery: ticketData['expectedDelivery'],
          );

          setState(() {
            tickets.insert(0, newTicket);
            _filterTickets();
            nextTicketId += 10;
          });

          await saveTickets();
          await DatabaseHelper.logModification(
            actionType: 'إضافة',
            itemType: 'صيانة',
            itemName: newTicket.deviceModel,
            details:
                'إيصال صيانة للعميل: ${newTicket.customerName} بقيمة ${newTicket.cost} ج.م',
          );
          deductParts(newTicket.partsUsed);

          sendSMS(
            ticketData['customerPhone'],
            ticketData['customerName'],
            newTicket.id,
            ticketData['deviceModel'],
            ticketData['technicianName'],
            ticketData['technicianPhone'],
            DatabaseHelper.complaintNumber,
          ).catchError((e) => debugPrint('SMS failed: $e'));

          // 🔄 Push changes to GitHub
          DatabaseHelper.syncDatabase();
        },
      ),
    ).then((_) => _isDialogOpen = false);
  }

  void showEditTicketDialog(Ticket ticket) {
    if (ticket.isClosed == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ لا يمكن تعديل هذا الإيصال لأنه مغلق بالتقفيل المالي',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isDialogOpen) return;
    _isDialogOpen = true;
    String oldStatus = ticket.status;
    showDialog(
      context: context,
      builder: (context) => TicketDialog(
        technicians: technicians,
        ticket: ticket,
        existingTickets: tickets,
        spareParts: spareParts,
        onSave: (ticketData) async {
          setState(() {
            final index = tickets.indexWhere((t) => t.id == ticket.id);
            if (index != -1) {
              final oldPartsUsed = tickets[index].partsUsed;
              tickets[index].customerName = ticketData['customerName'];
              tickets[index].customerPhone = ticketData['customerPhone'];
              tickets[index].deviceModel = ticketData['deviceModel'];
              tickets[index].problem = ticketData['problem'];
              tickets[index].status = ticketData['status'];
              tickets[index].updatedAt = DateTime.now().millisecondsSinceEpoch;
              tickets[index].cost = ticketData['cost'];
              tickets[index].notes = ticketData['notes'];
              tickets[index].agent = ticketData['agent'];
              tickets[index].deviceCondition =
                  ticketData['deviceCondition'] ?? '';
              tickets[index].technicianName = ticketData['technicianName'];
              tickets[index].technicianPhone = ticketData['technicianPhone'];
              tickets[index].partsCost = ticketData['partsCost'] ?? 0.0;
              tickets[index].partsUsed = ticketData['partsUsed'];
              tickets[index].commissionRate =
                  ticketData['commissionRate'] ?? 50.0;
              tickets[index].expectedDelivery = ticketData['expectedDelivery'];

              adjustPartsInventory(oldPartsUsed, ticketData['partsUsed']);
              _filterTickets();
            }
          });

          // 1️ أولاً: لو الحالة اتغيرت، التحديث المباشر لـ Supabase (المصدر الرئيسي)
          if (oldStatus != ticketData['status']) {
            await DatabaseHelper.updateTicketStatusInSupabase(
              ticket.id,
              ticketData['status'],
              DateTime.now().millisecondsSinceEpoch,
            );

            // ضبط deliveryDate لو الحالة اتحولت لـ delivered
            if (ticketData['status'] == 'delivered') {
              final index = tickets.indexWhere((t) => t.id == ticket.id);
              if (index != -1) {
                tickets[index].deliveryDate ??= DateTime.now();
              }
            }
          }

          // 2️ ثانياً: الحفظ محلياً كنسخة احتياطية (Cache)
          // saveTickets() بتعمل syncDatabase داخلياً
          await saveTickets();
          await DatabaseHelper.logModification(
            actionType: 'تعديل',
            itemType: 'صيانة',
            itemName: ticket.deviceModel,
            details:
                'تعديل إيصال العميل: ${ticket.customerName}، العطل: ${ticket.problem}، الحالة: ${_getStatusArabic(ticketData['status'])}',
          );

          if (oldStatus != ticketData['status'] &&
              ticketData['status'] == 'repaired') {
            sendReadySMS(
              ticketData['customerPhone'],
              ticketData['customerName'],
              ticket.id,
              ticketData['deviceModel'],
              ticketData['technicianName'],
              ticketData['technicianPhone'],
              DatabaseHelper.complaintNumber,
            ).catchError((e) => debugPrint('SMS failed: $e'));
          }
        },
      ),
    ).then((_) => _isDialogOpen = false);
  }

  void deleteTicket(Ticket ticket) {
    if (ticket.isClosed == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ لا يمكن حذف هذا الإيصال لأنه مغلق بالتقفيل المالي'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        title: const Text(
          'تأكيد الحذف',
          style: TextStyle(color: Colors.redAccent, fontSize: 20),
        ),
        content: Text(
          'هل أنت متأكد من حذف إيصال العميل ${ticket.customerName}؟',
          style: TextStyle(color: AppTheme.text(context), fontSize: 18),
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
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              setState(() {
                tickets.removeWhere((t) => t.id == ticket.id);
                _filterTickets();
              });
              await saveTickets();
              await DatabaseHelper.logModification(
                actionType: 'حذف',
                itemType: 'صيانة',
                itemName: ticket.deviceModel,
                details: 'حذف إيصال الصيانة للعميل ${ticket.customerName}',
              );
              restoreParts(ticket.partsUsed);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حذف', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final primaryGold = const Color(0xFFD4AF37);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryGold,
        foregroundColor: const Color(0xFF1A2A3A),
        onPressed: showAddTicketDialog,
        icon: const Icon(Icons.add, size: 24),
        label: const Text(
          'إضافة إيصال',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: 15,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🔧 قسم الصيانة والتذاكر',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textColor,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'إدارة فواتير وإيصالات الصيانة وتغيير حالات الإصلاح وطباعتها',
              style: TextStyle(
                fontSize: 12,
                color: textMuted,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 12),

            Card(
              color: AppTheme.cardBg(context),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontFamily: 'Cairo',
                            ),
                            decoration: InputDecoration(
                              hintText: 'البحث برقم الإيصال أو اسم العميل...',
                              prefixIcon: Icon(
                                Icons.search,
                                color: primaryGold,
                                size: 20,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {
                                searchQuery = val;
                                _filterTickets();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceTint(context),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border(context)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedDateFilter,
                              dropdownColor: AppTheme.cardBg(context),
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontFamily: 'Cairo',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'الكل',
                                  child: Text('كل التواريخ'),
                                ),
                                DropdownMenuItem(
                                  value: 'اليوم',
                                  child: Text('اليوم'),
                                ),
                                DropdownMenuItem(
                                  value: 'هذا الشهر',
                                  child: Text('هذا الشهر'),
                                ),
                                DropdownMenuItem(
                                  value: 'مخصص',
                                  child: Text('تاريخ مخصص'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val == 'مخصص') {
                                  selectCustomDateRange();
                                } else {
                                  setState(() {
                                    selectedDateFilter = val!;
                                    filterByDateRange();
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        if (selectedDateFilter == 'مخصص' &&
                            startDate != null &&
                            endDate != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: clearDateFilter,
                            tooltip: 'إلغاء تصفية التاريخ',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusChip('الكل', 'الكل'),
                          const SizedBox(width: 6),
                          _buildStatusChip('pending', '⏳ قيد الانتظار'),
                          const SizedBox(width: 6),
                          _buildStatusChip('in_progress', '🔧 تحت الصيانة'),
                          const SizedBox(width: 6),
                          _buildStatusChip('repaired', '✅ تم الإصلاح'),
                          const SizedBox(width: 6),
                          _buildStatusChip('delivered', '📦 تم التسليم'),
                          const SizedBox(width: 6),
                          _buildStatusChip('rejected', '❌ المرفوض'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: filteredTickets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 40,
                            color: textMuted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'لا توجد فواتير صيانة مطابقة للتصفية الحالية',
                            style: TextStyle(
                              fontSize: 14,
                              color: textMuted,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredTickets.length,
                      padding: const EdgeInsets.only(
                        bottom: 80,
                      ), // extra padding for FAB
                      itemBuilder: (context, index) {
                        final ticket = filteredTickets[index];
                        return TicketCard(
                          ticket: ticket,
                          onEdit: () => showEditTicketDialog(ticket),
                          onDelete: () => deleteTicket(ticket),
                          onPreviewLabel: (t) async {
                            try {
                              final bytes = await PrintService.generateLabelPdf(
                                t,
                              );
                              await Printing.layoutPdf(onLayout: (_) => bytes);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ خطأ في المعاينة: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          onPreviewReceipt: (t) async {
                            try {
                              final bytes =
                                  await PrintService.generateReceiptPdf(t);
                              await Printing.layoutPdf(onLayout: (_) => bytes);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ خطأ في المعاينة: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          onPrintLabel: (t) async {
                            try {
                              await PrintService.printLabel(t);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ تمت طباعة الملصق بنجاح'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ خطأ في الطباعة: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          onPrintReceipt: (t) async {
                            try {
                              await PrintService.printReceipt(t);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ تمت طباعة الإيصال بنجاح'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ خطأ في الطباعة: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          onStatusChanged: (t, newStatus) async {
                            String old = t.status;
                            setState(() {
                              t.status = newStatus;
                              t.updatedAt =
                                  DateTime.now().millisecondsSinceEpoch;
                              if (newStatus == 'delivered') {
                                t.deliveryDate = DateTime.now();
                              }
                            });

                            // 1️ أولاً: التحديث المباشر لـ Supabase (المصدر الرئيسي)
                            await DatabaseHelper.updateTicketStatusInSupabase(
                              t.id,
                              newStatus,
                              t.updatedAt!,
                            );

                            // 2️ ثانياً: الحفظ محلياً كنسخة احتياطية (Cache)
                            // saveTickets() بتعمل syncDatabase داخلياً فمش محتاج استدعاء منفصل
                            await saveTickets();

                            await DatabaseHelper.logModification(
                              actionType: 'تعديل حالة',
                              itemType: 'صيانة',
                              itemName: t.deviceModel,
                              details:
                                  'تغيير حالة إيصال العميل ${t.customerName} إلى ${_getStatusArabic(newStatus)}',
                            );
                            _filterTickets();

                            if (old != newStatus && newStatus == 'repaired') {
                              sendReadySMS(
                                t.customerPhone,
                                t.customerName,
                                t.id,
                                t.deviceModel,
                                t.technicianName ?? '',
                                t.technicianPhone ?? '',
                                DatabaseHelper.complaintNumber,
                              ).catchError(
                                (e) => debugPrint('Ready SMS failed: $e'),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String filterVal, String label) {
    final isSelected = selectedStatusFilter == filterVal;
    final primaryGold = const Color(0xFFD4AF37);
    return ChoiceChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
      ),
      selected: isSelected,
      selectedColor: primaryGold.withValues(alpha: 0.2),
      checkmarkColor: primaryGold,
      side: BorderSide(
        color: isSelected ? primaryGold : Colors.grey.withValues(alpha: 0.3),
      ),
      labelStyle: TextStyle(
        color: isSelected ? primaryGold : AppTheme.text(context),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            selectedStatusFilter = filterVal;
            _filterTickets();
          });
        }
      },
    );
  }

  String _getStatusArabic(String status) {
    switch (status) {
      case 'pending':
        return 'انتظار';
      case 'in_progress':
        return 'قيد الإصلاح';
      case 'repaired':
        return 'جاهز للتسليم';
      case 'delivered':
        return 'تم التسليم';
      case 'rejected':
        return 'مرفوض';
      default:
        return status;
    }
  }
}
