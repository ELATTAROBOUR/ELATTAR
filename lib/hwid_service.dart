import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';

class HwidService {
  // Secret key for HWID encryption/decryption
  static const String _hwidKey = "ELATTAR_HWID_SECRET_KEY_2026";
  // Secret salt for License Key generation
  static const String _salt = "ELATTAR_STORE_SECURE_SALT_2026";
  // Secret salt for Reset Key generation
  static const String _resetSalt = "ELATTAR_STORE_RESET_SALT_2026";

  // Global variables to store active license status
  static String expiryDate = "";

  /// Calculates remaining days of activation.
  static int getRemainingDays() {
    try {
      if (expiryDate.isEmpty) return 0;
      final exp = DateTime.parse(expiryDate);
      final currentDate = DateTime.now();
      // Calculate diff in days
      final diff = exp.difference(DateTime(currentDate.year, currentDate.month, currentDate.day)).inDays;
      return diff;
    } catch (e) {
      return 0;
    }
  }

  /// Collects raw system hardware components and returns a concatenated string.
  static Future<String> getRawHardwareDetails() async {
    String cpuId = "";
    String mbSerial = "";
    String diskSerial = "";
    String biosUuid = "";

    if (Platform.isWindows) {
      // 1. Get CPU ID
      try {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_Processor | Select-Object -ExpandProperty ProcessorId'
        ]);
        if (result.exitCode == 0) cpuId = result.stdout.toString().trim();
      } catch (e) {
        debugPrint('Failed to get CPU ID: $e');
      }

