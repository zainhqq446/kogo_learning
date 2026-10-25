import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/constants/backend_config.dart';

class AuthRemoteResult {
  final bool success;
  final String? message;
  final String? userId;
  final String? username;
  final String? fullName;
  final String? role;
  final int? ageYears;
  final String? schoolName;
  final String? accessToken;
  final String? refreshToken;

  const AuthRemoteResult({
    required this.success,
    this.message,
    this.userId,
    this.username,
    this.fullName,
    this.role,
    this.ageYears,
    this.schoolName,
    this.accessToken,
    this.refreshToken,
  });
}

class AuthRemoteService {
  static final AuthRemoteService instance = AuthRemoteService();

  final HttpClient _httpClient;

  AuthRemoteService({HttpClient? httpClient}) : _httpClient = httpClient ?? HttpClient();

  /// Registrasi akun anak ke backend Express + PostgreSQL
  Future<AuthRemoteResult> registerChild({
    required String fullName,
    required String username,
    required String password,
    required int ageYears,
    required String schoolName,
  }) async {
    final url = Uri.parse('${BackendConfig.apiBaseUrl}/auth/register/child');
    try {
      final request = await _httpClient.postUrl(url).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'fullName': fullName.trim(),
        'username': username.trim().toLowerCase(),
        'password': password.trim(),
        'ageYears': ageYears,
        'schoolName': schoolName.trim(),
      });
      request.write(body);

      final response = await request.close().timeout(const Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final userData = data['data'] as Map<String, dynamic>?;
        return AuthRemoteResult(
          success: true,
          message: data['message'] as String? ?? 'Registrasi anak berhasil',
          userId: userData?['id'] as String?,
          username: userData?['username'] as String?,
          fullName: userData?['fullName'] as String?,
          role: userData?['role'] as String? ?? 'child',
          ageYears: userData?['ageYears'] as int?,
          schoolName: userData?['schoolName'] as String?,
        );
      } else {
        return AuthRemoteResult(
          success: false,
          message: data['message'] as String? ?? 'Gagal mendaftar (kode status: ${response.statusCode})',
        );
      }
    } catch (e) {
      return AuthRemoteResult(
        success: false,
        message: 'Gagal menghubungi server backend: $e',
      );
    }
  }

  /// Login akun anak atau peneliti ke backend Express + PostgreSQL
  Future<AuthRemoteResult> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('${BackendConfig.apiBaseUrl}/auth/login');
    try {
      final request = await _httpClient.postUrl(url).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'username': username.trim().toLowerCase(),
        'password': password.trim(),
      });
      request.write(body);

      final response = await request.close().timeout(const Duration(seconds: 10));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final resData = data['data'] as Map<String, dynamic>?;
        final userData = resData?['user'] as Map<String, dynamic>?;
        final tokenData = resData?['tokens'] as Map<String, dynamic>?;

        return AuthRemoteResult(
          success: true,
          message: data['message'] as String? ?? 'Login berhasil',
          userId: userData?['id'] as String?,
          username: userData?['username'] as String?,
          fullName: userData?['fullName'] as String?,
          role: userData?['role'] as String?,
          ageYears: userData?['ageYears'] as int?,
          schoolName: userData?['schoolName'] as String?,
          accessToken: tokenData?['accessToken'] as String?,
          refreshToken: tokenData?['refreshToken'] as String?,
        );
      } else {
        return AuthRemoteResult(
          success: false,
          message: data['message'] as String? ?? 'Login gagal (kode status: ${response.statusCode})',
        );
      }
    } catch (e) {
      return AuthRemoteResult(
        success: false,
        message: 'Koneksi ke backend gagal: $e',
      );
    }
  }
}