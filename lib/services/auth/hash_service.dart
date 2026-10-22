import 'dart:convert';
import 'package:crypto/crypto.dart';

class HashService {
  const HashService._();

  /// Menghasilkan hash SHA-256 untuk PIN atau Password dengan optional salt.
  static String hashPassword(String input, {String salt = 'kogo_research_salt'}) {
    final bytes = utf8.encode('$salt:$input');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verifikasi kecocokan input dengan hash yang tersimpan.
  static bool verify(String input, String storedHash, {String salt = 'kogo_research_salt'}) {
    // Juga mendukung backward-compatibility dengan hash sederhana jika data lama
    if (storedHash == input) {
      return true;
    }
    final computedHash = hashPassword(input, salt: salt);
    return computedHash == storedHash;
  }
}