      // 2. Get Motherboard Serial
      try {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -ExpandProperty SerialNumber'
        ]);
        if (result.exitCode == 0) mbSerial = result.stdout.toString().trim();
      } catch (e) {
        debugPrint('Failed to get Motherboard Serial: $e');
      }

      // 3. Get Disk Serial (Select all serials and take first non-empty)
      try {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -ExpandProperty SerialNumber'
        ]);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().trim();
          final lines = output.split(RegExp(r'[\r\n]+'));
          for (var line in lines) {
            if (line.trim().isNotEmpty) {
              diskSerial = line.trim();
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to get Disk Serial: $e');
      }

      // 4. Get BIOS UUID
      try {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_ComputerSystemProduct | Select-Object -ExpandProperty UUID'
        ]);
        if (result.exitCode == 0) biosUuid = result.stdout.toString().trim();
      } catch (e) {
        debugPrint('Failed to get BIOS UUID: $e');
      }
    }

    // Normalization helper
    String clean(String val) {
      val = val.trim().toLowerCase();
      final dummyWords = ["to be filled", "o.e.m", "none", "n/a", "unknown", "default", "00000000"];
      for (var word in dummyWords) {
        if (val.contains(word)) return "";
      }
      return val.replaceAll(RegExp(r'[^a-z0-9]'), '');
    }

    cpuId = clean(cpuId);
    mbSerial = clean(mbSerial);
    diskSerial = clean(diskSerial);
    biosUuid = clean(biosUuid);

    // Fallbacks if queries fail
    if (cpuId.isEmpty && mbSerial.isEmpty && diskSerial.isEmpty && biosUuid.isEmpty) {
      final username = Platform.environment['USERNAME'] ?? '';
      final computername = Platform.environment['COMPUTERNAME'] ?? '';
      final processor = Platform.environment['PROCESSOR_IDENTIFIER'] ?? '';
      return "fallback-$username-$computername-$processor";
    }

    return "CPU:$cpuId|MB:$mbSerial|DISK:$diskSerial|UUID:$biosUuid";
  }

  /// Calculates a highly unique, fully encrypted, formatted Hardware ID.
  static Future<String> getHWID() async {
    final rawDetails = await getRawHardwareDetails();
    
    // Hash the raw hardware string to get a stable 32-byte digest
    final hashBytes = sha256.convert(utf8.encode(rawDetails)).bytes;

    // Use the first 12 bytes of the hash
    final payload = hashBytes.sublist(0, 12);

    // Generate a 3-byte checksum/signature using the SHA-256 of the payload
    final sigBytes = sha256.convert(payload).bytes.sublist(0, 3);

    // Pack: 15 bytes in total (12 payload + 3 signature)
    final packed = List<int>.from(payload)..addAll(sigBytes);

    // Encrypt packed bytes using rolling XOR
    final encrypted = _xorCipher(packed, _hwidKey);

    // Encode to Base32
    final base32Str = Base32.encode(encrypted);

    // Format as XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (24 characters, 5 hyphens)
    final formatted = StringBuffer();
    for (int i = 0; i < base32Str.length; i++) {
      if (i > 0 && i % 4 == 0) formatted.write('-');
      formatted.write(base32Str[i]);
    }

    return formatted.toString();
  }

  /// Decrypts a formatted HWID and verifies its integrity.
  /// Returns the decrypted 12-byte hardware signature (in hex) if valid, or null if invalid.
  static String? verifyAndDecryptHWID(String hwidStr) {
    try {
      final clean = hwidStr.replaceAll(RegExp(r'[^a-zA-Z2-7]'), '').toUpperCase();
      if (clean.length != 24) return null;

      final encrypted = Base32.decode(clean);
      if (encrypted == null || encrypted.length != 15) return null;

      // Decrypt using rolling XOR
      final packed = _xorCipher(encrypted, _hwidKey);

      final payload = packed.sublist(0, 12);
      final sigReceived = packed.sublist(12, 15);

      // Verify signature
      final sigExpected = sha256.convert(payload).bytes.sublist(0, 3);
      for (int i = 0; i < 3; i++) {
        if (sigReceived[i] != sigExpected[i]) return null; // Tampered!
      }

      // Return hex signature representing hardware
      return payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    } catch (e) {
      return null;
    }
  }

  /// Generates the Activation Key from the encrypted HWID and an expiration date.
  /// The expiry parameter should be "LIFETIME" or "yyyy-MM-dd".
  static String generateKey(String hwid, String expiry) {
    // Remove formatting from HWID
    final cleanHwid = hwid.replaceAll('-', '').toUpperCase();

    // Payload format: HWID|EXPIRY
    final payload = "$cleanHwid|$expiry";

    // Encrypt using rolling XOR
    final bytes = utf8.encode(payload);
    final encrypted = _xorCipher(bytes, _salt);

    // Encode to Base32
    return Base32.encode(encrypted);
  }

  /// Generates a Reset Key from the HWID.
  static String generateResetKey(String hwid) {
    // Remove formatting from HWID
    final cleanHwid = hwid.replaceAll('-', '').toUpperCase();

    // Payload format: RESET|HWID
    final payload = "RESET|$cleanHwid";

    // Encrypt using rolling XOR
    final bytes = utf8.encode(payload);
    final encrypted = _xorCipher(bytes, _resetSalt);

    // Encode to Base32
    return Base32.encode(encrypted);
  }

  /// Verifies a Reset Key against the local machine's HWID.
  static Future<bool> verifyResetKey(String key) async {
    if (key.trim().isEmpty) return false;
    try {
      final cleanKey = key.replaceAll('-', '').toUpperCase();
      final encrypted = Base32.decode(cleanKey);
      if (encrypted == null) return false;

      // Decrypt using rolling XOR
      final decryptedBytes = _xorCipher(encrypted, _resetSalt);
      final decryptedStr = utf8.decode(decryptedBytes);

      final parts = decryptedStr.split('|');
      if (parts.length != 2) return false;

      final prefix = parts[0];
      final keyHwid = parts[1];

      if (prefix != "RESET") return false;

      final currentHwid = (await getHWID()).replaceAll('-', '').toUpperCase();
      return keyHwid == currentHwid;
    } catch (e) {
      return false;
    }
  }

  /// Checks if system clock has been rolled back compared to tickets database dates.
  static Future<bool> isClockTampered(DateTime currentSysDate) async {
    try {
      final tickets = await DatabaseHelper.loadTickets();
      if (tickets.isNotEmpty) {
        DateTime latestDate = tickets.first.receivedDate;
        for (var t in tickets) {
          if (t.receivedDate.isAfter(latestDate)) {
            latestDate = t.receivedDate;
          }
        }
        // If current date is more than 1 day before the latest ticket date
        if (currentSysDate.isBefore(latestDate.subtract(const Duration(days: 1)))) {
          return true; // Clock has been rolled back!
        }
      }
    } catch (e) {
      debugPrint("Error checking clock tampering: $e");
    }
    return false;
  }

  /// Verifies a license key against the local machine's HWID and sets the expiration status.
  static Future<bool> verifyLicense(String key) async {
    if (key.trim().isEmpty) return false;
    try {
      final cleanKey = key.replaceAll('-', '').toUpperCase();
      final encrypted = Base32.decode(cleanKey);
      if (encrypted == null) return false;

      // Decrypt using rolling XOR
      final decryptedBytes = _xorCipher(encrypted, _salt);
      final decryptedStr = utf8.decode(decryptedBytes);

      final parts = decryptedStr.split('|');
      if (parts.length != 2) return false;

      final keyHwid = parts[0];
      final keyExpiry = parts[1];

      final currentHwid = (await getHWID()).replaceAll('-', '').toUpperCase();
      if (keyHwid != currentHwid) return false;

      // Set global expiry details
      expiryDate = keyExpiry;

      // Check date validity
      if (keyExpiry == "LIFETIME") {
        return true;
      }

      final expDate = DateTime.parse(keyExpiry);
      final currentDate = DateTime.now();

      // Verify clock tampering
      final tampered = await isClockTampered(currentDate);
      if (tampered) {
        debugPrint("Clock tampering detected!");
        return false;
      }

      // Compare current date with expiry date
      // If the expiry contains a time component (has a colon), compare exactly.
      // Otherwise, add 1 day grace period for date-only values.
      final hasTime = keyExpiry.contains(':');
      final finalExp = hasTime ? expDate : expDate.add(const Duration(days: 1));
      if (currentDate.isAfter(finalExp)) {
        debugPrint("License has expired on $keyExpiry!");
        return false; // Expired!
      }

      return true;
    } catch (e) {
      debugPrint("License verification error: $e");
      return false;
    }
  }

  /// Rolling XOR Cipher
  static List<int> _xorCipher(List<int> bytes, String key) {
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(bytes.length, 0);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i] ^ keyBytes[i % keyBytes.length] ^ ((i * 47 + 139) % 256);
    }
    return result;
  }
}

