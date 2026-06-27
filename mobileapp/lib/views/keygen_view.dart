import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cryptography/cryptography.dart';
import '../hwid_service.dart';

class KeygenView extends StatefulWidget {
  const KeygenView({super.key});

  @override
  State<KeygenView> createState() => _KeygenViewState();
}

class _KeygenViewState extends State<KeygenView> {
  final TextEditingController _hwidController = TextEditingController();
  String _validationStatus = 'أدخل رمز الجهاز للتحقق';
  bool _isValidHwid = false;
  String _decryptedSignature = '';
  String _generatedKey = '';
  String _statusMessage = '';
  bool _generating = false;
  String _selectedDuration = 'LIFETIME';
  DateTime? _customExpiryDate;

  // Ed25519 keys (same as desktop keygen)
  static const String _privateKeyHex =
      'efdbb90fcb74a1c11daddba4c4ca1748b82c43a83174ff4a6bb503313f68b747';
  static const String _publicKeyHex =
      'd6870d45570293cffcf5ec390ae962cc6fd35c05e26b9d2ae5e2791622923f7b';

  @override
  void initState() {
    super.initState();
    _hwidController.addListener(_onHwidChanged);
  }

  @override
  void dispose() {
    _hwidController.dispose();
    super.dispose();
  }

  void _onHwidChanged() {
    final hwid = _hwidController.text.trim();
    if (hwid.isEmpty) {
      setState(() {
        _validationStatus = 'أدخل رمز الجهاز للتحقق';
        _isValidHwid = false;
        _decryptedSignature = '';
        _generatedKey = '';
      });
      return;
    }

    final decrypted = HwidService.verifyAndDecryptHWID(hwid);
    if (decrypted != null) {
      setState(() {
        _validationStatus = '✅ رمز الجهاز صحيح';
        _isValidHwid = true;
        _decryptedSignature = decrypted;
      });
    } else {
      setState(() {
        _validationStatus = '❌ رمز جهاز غير صالح';
        _isValidHwid = false;
        _decryptedSignature = '';
        _generatedKey = '';
      });
    }
  }

  Future<void> _generateLicense() async {
    final hwid = _hwidController.text.trim();
    if (!_isValidHwid) return;

    setState(() {
      _generating = true;
      _statusMessage = 'جاري إنشاء مفتاح التفعيل...';
    });

    // Small delay for UX
    await Future.delayed(const Duration(milliseconds: 500));

    String expiry = 'LIFETIME';
    final now = DateTime.now();

    switch (_selectedDuration) {
      case '5_MINUTES':
        expiry = _formatDateTime(now.add(const Duration(minutes: 5)));
        break;
      case '1_DAY':
        expiry = _formatDate(now.add(const Duration(days: 1)));
        break;
      case '1_MONTH':
        expiry = _formatDate(now.add(const Duration(days: 30)));
        break;
      case '3_MONTHS':
        expiry = _formatDate(now.add(const Duration(days: 90)));
        break;
      case '6_MONTHS':
        expiry = _formatDate(now.add(const Duration(days: 180)));
        break;
      case '1_YEAR':
        expiry = _formatDate(now.add(const Duration(days: 365)));
        break;
      case 'CUSTOM':
        if (_customExpiryDate == null) {
          setState(() {
            _statusMessage = '❌ الرجاء اختيار تاريخ انتهاء التفعيل';
            _generating = false;
          });
          return;
        }
        expiry = _formatDate(_customExpiryDate!);
        break;
    }

    try {
      final key = await _generateSignedKey(hwid, expiry);
      setState(() {
        _generatedKey = key;
        _statusMessage = '✅ تم إنشاء مفتاح التفعيل بنجاح';
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ فشل إنشاء المفتاح: $e';
        _generating = false;
      });
    }
  }

  void _generateResetKey() {
    final hwid = _hwidController.text.trim();
    if (!_isValidHwid) return;

    final key = HwidService.generateResetKey(hwid);
    setState(() {
      _generatedKey = key;
      _statusMessage = '✅ تم إنشاء كود إعادة التعيين بنجاح';
    });
  }

