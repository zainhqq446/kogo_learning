import 'package:flutter/material.dart';
import '../../../../core/theme/kogo_theme.dart';
import '../../../../data/models/child_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/repositories/child_repository.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../services/auth/hash_service.dart';
import '../../../../services/auth/session_manager.dart';
import '../../../home/presentation/pages/home_page.dart';

/// Halaman Autentikasi Kogo Voice Learning.
/// Mendukung Login Anak (Child Code + PIN) dan Login/Register Peneliti/Guru.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SessionManager _sessionManager = SessionManager.instance;
  final ChildRepository _childRepository = ChildRepository();
  final UserRepository _userRepository = UserRepository();

  // Child Login Controllers
  final _childCodeController = TextEditingController(text: 'P001');
  final _childPinController = TextEditingController(text: '1234');
  List<ChildModel> _availableChildren = [];
  bool _isLoadingChildren = false;

  // Researcher Controllers
  final _researcherUserCtrl = TextEditingController(text: 'researcher');
  final _researcherPassCtrl = TextEditingController(text: 'kogo2026');
  bool _isRegisterMode = false;
  final _regUsernameCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();

  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadChildren();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _childCodeController.dispose();
    _childPinController.dispose();
    _researcherUserCtrl.dispose();
    _researcherPassCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChildren() async {
    setState(() => _isLoadingChildren = true);
    try {
      final children = await _childRepository.getAllChildren();
      if (mounted) {
        setState(() {
          _availableChildren = children;
          _isLoadingChildren = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingChildren = false);
      }
    }
  }

  Future<void> _handleChildLogin() async {
    final code = _childCodeController.text.trim();
    final pin = _childPinController.text.trim();

    if (code.isEmpty || pin.isEmpty) {
      setState(() => _errorMessage = 'Mohon masukkan Kode Anak dan PIN.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final child = await _sessionManager.loginChild(childCode: code, pin: pin);
      if (child == null) {
        setState(() {
          _errorMessage = 'Kode anak atau PIN salah. Pastikan PIN benar (default: 1234).';
          _isSubmitting = false;
        });
        return;
      }

      // Mulai research session otomatis untuk anak ini
      try {
        await _sessionManager.startResearchSession(notes: 'Sesi latihan belajar anak $code');
      } catch (sessionErr) {
        debugPrint('[AuthPage] Warning: Research session init: $sessionErr');
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Terjadi kesalahan saat masuk: $e';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleResearcherLogin() async {
    final username = _researcherUserCtrl.text.trim();
    final password = _researcherPassCtrl.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Username dan password wajib diisi.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final user = await _sessionManager.loginResearcher(
        username: username,
        password: password,
      );

      if (user == null) {
        setState(() {
          _errorMessage = 'Username atau password salah.';
          _isSubmitting = false;
        });
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Kesalahan login peneliti: $e';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleResearcherRegister() async {
    final username = _regUsernameCtrl.text.trim();
    final password = _regPasswordCtrl.text.trim();

    if (username.isEmpty || password.length < 4) {
      setState(() => _errorMessage = 'Username minimal 3 karakter & Password minimal 4 karakter.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final existing = await _userRepository.getByUsername(username);
      if (existing != null) {
        setState(() {
          _errorMessage = 'Username "$username" sudah terdaftar. Silakan pilih username lain.';
          _isSubmitting = false;
        });
        return;
      }

      final now = DateTime.now().toIso8601String();
      final newUser = UserModel(
        username: username,
        passwordHash: HashService.hashPassword(password),
        role: 'researcher',
        createdAt: now,
        updatedAt: now,
      );

      await _userRepository.insertUser(newUser);

      // Auto login setelah registrasi
      await _sessionManager.loginResearcher(username: username, password: password);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Akun $username berhasil didaftarkan! Selamat datang.'),
            backgroundColor: KogoTheme.leafGreen,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Gagal mendaftarkan akun: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KogoTheme.creamBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo & Header
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: KogoTheme.softPeach,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: KogoTheme.primaryCoral.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('🐻', style: TextStyle(fontSize: 48)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Kogo Voice Learning',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: KogoTheme.darkSlate,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pintar Membaca & Bersuara Bersama Kogo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: KogoTheme.lightSlate,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tab Bar Pemilihan Login Anak vs Peneliti
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: KogoTheme.primaryCoral,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: KogoTheme.mediumSlate,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.face_rounded, size: 20),
                          text: 'Anak / Peserta',
                        ),
                        Tab(
                          icon: Icon(Icons.school_rounded, size: 20),
                          text: 'Guru / Peneliti',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Pesan Kesalahan jika ada
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF87171)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Konten Tab
                  SizedBox(
                    height: 380,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildChildTab(),
                        _buildResearcherTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChildTab() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masuk Akun Anak',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoTheme.darkSlate),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pilih ID Peserta atau masukkan Kode dan PIN:',
              style: TextStyle(fontSize: 13, color: KogoTheme.lightSlate),
            ),
            const SizedBox(height: 14),

            // Dropdown cepat daftar anak jika tersedia
            if (_isLoadingChildren) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: KogoTheme.primaryCoral),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ] else if (_availableChildren.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: KogoTheme.creamSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: KogoTheme.sunnyYellow.withValues(alpha: 0.5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _availableChildren.any((c) => c.childCode == _childCodeController.text)
                        ? _childCodeController.text
                        : _availableChildren.first.childCode,
                    hint: const Text('Pilih Anak...'),
                    items: _availableChildren.map((c) {
                      return DropdownMenuItem<String>(
                        value: c.childCode,
                        child: Row(
                          children: [
                            const Text('🧒 ', style: TextStyle(fontSize: 16)),
                            Text('${c.childCode} — ${c.displayName} (${c.age ?? 6} thn)'),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _childCodeController.text = val;
                          _childPinController.text = '1234'; // Default PIN
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _childCodeController,
              decoration: InputDecoration(
                labelText: 'Kode Anak (Contoh: P001)',
                prefixIcon: const Icon(Icons.badge_rounded, color: KogoTheme.primaryCoral),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _childPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'PIN 4 Digit (Default: 1234)',
                prefixIcon: const Icon(Icons.pin_rounded, color: KogoTheme.primaryCoral),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: KogoTheme.primaryCoral,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isSubmitting ? null : _handleChildLogin,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text('Mulai Belajar Sekarang!'),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildResearcherTab() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _isRegisterMode ? 'Daftar Peneliti Baru' : 'Login Guru / Peneliti',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: KogoTheme.darkSlate),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isRegisterMode = !_isRegisterMode;
                      _errorMessage = null;
                    });
                  },
                  child: Text(
                    _isRegisterMode ? 'Sudah Punya Akun' : 'Daftar Baru',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: KogoTheme.skyBlue),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (!_isRegisterMode) ...[
              TextField(
                controller: _researcherUserCtrl,
                decoration: InputDecoration(
                  labelText: 'Username (Default: researcher)',
                  prefixIcon: const Icon(Icons.person_rounded, color: KogoTheme.skyBlue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _researcherPassCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password (Default: kogo2026)',
                  prefixIcon: const Icon(Icons.lock_rounded, color: KogoTheme.skyBlue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KogoTheme.skyBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _handleResearcherLogin,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Masuk Dashboard Peneliti'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _regUsernameCtrl,
                decoration: InputDecoration(
                  labelText: 'Username Baru',
                  prefixIcon: const Icon(Icons.person_add_rounded, color: KogoTheme.leafGreen),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _regPasswordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password Baru',
                  prefixIcon: const Icon(Icons.vpn_key_rounded, color: KogoTheme.leafGreen),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KogoTheme.leafGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isSubmitting ? null : _handleResearcherRegister,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('Daftar & Masuk'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