/// Helper class for Base32 Encoding / Decoding
class Base32 {
  static const String _alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

  static String encode(List<int> bytes) {
    int i = 0;
    int index = 0;
    int digit = 0;
    int currByte = 0;
    int nextByte = 0;
    final result = StringBuffer();

    while (i < bytes.length) {
      currByte = bytes[i];
      if (index > 3) {
        nextByte = (i + 1) < bytes.length ? bytes[i + 1] : 0;
        digit = currByte & (0xFF >> index);
        index = (index + 5) % 8;
        digit <<= index;
        digit |= nextByte >> (8 - index);
        i++;
      } else {
        digit = (currByte >> (8 - (index + 5))) & 0x1F;
        index = (index + 5) % 8;
        if (index == 0) i++;
      }
      result.writeCharCode(_alphabet.codeUnitAt(digit));
    }
    return result.toString();
  }

  static List<int>? decode(String str) {
    final cleanStr = str.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    if (cleanStr.isEmpty) return null;

    final numBytes = (cleanStr.length * 5) ~/ 8;
    final bytes = List<int>.filled(numBytes, 0);

    int i = 0;
    int index = 0;
    int lookup = 0;

    for (int charIndex = 0; charIndex < cleanStr.length; charIndex++) {
      lookup = _alphabet.indexOf(cleanStr[charIndex]);
      if (lookup == -1) return null;

      if (index <= 3) {
        index = (index + 5) % 8;
        if (index == 0) {
          bytes[i] |= lookup & 0xFF;
          i++;
        } else {
          bytes[i] |= (lookup << (8 - index)) & 0xFF;
        }
      } else {
        index = (index + 5) % 8;
        bytes[i] |= (lookup >> index) & 0xFF;
        i++;
        if (i < numBytes) {
          bytes[i] |= (lookup << (8 - index)) & 0xFF;
        }
      }
    }
    return bytes;
  }
}