  void _copyToClipboard() {
    if (_generatedKey.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _generatedKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '✅ تم نسخ المفتاح إلى الحافظة',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<String> _generateSignedKey(String hwid, String expiry) async {
    final cleanHwid = hwid.replaceAll('-', '').toUpperCase();
    final payload = '$cleanHwid|$expiry';
    final payloadBytes = utf8.encode(payload);

    final privateKeyBytes = _hexToBytes(_privateKeyHex);
    final publicKeyBytes = _hexToBytes(_publicKeyHex);

    final algorithm = Ed25519();
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

    final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
    final signatureHex = _bytesToHex(signature.bytes);

    return '$expiry.$signatureHex';
  }

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _durationLabel(String duration) {
    switch (duration) {
      case '5_MINUTES':
        return '5 دقائق (تجريبي)';
      case '1_DAY':
        return 'يوم واحد';
      case '1_MONTH':
        return 'شهر واحد';
      case '3_MONTHS':
        return '3 أشهر';
      case '6_MONTHS':
        return '6 أشهر';
      case '1_YEAR':
        return 'سنة واحدة';
      case 'CUSTOM':
        return 'تحديد تاريخ...';
      case 'LIFETIME':
        return 'مدى الحياة ♾️';
      default:
        return duration;
    }
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customExpiryDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      locale: const Locale('ar', 'EG'),
    );
    if (picked != null) {
      setState(() {
        _customExpiryDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFFD4AF37);
    final bgColor = isDark ? const Color(0xFF121B26) : const Color(0xFFF0F4F8);
    final cardBg = isDark ? const Color(0xFF1A2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF4A5D6E);
    final inputBg = isDark ? const Color(0xFF15202F) : const Color(0xFFF0F4F8);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            'توليد مفاتيح التفعيل',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: cardBg,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: primaryColor),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // HWID Input Card
              Card(
                color: cardBg,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.vpn_key_rounded,
                            color: primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'رمز الجهاز (HWID)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hwidController,
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                          hintStyle: TextStyle(
                            color: textMuted.withValues(alpha: 0.4),
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: inputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _validationStatus,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Cairo',
                          color: _isValidHwid
                              ? Colors.greenAccent
                              : (_validationStatus.contains('❌')
                                    ? Colors.redAccent
                                    : textMuted),
                        ),
                      ),
                      if (_decryptedSignature.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'البصمة: $_decryptedSignature',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Duration Selector Card
              Card(
                color: cardBg,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            color: primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'مدة التفعيل',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedDuration,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: inputBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        dropdownColor: cardBg,
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'Cairo',
                          fontSize: 14,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '5_MINUTES',
                            child: Text('5 دقائق (تجريبي) ⏳'),
                          ),
                          DropdownMenuItem(
                            value: '1_DAY',
                            child: Text('يوم واحد 🗓️'),
                          ),
                          DropdownMenuItem(
                            value: '1_MONTH',
                            child: Text('شهر واحد 🗓️'),
                          ),
                          DropdownMenuItem(
                            value: '3_MONTHS',
                            child: Text('3 أشهر 🗓️'),
                          ),
                          DropdownMenuItem(
                            value: '6_MONTHS',
                            child: Text('6 أشهر 🗓️'),
                          ),
                          DropdownMenuItem(
                            value: '1_YEAR',
                            child: Text('سنة واحدة 🗓️'),
                          ),
                          DropdownMenuItem(
                            value: 'LIFETIME',
                            child: Text('مدى الحياة ♾️'),
                          ),
                          DropdownMenuItem(
                            value: 'CUSTOM',
                            child: Text('تحديد تاريخ مخصص... 🛠️'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedDuration = val;
                              if (val == 'CUSTOM') {
                                _pickCustomDate();
                              }
                            });
                          }
                        },
                      ),
                      if (_selectedDuration == 'CUSTOM' &&
                          _customExpiryDate != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: primaryColor),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_month,
                                color: primaryColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'تاريخ الانتهاء: ${_formatDate(_customExpiryDate!)}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: textColor,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _pickCustomDate,
                                child: const Icon(
                                  Icons.edit_calendar,
                                  color: Colors.blueAccent,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: const Color(0xFF1A2A3A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        disabledBackgroundColor: primaryColor.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      onPressed: _isValidHwid && !_generating
                          ? _generateLicense
                          : null,
                      icon: _generating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF1A2A3A),
                                ),
                              ),
                            )
                          : const Icon(Icons.auto_fix_high_rounded),
                      label: Text(
                        _generating ? 'جاري التوليد...' : 'توليد مفتاح التفعيل',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amberAccent,
                        side: BorderSide(
                          color: Colors.amberAccent.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isValidHwid ? _generateResetKey : null,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text(
                        'توليد كود إعادة التعيين',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Generated Key Display
              if (_generatedKey.isNotEmpty) ...[
                Card(
                  color: cardBg,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _statusMessage.contains('✅')
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              _statusMessage.contains('✅')
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              color: _statusMessage.contains('✅')
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontFamily: 'Cairo',
                                  color: _statusMessage.contains('✅')
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(
                            _generatedKey,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Color(0xFFD4AF37),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A2A3A),
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _copyToClipboard,
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            label: const Text(
                              'نسخ المفتاح إلى الحافظة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Info Card
              Card(
                color: cardBg,
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'يتم التوقيع الرقمي باستخدام خوارزمية Ed25519.\n'
                          'المفتاح الخاص موجود في الكيجين فقط.\n'
                          'يمكنك نسخ المفتاح وإرساله للعميل.',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Cairo',
                            color: textMuted,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
