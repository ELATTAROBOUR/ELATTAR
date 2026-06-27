import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../print_service.dart';
import '../services/whatsapp_service.dart';

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
  final bool enableSMS = false; // تعطيل إرسال رسائل الـ SMS مؤقتاً

  Timer? _refreshTimer;
  bool _isRefreshing = false;
  Set<String> _presentTechnicians = {};

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
        await _loadPresentTechnicians();

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

  Future<void> _loadPresentTechnicians() async {
    try {
      final todayAttendance = await DatabaseHelper.getTodayAttendance();
      final present = todayAttendance
          .where((a) => a.checkIn != null && a.checkOut == null)
          .map((a) => a.userName)
          .toSet();
      if (!mounted) return;
      setState(() {
        _presentTechnicians = present;
      });
    } catch (e) {
      debugPrint('Error loading present technicians: $e');
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
            // 1. Try name from currentLoggedInUser
            if (currentLoggedInUser?.email.toLowerCase() == techEmail) {
              techName = currentLoggedInUser?.name;
            }
            // 2. Try looking up in the technicians list
            if (techName == null || techName.isEmpty) {
              final techMatch = technicians.firstWhere(
                (tech) => tech['email']?.toLowerCase() == techEmail,
                orElse: () => {},
              );
              techName = techMatch['name'];
            }
            // 3. Smart Fallback: Match by transliterating Arabic names and comparing with email prefix
            if (techName == null || techName.isEmpty) {
              final emailPrefix =
                  techEmail.split('@').first.trim().toLowerCase();
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
                          'Smart Match: Matched email $techEmail to technician $tName');
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

        // Search Query filter
        bool matchesSearch = true;
        if (searchQuery.isNotEmpty) {
          final query = searchQuery.trim().toLowerCase();
          int? idSearch = int.tryParse(query);
          matchesSearch = (idSearch != null && t.id == idSearch) ||
              t.customerName.toLowerCase().contains(query) ||
              t.customerPhone.contains(query) ||
              t.deviceModel.toLowerCase().contains(query) ||
              (t.technicianName?.toLowerCase().contains(query) ?? false);
        }

        // Status filter
        bool matchesStatus = true;
        if (selectedStatusFilter != 'الكل') {
          matchesStatus = t.status == selectedStatusFilter;
        }

        // Date filter
        bool matchesDate = true;
        if (startDate != null) {
          final tDate = DateTime(
              t.receivedDate.year, t.receivedDate.month, t.receivedDate.day);
          final start =
              DateTime(startDate!.year, startDate!.month, startDate!.day);
          if (tDate.isBefore(start)) matchesDate = false;
        }
        if (endDate != null && matchesDate) {
          final tDate = DateTime(
              t.receivedDate.year, t.receivedDate.month, t.receivedDate.day);
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
        startDate =
            DateTime(picked.start.year, picked.start.month, picked.start.day);
        endDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
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
          spareParts[index].quantity =
              (spareParts[index].quantity - qtyUsed).clamp(0, 999999);
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
            spareParts[index].quantity =
                (spareParts[index].quantity - qtyUsed).clamp(0, 999999);
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
    if (!enableSMS) return; // تعطيل مؤقت للرسائل
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
              'textMessage': {'text': message}
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
    final message =
        "🌹 مرحباً $customerName، \n🌹 اهلاً وسهلاً بكم في محلات العطار استور\n✅ تم الانتهاء من اصلاح جهازكم ( $deviceModel ) بنجاح\n🆔 رقم الايصال: $ticketId\n📦 جهازكم جاهز للتسليم\nشكراً لثقتكم بنا 🌹";

    // ── Try WhatsApp first ──
    try {
      final isWAConfigured = await WhatsAppService.isConfigured();
      if (isWAConfigured) {
        final result = await WhatsAppService.sendRepairReady(
          customerName: customerName,
          customerPhone: phoneNumber,
          ticketId: ticketId,
          deviceModel: deviceModel,
          cost: null,
        );
        if (result.success) {
          debugPrint('WhatsApp notification sent successfully.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ تم إرسال إشعار واتساب للعميل'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
          return; // WhatsApp succeeded, no need for SMS
        } else {
          debugPrint('WhatsApp failed, falling back to SMS: ${result.error}');
        }
      }
    } catch (e) {
      debugPrint('WhatsApp send failed: $e');
    }

    // ── Fallback to SMS ──
    if (!enableSMS) return; // تعطيل مؤقت للرسائل

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
              'textMessage': {'text': message}
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('Fallback SMS sent successfully.');
    } catch (e) {
      debugPrint('Ready SMS post failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Delivery Payment Dialog
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showDeliveryPaymentDialog(Ticket ticket) async {
    const primaryGold = Color(0xFFD4AF37);
    String selectedPayment = 'cash';
    final costController =
        TextEditingController(text: ticket.cost.toStringAsFixed(2));
    final vfNumberController =
        TextEditingController(text: ticket.paymentDetails ?? '');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final textColor = AppTheme.text(ctx);
          final cardBg = AppTheme.cardBg(ctx);

          Widget paymentCard(
              String method, String label, IconData icon, Color color) {
            final isSelected = selectedPayment == method;
            return GestureDetector(
              onTap: () => setDlg(() => selectedPayment = method),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isSelected ? color : Colors.grey.withValues(alpha: 0.3),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        color: isSelected ? color : Colors.grey, size: 28),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : textColor,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                        fontFamily: 'Cairo',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.payment_rounded,
                      color: primaryGold, size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تأكيد التسليم وطريقة الدفع',
                          style: TextStyle(
                              color: primaryGold,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo'),
                        ),
                        Text(
                          '${ticket.customerName} — ${ticket.deviceModel}',
                          style: TextStyle(
                              color: textColor.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cost field
                      TextField(
                        controller: costController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'التكلفة النهائية (ج.م)',
                          labelStyle: const TextStyle(
                              color: primaryGold, fontFamily: 'Cairo'),
                          suffixText: 'ج.م',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: primaryGold, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Payment methods grid
                      Text(
                        'طريقة الدفع',
                        style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontFamily: 'Cairo'),
                      ),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.85,
                        children: [
                          paymentCard('cash', 'نقدي', Icons.payments_outlined,
                              Colors.green),
                          paymentCard('vodafone_cash', 'فودافون\nكاش',
                              Icons.phone_android, Colors.red),
                          paymentCard(
                              'instapay',
                              'InstaPay',
                              Icons.account_balance_wallet_outlined,
                              Colors.indigo),
                          paymentCard('visa', 'Visa / بطاقة', Icons.credit_card,
                              Colors.blue),
                        ],
                      ),
                      // Vodafone number field
                      if (selectedPayment == 'vodafone_cash') ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: vfNumberController,
                          style: TextStyle(color: textColor),
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: Colors.red, width: 2),
                            ),
                          ),
                        ),
                      ],
                      // InstaPay number display (read-only)
                      if (selectedPayment == 'instapay') ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller:
                              TextEditingController(text: '01000361006'),
                          readOnly: true,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Colors.indigo, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: TextStyle(
                          color: AppTheme.textMuted(ctx),
                          fontSize: 15,
                          fontFamily: 'Cairo')),
                ),
                // Preview Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                    foregroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    side: const BorderSide(color: Colors.blueAccent),
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 19),
                  label: const Text('معاينة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo')),
                  onPressed: () async {
                    final finalCost =
                        double.tryParse(costController.text) ?? ticket.cost;
                    final paymentDetails = selectedPayment == 'vodafone_cash'
                        ? vfNumberController.text.trim()
                        : (selectedPayment == 'instapay'
                            ? '01000361006'
                            : null);
                    Navigator.pop(ctx);
                    try {
                      final bytes = await PrintService.generateReceiptPdf(
                        ticket,
                        isDelivery: true,
                        overrideCost: finalCost,
                        overridePaymentMethod: selectedPayment,
                        overridePaymentDetails: paymentDetails,
                      );
                      if (context.mounted) {
                        await showDialog(
                          context: context,
                          builder: (ctx) => Dialog(
                            backgroundColor: Colors.transparent,
                            insetPadding: const EdgeInsets.all(16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 520,
                                height: 700,
                                child: PdfPreview(
                                  build: (_) async => bytes,
                                  allowPrinting: true,
                                  allowSharing: false,
                                  canChangeOrientation: false,
                                  canChangePageFormat: false,
                                  canDebug: false,
                                  pdfFileName: 'receipt.pdf',
                                  actions: const [],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('خطأ في المعاينة: ' + e.toString()),
                            backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
                const SizedBox(width: 4),
                // Direct Print x2 Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGold,
                    foregroundColor: const Color(0xFF1A2A3A),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 19),
                  label: const Text('تأكيد وطباعة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo')),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final finalCost =
                        double.tryParse(costController.text) ?? ticket.cost;
                    final paymentDetails = selectedPayment == 'vodafone_cash'
                        ? vfNumberController.text.trim()
                        : (selectedPayment == 'instapay'
                            ? '01000361006'
                            : null);
                    setState(() {
                      ticket.status = 'delivered';
                      ticket.deliveryDate = DateTime.now();
                      ticket.cost = finalCost;
                      ticket.paymentMethod = selectedPayment;
                      ticket.paymentDetails = paymentDetails;
                      ticket.updatedAt = DateTime.now().millisecondsSinceEpoch;
                    });
                    await saveTickets();
                    await DatabaseHelper.logModification(
                      actionType: 'تسليم',
                      itemType: 'صيانة',
                      itemName: ticket.deviceModel,
                      details: 'تسليم إيصال #' +
                          '' +
                          ' للعميل ' +
                          '' +
                          '، طريقة الدفع: ' +
                          '' +
                          '، التكلفة: ' +
                          '' +
                          ' ج.م',
                    );
                    _filterTickets();
                    try {
                      await PrintService.printReceipt(
                        ticket,
                        isDelivery: true,
                        overrideCost: finalCost,
                        overridePaymentMethod: selectedPayment,
                        overridePaymentDetails: paymentDetails,
                        copies: 2,
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('خطأ في الطباعة: ' + e.toString()),
                            backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
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
            updatedAt: DateTime.now().millisecondsSinceEpoch,
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

          // Auto printing labels and receipts
          try {
            await PrintService.printLabel(newTicket);
          } catch (_) {}
          try {
            await PrintService.printReceipt(newTicket);
          } catch (_) {}

          sendSMS(
            ticketData['customerPhone'],
            ticketData['customerName'],
            newTicket.id,
            ticketData['deviceModel'],
            ticketData['technicianName'],
            ticketData['technicianPhone'],
            DatabaseHelper.complaintNumber,
          ).catchError((e) => debugPrint('SMS failed: $e'));
        },
      ),
    ).then((_) => _isDialogOpen = false);
  }

  void showEditTicketDialog(Ticket ticket) {
    if (ticket.isClosed == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('⚠️ لا يمكن تعديل هذا الإيصال لأنه مغلق بالتقفيل المالي'),
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
              tickets[index].updatedAt = DateTime.now().millisecondsSinceEpoch;

              adjustPartsInventory(oldPartsUsed, ticketData['partsUsed']);
              _filterTickets();
            }
          });

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
        title: const Text('تأكيد الحذف',
            style: TextStyle(color: Colors.redAccent, fontSize: 20)),
        content: Text(
            'هل أنت متأكد من حذف إيصال العميل ${ticket.customerName}؟',
            style: TextStyle(color: AppTheme.text(context), fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء',
                style: TextStyle(
                    color: AppTheme.textMuted(context), fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white),
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

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            FocusManager.instance.primaryFocus == node) {
          if (event.logicalKey == LogicalKeyboardKey.add ||
              event.logicalKey == LogicalKeyboardKey.numpadAdd ||
              event.character == '+') {
            showAddTicketDialog();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Add Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔧 قسم الصيانة والتذاكر',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: textColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'إدارة فواتير وإيصالات الصيانة وتغيير حالات الإصلاح وطباعتها',
                      style: TextStyle(fontSize: 15, color: textMuted),
                    ),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      onPressed: showCloseDailyRecordDialog,
                      icon: const Icon(Icons.lock_clock, size: 22),
                      label: const Text('تقفيل يومية الصيانة',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGold,
                        foregroundColor: const Color(0xFF1A2A3A),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      onPressed: showAddTicketDialog,
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 22),
                      label: const Text('إضافة إيصال صيانة',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Filters and Search Bar
            Card(
              color: AppTheme.cardBg(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Search field
                        Expanded(
                          child: TextField(
                            style: TextStyle(color: textColor, fontSize: 16),
                            decoration: InputDecoration(
                              hintText:
                                  'البحث برقم الإيصال، اسم العميل، الهاتف، أو الجهاز...',
                              prefixIcon:
                                  Icon(Icons.search, color: primaryGold),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            onChanged: (val) {
                              setState(() {
                                searchQuery = val;
                                _filterTickets();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Date filter options
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedDateFilter,
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontFamily: 'Cairo'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'الكل', child: Text('كل التواريخ')),
                              DropdownMenuItem(
                                  value: 'اليوم', child: Text('اليوم')),
                              DropdownMenuItem(
                                  value: 'هذا الشهر', child: Text('هذا الشهر')),
                              DropdownMenuItem(
                                  value: 'مخصص', child: Text('تاريخ مخصص')),
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
                        if (selectedDateFilter == 'مخصص' &&
                            startDate != null &&
                            endDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.redAccent),
                            onPressed: clearDateFilter,
                            tooltip: 'إلغاء تصفية التاريخ',
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Status filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusChip('الكل', 'الكل'),
                          const SizedBox(width: 8),
                          _buildStatusChip('pending', '⏳ قيد الانتظار'),
                          const SizedBox(width: 8),
                          _buildStatusChip('in_progress', '🔧 تحت الصيانة'),
                          const SizedBox(width: 8),
                          _buildStatusChip('repaired', '✅ تم الإصلاح'),
                          const SizedBox(width: 8),
                          _buildStatusChip('delivered', '📦 تم التسليم'),
                          const SizedBox(width: 8),
                          _buildStatusChip('rejected', '❌ المرفوض'),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tickets List View
            Expanded(
              child: filteredTickets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'لا توجد فواتير صيانة مطابقة للتصفية الحالية',
                            style: TextStyle(fontSize: 18, color: textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredTickets.length,
                      itemBuilder: (context, index) {
                        final ticket = filteredTickets[index];
                        return TicketCard(
                          ticket: ticket,
                          presentTechnicians: _presentTechnicians,
                          onEdit: () => showEditTicketDialog(ticket),
                          onDelete: () => deleteTicket(ticket),
                          onPrintLabel: (t) async {
                            try {
                              await PrintService.printLabel(t);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('❌ خطأ في الطباعة: $e'),
                                      backgroundColor: Colors.red));
                            }
                          },
                          onPrintReceipt: (t) async {
                            try {
                              await PrintService.printReceipt(t);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('❌ خطأ في الطباعة: $e'),
                                      backgroundColor: Colors.red));
                            }
                          },
                          onPreviewLabel: (t) async {
                            try {
                              final bytes =
                                  await PrintService.generateLabelPdf(t);
                              if (context.mounted) {
                                await showDialog(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.all(16),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 520,
                                        height: 700,
                                        child: PdfPreview(
                                          build: (_) async => bytes,
                                          allowPrinting: true,
                                          allowSharing: false,
                                          canChangeOrientation: false,
                                          canChangePageFormat: false,
                                          canDebug: false,
                                          pdfFileName: 'receipt.pdf',
                                          actions: const [],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('❌ خطأ في المعاينة: $e'),
                                      backgroundColor: Colors.red));
                            }
                          },
                          onPreviewReceipt: (t) async {
                            try {
                              final bytes =
                                  await PrintService.generateReceiptPdf(t);
                              if (context.mounted) {
                                await showDialog(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.all(16),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 520,
                                        height: 700,
                                        child: PdfPreview(
                                          build: (_) async => bytes,
                                          allowPrinting: true,
                                          allowSharing: false,
                                          canChangeOrientation: false,
                                          canChangePageFormat: false,
                                          canDebug: false,
                                          pdfFileName: 'receipt.pdf',
                                          actions: const [],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('❌ خطأ في المعاينة: $e'),
                                      backgroundColor: Colors.red));
                            }
                          },
                          onStatusChanged: (t, newStatus) async {
                            String old = t.status;

                            // ── Delivery: show payment dialog ──────────────
                            if (newStatus == 'delivered') {
                              await _showDeliveryPaymentDialog(t);
                              return; // dialog handles save + print
                            }

                            setState(() {
                              t.status = newStatus;
                              t.updatedAt =
                                  DateTime.now().millisecondsSinceEpoch;
                            });
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
                                      DatabaseHelper.complaintNumber)
                                  .catchError((e) =>
                                      debugPrint('Ready SMS failed: $e'));
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
      label: Text(label, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      selectedColor: primaryGold.withValues(alpha: 0.2),
      checkmarkColor: primaryGold,
      side: BorderSide(
          color: isSelected ? primaryGold : Colors.grey.withValues(alpha: 0.3)),
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

  void showCloseDailyRecordDialog() {
    DateTime selectedDate = DateTime.now();
    DateTime? lastSelectedDate;
    final Map<int, bool> hasSparePartMap = {};
    final Map<int, double> sparePartCostsMap = {};
    final Map<int, TextEditingController> costControllers = {};

    void disposeControllers() {
      for (var controller in costControllers.values) {
        controller.dispose();
      }
      costControllers.clear();
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetDate = DateTime(
                selectedDate.year, selectedDate.month, selectedDate.day);
            final dailyTickets = tickets.where((t) {
              if (t.status != 'delivered') {
                return false;
              }
              if (t.isClosed == 1) {
                return false;
              }
              if (t.deliveryDate == null) {
                return false;
              }
              final dDate = DateTime(t.deliveryDate!.year,
                  t.deliveryDate!.month, t.deliveryDate!.day);
              return dDate.isAtSameMomentAs(targetDate);
            }).toList();

            // Lazy initialization of maps for the selected date
            if (lastSelectedDate == null ||
                !lastSelectedDate!.isAtSameMomentAs(targetDate)) {
              hasSparePartMap.clear();
              sparePartCostsMap.clear();
              for (var controller in costControllers.values) {
                controller.dispose();
              }
              costControllers.clear();

              for (var t in dailyTickets) {
                final hasPart = t.partsCost > 0;
                hasSparePartMap[t.id] = hasPart;
                sparePartCostsMap[t.id] = t.partsCost;
                costControllers[t.id] = TextEditingController(
                  text: hasPart ? t.partsCost.toStringAsFixed(2) : '',
                );
              }
              lastSelectedDate = targetDate;
            }

            double totalRevenue =
                dailyTickets.fold(0.0, (sum, t) => sum + t.cost);
            double totalPartsCost = dailyTickets.fold(0.0, (sum, t) {
              final cost = hasSparePartMap[t.id] == true
                  ? (sparePartCostsMap[t.id] ?? 0.0)
                  : 0.0;
              return sum + cost;
            });
            double totalNetProfit = totalRevenue - totalPartsCost;
            double totalTechEarnings = 0.0;

            final Map<String, List<Ticket>> techGroups = {};
            for (var t in dailyTickets) {
              final name = t.technicianName ?? 'غير محدد';
              techGroups.putIfAbsent(name, () => []).add(t);
            }

            for (var t in dailyTickets) {
              final partCost = hasSparePartMap[t.id] == true
                  ? (sparePartCostsMap[t.id] ?? 0.0)
                  : 0.0;
              final net = t.cost - partCost;
              totalTechEarnings += net * (t.commissionRate / 100);
            }
            double totalStoreEarnings = totalNetProfit - totalTechEarnings;

            double cashSum = 0;
            double vfCashSum = 0;
            double instapaySum = 0;
            double visaSum = 0;
            for (var t in dailyTickets) {
              if (t.paymentMethod == 'vodafone_cash') {
                vfCashSum += t.cost;
              } else if (t.paymentMethod == 'instapay') {
                instapaySum += t.cost;
              } else if (t.paymentMethod == 'visa') {
                visaSum += t.cost;
              } else {
                cashSum += t.cost;
              }
            }

            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) {
                  disposeControllers();
                }
              },
              child: Dialog(
                backgroundColor: AppTheme.cardBg(context),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  height: MediaQuery.of(context).size.height * 0.85,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.lock_clock,
                                  color: Color(0xFFD4AF37), size: 28),
                              SizedBox(width: 10),
                              Text(
                                'تقفيل اليومية المالية للعملاء والاصلاحات',
                                style: TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close,
                                size: 28, color: AppTheme.textMuted(context)),
                            onPressed: () {
                              disposeControllers();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      const Divider(
                          color: Color(0xFFD4AF37), thickness: 0.5, height: 24),
                      Row(
                        children: [
                          Text(
                            'تاريخ اليومية المراد إغلاقها: ',
                            style: TextStyle(
                                color: AppTheme.text(context),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: const Color(0xFF1A2A3A),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                locale: const Locale('ar', 'EG'),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                            icon: const Icon(Icons.calendar_month, size: 20),
                            label: Text(
                              DateFormat('yyyy/MM/dd').format(selectedDate),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: dailyTickets.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        color:
                                            Colors.green.withValues(alpha: 0.7),
                                        size: 64),
                                    const SizedBox(height: 16),
                                    Text(
                                      'لا توجد إيصالات صيانة غير مقفلة ومسلمة في هذا اليوم.',
                                      style: TextStyle(
                                          color: AppTheme.textMuted(context),
                                          fontSize: 16,
                                          fontFamily: 'Cairo'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildClosureStatCard(
                                            'إجمالي المقبوض',
                                            '${totalRevenue.toStringAsFixed(2)} ج.م',
                                            Icons.monetization_on,
                                            const Color(0xFF2E7D32),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildClosureStatCard(
                                            'تكلفة قطع الغيار',
                                            '${totalPartsCost.toStringAsFixed(2)} ج.م',
                                            Icons.settings,
                                            const Color(0xFFC62828),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildClosureStatCard(
                                            'مستحقات الفنيين',
                                            '${totalTechEarnings.toStringAsFixed(2)} ج.م',
                                            Icons.badge,
                                            const Color(0xFF1565C0),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildClosureStatCard(
                                            'صافي المحل الكلي',
                                            '${totalStoreEarnings.toStringAsFixed(2)} ج.م',
                                            Icons.store,
                                            const Color(0xFFD4AF37),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppTheme.surfaceTint(context),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color:
                                                      AppTheme.border(context)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  '💳 تفصيل المقبوضات حسب وسيلة الدفع:',
                                                  style: TextStyle(
                                                      color: Color(0xFFD4AF37),
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontFamily: 'Cairo'),
                                                ),
                                                const SizedBox(height: 12),
                                                _buildClosurePaymentRow(
                                                    'نقدي (كاش)',
                                                    cashSum,
                                                    Icons.payments,
                                                    Colors.green),
                                                const Divider(height: 16),
                                                _buildClosurePaymentRow(
                                                    'فودافون كاش',
                                                    vfCashSum,
                                                    Icons.phone_android,
                                                    Colors.red),
                                                const Divider(height: 16),
                                                _buildClosurePaymentRow(
                                                    'InstaPay',
                                                    instapaySum,
                                                    Icons.account_balance,
                                                    Colors.blue),
                                                const Divider(height: 16),
                                                _buildClosurePaymentRow(
                                                    'فيزا',
                                                    visaSum,
                                                    Icons.credit_card,
                                                    Colors.orange),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 3,
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppTheme.surfaceTint(context),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color:
                                                      AppTheme.border(context)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  '👨‍🔧 مستحقات وأرباح الفنيين:',
                                                  style: TextStyle(
                                                      color: Color(0xFFD4AF37),
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontFamily: 'Cairo'),
                                                ),
                                                const SizedBox(height: 12),
                                                ...techGroups.entries
                                                    .map((entry) {
                                                  final techName = entry.key;
                                                  final list = entry.value;
                                                  double techRevenue =
                                                      list.fold(
                                                          0.0,
                                                          (sum, t) =>
                                                              sum + t.cost);
                                                  double techParts =
                                                      list.fold(0.0, (sum, t) {
                                                    final cost =
                                                        hasSparePartMap[t.id] ==
                                                                true
                                                            ? (sparePartCostsMap[
                                                                    t.id] ??
                                                                0.0)
                                                            : 0.0;
                                                    return sum + cost;
                                                  });
                                                  double techEarn = 0;
                                                  for (var t in list) {
                                                    final partCost =
                                                        hasSparePartMap[t.id] ==
                                                                true
                                                            ? (sparePartCostsMap[
                                                                    t.id] ??
                                                                0.0)
                                                            : 0.0;
                                                    final net =
                                                        t.cost - partCost;
                                                    techEarn += net *
                                                        (t.commissionRate /
                                                            100);
                                                  }
                                                  double storeShare =
                                                      (techRevenue -
                                                              techParts) -
                                                          techEarn;

                                                  return Card(
                                                    color: AppTheme.cardBg(
                                                        context),
                                                    margin:
                                                        const EdgeInsets.only(
                                                            bottom: 8),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8)),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            children: [
                                                              Text(
                                                                'الفني: $techName',
                                                                style: TextStyle(
                                                                    color: AppTheme
                                                                        .text(
                                                                            context),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        16,
                                                                    fontFamily:
                                                                        'Cairo'),
                                                              ),
                                                              Container(
                                                                padding: const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        3),
                                                                decoration: BoxDecoration(
                                                                    color: const Color(
                                                                            0xFFD4AF37)
                                                                        .withValues(
                                                                            alpha:
                                                                                0.15),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            10)),
                                                                child: Text(
                                                                  'أجهزة: ${list.length}',
                                                                  style: const TextStyle(
                                                                      color: Color(
                                                                          0xFFD4AF37),
                                                                      fontSize:
                                                                          13),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const Divider(
                                                              height: 16,
                                                              color: Colors
                                                                  .white24),
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            children: [
                                                              Text(
                                                                  'المقبوض: ${techRevenue.toStringAsFixed(2)}',
                                                                  style: TextStyle(
                                                                      color: AppTheme
                                                                          .textMuted(
                                                                              context),
                                                                      fontSize:
                                                                          14)),
                                                              Text(
                                                                  'قطع غيار: ${techParts.toStringAsFixed(2)}',
                                                                  style: TextStyle(
                                                                      color: AppTheme
                                                                          .textMuted(
                                                                              context),
                                                                      fontSize:
                                                                          14)),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                              height: 6),
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            children: [
                                                              Text(
                                                                'صافي أرباح الفني: ${techEarn.toStringAsFixed(2)} ج.م',
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .green,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        14),
                                                              ),
                                                              Text(
                                                                'للمحل: ${storeShare.toStringAsFixed(2)} ج.م',
                                                                style: TextStyle(
                                                                    color: const Color(
                                                                        0xFFD4AF37),
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        14),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceTint(context),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppTheme.border(context)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '📋 تفاصيل الإيصالات المسلمة ومراجعة قطع الغيار:',
                                            style: TextStyle(
                                                color: Color(0xFFD4AF37),
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo'),
                                          ),
                                          const SizedBox(height: 12),
                                          ListView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: dailyTickets.length,
                                            itemBuilder: (context, index) {
                                              final t = dailyTickets[index];
                                              final isChecked =
                                                  hasSparePartMap[t.id] ??
                                                      false;
                                              final double currentPartsCost =
                                                  isChecked
                                                      ? (sparePartCostsMap[
                                                              t.id] ??
                                                          0.0)
                                                      : 0.0;
                                              final double net =
                                                  t.cost - currentPartsCost;
                                              final double techEarn = net *
                                                  (t.commissionRate / 100);
                                              final double storeShare =
                                                  net - techEarn;

                                              return Card(
                                                color: AppTheme.cardBg(context),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  side: BorderSide(
                                                      color: AppTheme.border(
                                                          context)),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              CircleAvatar(
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFFD4AF37),
                                                                foregroundColor:
                                                                    const Color(
                                                                        0xFF1A2A3A),
                                                                radius: 16,
                                                                child: Text(
                                                                    t.id
                                                                        .toString(),
                                                                    style: const TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        fontWeight:
                                                                            FontWeight.bold)),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                '${t.customerName} - ${t.deviceModel}',
                                                                style: TextStyle(
                                                                    color: AppTheme
                                                                        .text(
                                                                            context),
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontFamily:
                                                                        'Cairo'),
                                                              ),
                                                            ],
                                                          ),
                                                          Text(
                                                            '${t.cost.toStringAsFixed(2)} ج.م',
                                                            style: const TextStyle(
                                                                color: Color(
                                                                    0xFFD4AF37),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'الفني: ${t.technicianName ?? "غير محدد"} (عمولة ${t.commissionRate.toStringAsFixed(0)}%) | طريقة الدفع: ${_getClosurePaymentMethodArabicName(t.paymentMethod)}',
                                                        style: TextStyle(
                                                            color: AppTheme
                                                                .textMuted(
                                                                    context),
                                                            fontSize: 13,
                                                            fontFamily:
                                                                'Cairo'),
                                                      ),
                                                      const Divider(height: 20),
                                                      Row(
                                                        children: [
                                                          Checkbox(
                                                            activeColor:
                                                                const Color(
                                                                    0xFFD4AF37),
                                                            checkColor:
                                                                const Color(
                                                                    0xFF1A2A3A),
                                                            value: isChecked,
                                                            onChanged: (val) {
                                                              setDialogState(
                                                                  () {
                                                                hasSparePartMap[
                                                                        t.id] =
                                                                    val ??
                                                                        false;
                                                                if (val ==
                                                                    true) {
                                                                  if ((sparePartCostsMap[
                                                                              t.id] ??
                                                                          0.0) ==
                                                                      0.0) {
                                                                    sparePartCostsMap[
                                                                            t.id] =
                                                                        0.0;
                                                                  }
                                                                } else {
                                                                  sparePartCostsMap[
                                                                          t.id] =
                                                                      0.0;
                                                                  costControllers[
                                                                          t.id]
                                                                      ?.text = '';
                                                                }
                                                              });
                                                            },
                                                          ),
                                                          Text(
                                                            'يوجد قطع غيار مستخدمة لهذا الإيصال',
                                                            style: TextStyle(
                                                                color: AppTheme
                                                                    .text(
                                                                        context),
                                                                fontSize: 14,
                                                                fontFamily:
                                                                    'Cairo'),
                                                          ),
                                                        ],
                                                      ),
                                                      if (isChecked) ...[
                                                        const SizedBox(
                                                            height: 8),
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: SizedBox(
                                                                height: 48,
                                                                child:
                                                                    TextFormField(
                                                                  controller:
                                                                      costControllers[
                                                                          t.id],
                                                                  keyboardType: const TextInputType
                                                                      .numberWithOptions(
                                                                      decimal:
                                                                          true),
                                                                  style: TextStyle(
                                                                      color: AppTheme
                                                                          .text(
                                                                              context)),
                                                                  decoration:
                                                                      InputDecoration(
                                                                    labelText:
                                                                        'سعر / تكلفة قطعة الغيار (ج.م) *',
                                                                    labelStyle: TextStyle(
                                                                        color: AppTheme.textMuted(
                                                                            context),
                                                                        fontFamily:
                                                                            'Cairo',
                                                                        fontSize:
                                                                            13),
                                                                    border: OutlineInputBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(8)),
                                                                    focusedBorder:
                                                                        OutlineInputBorder(
                                                                      borderSide:
                                                                          const BorderSide(
                                                                              color: Color(0xFFD4AF37)),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              8),
                                                                    ),
                                                                    contentPadding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            12,
                                                                        vertical:
                                                                            8),
                                                                  ),
                                                                  onChanged:
                                                                      (val) {
                                                                    final parsed =
                                                                        double.tryParse(val) ??
                                                                            0.0;
                                                                    setDialogState(
                                                                        () {
                                                                      sparePartCostsMap[
                                                                              t.id] =
                                                                          parsed;
                                                                    });
                                                                  },
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                      const SizedBox(
                                                          height: 12),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(10),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: AppTheme
                                                                  .surfaceTint(
                                                                      context)
                                                              .withValues(
                                                                  alpha: 0.5),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Text(
                                                              'صافي الربح: ${net.toStringAsFixed(2)} ج.م',
                                                              style: TextStyle(
                                                                color: net >= 0
                                                                    ? Colors
                                                                        .green
                                                                    : Colors
                                                                        .red,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                                fontFamily:
                                                                    'Cairo',
                                                              ),
                                                            ),
                                                            Text(
                                                              'نصيب الفني: ${techEarn.toStringAsFixed(2)} ج.م',
                                                              style: TextStyle(
                                                                  color: AppTheme
                                                                      .textMuted(
                                                                          context),
                                                                  fontSize: 13,
                                                                  fontFamily:
                                                                      'Cairo'),
                                                            ),
                                                            Text(
                                                              'نصيب المحل: ${storeShare.toStringAsFixed(2)} ج.م',
                                                              style: const TextStyle(
                                                                  color: Color(
                                                                      0xFFD4AF37),
                                                                  fontSize: 13,
                                                                  fontFamily:
                                                                      'Cairo'),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              disposeControllers();
                              Navigator.pop(context);
                            },
                            child: Text(
                              'إلغاء',
                              style: TextStyle(
                                  color: AppTheme.textDisabled(context),
                                  fontSize: 16,
                                  fontFamily: 'Cairo'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (dailyTickets.isNotEmpty) ...[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('معاينة التقرير',
                                  style: TextStyle(
                                      fontSize: 16, fontFamily: 'Cairo')),
                              onPressed: () async {
                                final scaffoldMessenger =
                                    ScaffoldMessenger.of(context);
                                try {
                                  final updatedTicketsForPrint =
                                      dailyTickets.map((t) {
                                    final actualCost =
                                        hasSparePartMap[t.id] == true
                                            ? (sparePartCostsMap[t.id] ?? 0.0)
                                            : 0.0;
                                    return Ticket(
                                      id: t.id,
                                      customerName: t.customerName,
                                      customerPhone: t.customerPhone,
                                      deviceModel: t.deviceModel,
                                      problem: t.problem,
                                      status: t.status,
                                      receivedDate: t.receivedDate,
                                      deliveryDate: t.deliveryDate,
                                      cost: t.cost,
                                      notes: t.notes,
                                      technicianName: t.technicianName,
                                      technicianPhone: t.technicianPhone,
                                      complaintNumber: t.complaintNumber,
                                      deviceCondition: t.deviceCondition,
                                      paymentMethod: t.paymentMethod,
                                      paymentDetails: t.paymentDetails,
                                      partsCost: actualCost,
                                      partsUsed: t.partsUsed,
                                      commissionRate: t.commissionRate,
                                      isClosed: t.isClosed,
                                    );
                                  }).toList();

                                  final bytes = await PrintService
                                      .generateDailyClosurePdf(
                                          selectedDate, updatedTicketsForPrint);
                                  if (context.mounted) {
                                    await showDialog(
                                      context: context,
                                      builder: (ctx) => Dialog(
                                        backgroundColor: Colors.transparent,
                                        insetPadding: const EdgeInsets.all(16),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: SizedBox(
                                            width: 520,
                                            height: 700,
                                            child: PdfPreview(
                                              build: (_) async => bytes,
                                              allowPrinting: true,
                                              allowSharing: false,
                                              canChangeOrientation: false,
                                              canChangePageFormat: false,
                                              canDebug: false,
                                              pdfFileName: 'daily_closure.pdf',
                                              actions: const [],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text('❌ فشل معاينة التقرير: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('طباعة التقرير',
                                  style: TextStyle(
                                      fontSize: 16, fontFamily: 'Cairo')),
                              onPressed: () async {
                                final scaffoldMessenger =
                                    ScaffoldMessenger.of(context);
                                try {
                                  final updatedTicketsForPrint =
                                      dailyTickets.map((t) {
                                    final actualCost =
                                        hasSparePartMap[t.id] == true
                                            ? (sparePartCostsMap[t.id] ?? 0.0)
                                            : 0.0;
                                    return Ticket(
                                      id: t.id,
                                      customerName: t.customerName,
                                      customerPhone: t.customerPhone,
                                      deviceModel: t.deviceModel,
                                      problem: t.problem,
                                      status: t.status,
                                      receivedDate: t.receivedDate,
                                      deliveryDate: t.deliveryDate,
                                      cost: t.cost,
                                      notes: t.notes,
                                      technicianName: t.technicianName,
                                      technicianPhone: t.technicianPhone,
                                      complaintNumber: t.complaintNumber,
                                      deviceCondition: t.deviceCondition,
                                      paymentMethod: t.paymentMethod,
                                      paymentDetails: t.paymentDetails,
                                      partsCost: actualCost,
                                      partsUsed: t.partsUsed,
                                      commissionRate: t.commissionRate,
                                      isClosed: t.isClosed,
                                    );
                                  }).toList();

                                  await PrintService.printDailyClosureReport(
                                      selectedDate, updatedTicketsForPrint);
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          '✅ تم إرسال تقرير تقفيل اليومية إلى الطابعة بنجاح'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } catch (e) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text('❌ فشل طباعة التقرير: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[800],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('تأكيد تقفيل اليومية',
                                  style: TextStyle(
                                      fontSize: 16, fontFamily: 'Cairo')),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (subContext) => AlertDialog(
                                    backgroundColor: AppTheme.cardBg(context),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    title: const Text('تأكيد التقفيل والأرشفة',
                                        style: TextStyle(
                                            color: Color(0xFFD4AF37),
                                            fontSize: 20,
                                            fontFamily: 'Cairo')),
                                    content: const Text(
                                      'هل أنت متأكد من إغلاق وتقفيل اليومية؟ لن تظهر الإيصالات المحددة مرة أخرى في التقارير المالية القادمة وسيتم أرشفتها نهائياً كـ مقفلة وسيتم حفظ تكاليف قطع الغيار المعدلة.',
                                      style: TextStyle(
                                          fontSize: 16, fontFamily: 'Cairo'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(subContext),
                                        child: Text('إلغاء',
                                            style: TextStyle(
                                                color:
                                                    AppTheme.textMuted(context),
                                                fontSize: 16,
                                                fontFamily: 'Cairo')),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green[800]),
                                        onPressed: () async {
                                          Navigator.pop(subContext);
                                          Navigator.pop(context);

                                          final scaffoldMessenger =
                                              ScaffoldMessenger.of(context);

                                          setState(() {
                                            for (var dailyT in dailyTickets) {
                                              final index = tickets.indexWhere(
                                                  (t) => t.id == dailyT.id);
                                              if (index != -1) {
                                                final actualCost =
                                                    hasSparePartMap[
                                                                dailyT.id] ==
                                                            true
                                                        ? (sparePartCostsMap[
                                                                dailyT.id] ??
                                                            0.0)
                                                        : 0.0;
                                                tickets[index].partsCost =
                                                    actualCost;
                                                tickets[index].isClosed = 1;
                                                tickets[index].updatedAt =
                                                    DateTime.now()
                                                        .millisecondsSinceEpoch;
                                              }
                                            }
                                            _filterTickets();
                                            saveTickets();
                                          });

                                          disposeControllers();

                                          scaffoldMessenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  '✅ تم إغلاق وتقفيل اليومية المالية بنجاح وأرشفة الإيصالات'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        },
                                        child: const Text('تأكيد وتقفيل',
                                            style:
                                                TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClosureStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Cairo'),
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildClosurePaymentRow(
      String method, double amount, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          method,
          style: TextStyle(
              color: AppTheme.text(context),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFamily: 'Cairo'),
        ),
        const Spacer(),
        Text(
          '${amount.toStringAsFixed(2)} ج.م',
          style: TextStyle(
              color: color, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _getClosurePaymentMethodArabicName(String? method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'vodafone_cash':
        return 'فودافون كاش';
      case 'instapay':
        return 'InstaPay';
      case 'visa':
        return 'فيزا';
      default:
        return 'غير حدد';
    }
  }
}
