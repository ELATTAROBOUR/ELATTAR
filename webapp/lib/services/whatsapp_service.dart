// ─────────────────────────────────────────────────────────────────────────────
// WhatsApp Cloud API Service
//  Uses Meta's official WhatsApp Business Cloud API
//  • Send repair completion notification
//  • Send invoice/receipt
//  • Send payment reminder
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../database_helper.dart';

class WhatsAppService {
  // ── Settings Keys ──────────────────────────────────────────────────────────
  static const String _settingToken = 'whatsapp_token';
  static const String _settingPhoneNumberId = 'whatsapp_phone_number_id';
  static const String _settingBusinessAccountId =
      'whatsapp_business_account_id';

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Load WhatsApp API settings from database
  static Future<WhatsAppConfig> loadConfig() async {
    return WhatsAppConfig(
      token: await DatabaseHelper.getSetting(_settingToken) ?? '',
      phoneNumberId:
          await DatabaseHelper.getSetting(_settingPhoneNumberId) ?? '',
      businessAccountId:
          await DatabaseHelper.getSetting(_settingBusinessAccountId) ?? '',
    );
  }

  /// Save WhatsApp API settings to database
  static Future<void> saveConfig(WhatsAppConfig config) async {
    await DatabaseHelper.saveSetting(_settingToken, config.token);
    await DatabaseHelper.saveSetting(
        _settingPhoneNumberId, config.phoneNumberId);
    await DatabaseHelper.saveSetting(
        _settingBusinessAccountId, config.businessAccountId);
  }

  /// Check if WhatsApp is configured
  static Future<bool> isConfigured() async {
    final config = await loadConfig();
    return config.token.isNotEmpty && config.phoneNumberId.isNotEmpty;
  }

  // ── Send Message ───────────────────────────────────────────────────────────

  /// Send a text message to a customer via WhatsApp Cloud API
  static Future<WhatsAppResult> sendMessage({
    required String toPhone,
    required String message,
  }) async {
    final config = await loadConfig();
    if (config.token.isEmpty || config.phoneNumberId.isEmpty) {
      return WhatsAppResult(
        success: false,
        error:
            'لم يتم إعداد واتساب بعد. يرجى إضافة التوكن ورقم الهاتف في الإعدادات.',
      );
    }

    // Clean phone number: remove any non-digit characters and ensure it starts with country code
    String cleanPhone = toPhone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanPhone.startsWith('00')) {
      cleanPhone = '+${cleanPhone.substring(2)}';
    }
    if (!cleanPhone.startsWith('+')) {
      cleanPhone = '+2$cleanPhone'; // Default Egypt country code
    }

    final url = Uri.parse(
      'https://graph.facebook.com/v22.0/${config.phoneNumberId}/messages',
    );

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${config.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'recipient_type': 'individual',
          'to': cleanPhone,
          'type': 'text',
          'text': {
            'preview_url': false,
            'body': message,
          },
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return WhatsAppResult(
          success: true,
          messageId: data['messages']?[0]?['id'],
        );
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['error']?['message'] ?? 'خطأ غير معروف';
        debugPrint('WhatsApp API Error ($response.statusCode): $errorMsg');
        return WhatsAppResult(
          success: false,
          error: 'فشل الإرسال: $errorMsg',
        );
      }
    } catch (e) {
      debugPrint('WhatsApp API Exception: $e');
      return WhatsAppResult(
        success: false,
        error: 'فشل الاتصال بخادم واتساب: $e',
      );
    }
  }

  // ── Common Message Templates ───────────────────────────────────────────────

  /// Send repair completion notification
  static Future<WhatsAppResult> sendRepairReady({
    required String customerName,
    required String customerPhone,
    required int ticketId,
    required String deviceModel,
    String? cost,
  }) async {
    final costStr = cost ?? '';
    return sendMessage(
      toPhone: customerPhone,
      message: '''🔧 *العطار استور - صيانة الموبايلات*
━━━━━━━━━━━━━━━━━━━━━
عزيزي $customerName،

جهازك *$deviceModel* (#$ticketId) جاهز للتسليم ✅
${costStr.isNotEmpty ? '\nالتكلفة: $costStr ج.م' : ''}

⏰ يرجى الحضور لاستلام جهازك في أقرب وقت.

━━━━━━━━━━━━━━━━━━━━━
*العطار استور* 📍''',
    );
  }

  /// Send invoice/receipt
  static Future<WhatsAppResult> sendInvoice({
    required String customerName,
    required String customerPhone,
    required String invoiceDetails,
  }) async {
    return sendMessage(
      toPhone: customerPhone,
      message: '''🧾 *العطار استور - فاتورة*
━━━━━━━━━━━━━━━━━━━━━
عزيزي $customerName،

تفاصيل الفاتورة:
$invoiceDetails

شكراً لتعاملكم معنا 🙏
━━━━━━━━━━━━━━━━━━━━━
*العطار استور* 📍''',
    );
  }

  /// Send payment reminder
  static Future<WhatsAppResult> sendPaymentReminder({
    required String customerName,
    required String customerPhone,
    required double remainingAmount,
    String? dueDate,
  }) async {
    final dueStr = dueDate != null ? '\nتاريخ الاستحقاق: $dueDate' : '';
    return sendMessage(
      toPhone: customerPhone,
      message: '''💳 *العطار استور - تذكير بالدفع*
━━━━━━━━━━━━━━━━━━━━━
عزيزي $customerName،

لديك مبلغ مستحق قدره *${remainingAmount.toStringAsFixed(0)} ج.م*$dueStr

يرجى التفضل بالسداد في أقرب وقت ممكن.

━━━━━━━━━━━━━━━━━━━━━
*العطار استور* 📍''',
    );
  }

  /// Send WhatsApp settings dialog data to main.dart
  static Future<bool> testConnection() async {
    final config = await loadConfig();
    if (config.token.isEmpty || config.phoneNumberId.isEmpty) return false;

    final url = Uri.parse(
      'https://graph.facebook.com/v22.0/${config.phoneNumberId}/messages',
    );

    try {
      await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${config.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'recipient_type': 'individual',
          'to': '201000000000', // Test number (won't actually send)
          'type': 'text',
          'text': {'preview_url': false, 'body': 'Test connection'},
        }),
      );
      // If we get a response (even error about invalid number), connection works
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// ────────────────────────────────────────────────────────────────────────────
///  Data Classes
/// ────────────────────────────────────────────────────────────────────────────

class WhatsAppConfig {
  final String token;
  final String phoneNumberId;
  final String businessAccountId;

  const WhatsAppConfig({
    this.token = '',
    this.phoneNumberId = '',
    this.businessAccountId = '',
  });

  bool get isConfigured => token.isNotEmpty && phoneNumberId.isNotEmpty;
}

class WhatsAppResult {
  final bool success;
  final String? messageId;
  final String? error;

  const WhatsAppResult({
    required this.success,
    this.messageId,
    this.error,
  });
}
