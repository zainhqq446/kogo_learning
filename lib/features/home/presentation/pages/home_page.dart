import 'package:flutter/material.dart';

import '../../../../core/telemetry/startup_telemetry.dart';
import '../../../../data/models/child_model.dart';
import '../../../../data/models/stage_model.dart';
import '../../../../data/repositories/progress_repository.dart';
import '../../../../data/repositories/stage_repository.dart';
import '../../../../services/auth/session_manager.dart';
import '../../../lesson/presentation/pages/lesson_page.dart';
import '../../../navigation/presentation/widgets/bottom_nav_bar.dart';
import '../../../progress/presentation/pages/child_progress_page.dart';
import '../../../speech/presentation/pages/kogo_voice_playground_page.dart';
import '../../../stage/presentation/pages/stage_page.dart';
import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/sync/sync_service.dart';

/// Halaman Home Kogo Voice Learning yang mengadopsi desain visual Figma (HomeScreen, RewardsScreen, ProfileScreen).
/// Menggunakan warna-warna gradien cerah, maskot interaktif, animasi lembut, dan navigasi ramah anak.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final SessionManager _sessionManager = SessionManager.instance;
  final StageRepository _stageRepository = StageRepository();
  final ProgressRepository _progressRepository = ProgressRepository();

  ChildModel? _child;
  int _activeNavIndex = 0;
  final Set<int> _visitedTabs = {0};
  List<StageModel> _stages = [];

  // Data ringkasan untuk Tab Hadiah & Profil
  int _completedQuestions = 0;
  int _totalAttempts = 0;
  int _correctAttempts = 0;
  double _accuracy = 0.0;
  int _unlockedAchievements = 0;

  late final AnimationController _mascotAnimController;
  late final Animation<double> _mascotBobAnimation;
  late final Animation<double> _mascotWiggleAnimation;

  @override
  void initState() {
    super.initState();
    StartupTelemetry.onHomeInitStart();
    _child = _sessionManager.currentChild;
    _mascotAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _mascotBobAnimation = Tween<double>(begin: 0, end: -12).animate(
      CurvedAnimation(parent: _mascotAnimController, curve: Curves.easeInOut),
    );

    _mascotWiggleAnimation = Tween<double>(begin: -0.06, end: 0.06).animate(
      CurvedAnimation(parent: _mascotAnimController, curve: Curves.easeInOut),
    );

    // Tier 1: Muat data esensial untuk HomeScreen UI terlebih dahulu
    _loadInitialData();

    // Tier 2: Jadwalkan pemuatan data non-kritis setelah frame pertama ter-render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupTelemetry.onFirstFrame();
      _loadSecondaryData();
    });
  }

  /// Memuat data kritis (daftar stage) agar HomeScreen dapat segera ditampilkan.
  Future<void> _loadInitialData() async {
    try {
      final currentChild = _sessionManager.currentChild;
      final stages = await _stageRepository.getAll();
      if (mounted) {
        setState(() {
          _child = currentChild;
          _stages = stages;
        });
        StartupTelemetry.onHomeCriticalDataLoaded(stages.length);
      }
    } catch (e) {
      debugPrint('[HomePage] Load initial stages error: $e');
    }
  }

  /// Memuat data progres & pencapaian anak di background tanpa memblok first frame.
  Future<void> _loadSecondaryData() async {
    try {
      final childId = _sessionManager.currentChild?.id ?? 1;
      final summary = await _progressRepository.getProgressSummary(childId);
      if (mounted) {
        setState(() {
          _completedQuestions = summary.completedQuestions;
          _totalAttempts = summary.totalAttempts;
          _correctAttempts = summary.correctAttempts;
          _accuracy = summary.accuracyPercent;
          _unlockedAchievements = summary.earnedAchievements.length;
        });
        StartupTelemetry.onSecondaryDataComplete();
      }
    } catch (e) {
      debugPrint('[HomePage] Load secondary data error: $e');
    }
  }

  /// Memuat semua data secara berurutan (dipertahankan untuk kompatibilitas penuh).
  Future<void> _loadData() async {
    await _loadInitialData();
    await _loadSecondaryData();
  }

  @override
  void dispose() {
    _mascotAnimController.dispose();
    super.dispose();
  }

  Future<void> _openStageByIndex(int stageIndex) async {
    if (_stages.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StagePage()),
      );
      return;
    }

    final targetStage = (stageIndex < _stages.length) ? _stages[stageIndex] : _stages.first;
    if (!mounted) return;

    // Pilihan kategori di Home langsung membuka Map pembelajaran kategori tersebut.
    // Penguncian checkpoint diterapkan di dalam Map per akun anak.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonPage(stage: targetStage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradien dinamis sesuai tab aktif
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _activeNavIndex == 0
                      ? const [Color(0xFFFEF3C7), Color(0xFFFFF7ED), Color(0xFFFDF2F8)] // Yellow-100 to Pink-50
                      : _activeNavIndex == 1
                          ? const [Color(0xFFFEF3C7), Color(0xFFFFFBEB), Color(0xFFFFEDD5)] // Amber-100 to Orange-50
                          : const [Color(0xFFFCE7F3), Color(0xFFF3E8FF), Color(0xFFEFF6FF)], // Pink-100 to Blue-50
                ),
              ),
            ),
          ),

          // Elemen ornamen mengambang di latar belakang (Figma HomeScreen decoration)
          _buildFloatingDecorations(),

          // Konten Utama berdasarkan tab aktif dengan Lazy Evaluation untuk tab sekunder
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _activeNavIndex,
              children: [
                _buildHomeScreenContent(),
                _visitedTabs.contains(1)
                    ? _buildRewardsScreenContent()
                    : const SizedBox.shrink(),
                _visitedTabs.contains(2)
                    ? _buildProfileScreenContent()
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: KogoBottomNav(
        currentIndex: _activeNavIndex,
        onTap: (index) {
          setState(() {
            _activeNavIndex = index;
            _visitedTabs.add(index);
          });
          _loadData();
        },
      ),
    );
  }

  Widget _buildFloatingDecorations() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 60,
            left: 20,
            child: Text('⭐', style: TextStyle(fontSize: 26, color: Colors.amber.withValues(alpha: 0.7))),
          ),
          Positioned(
            top: 100,
            right: 28,
            child: Text('✨', style: TextStyle(fontSize: 22, color: Colors.orange.withValues(alpha: 0.7))),
          ),
          Positioned(
            top: 280,
            left: 24,
            child: Text('☁️', style: TextStyle(fontSize: 34, color: Colors.white.withValues(alpha: 0.6))),
          ),
          Positioned(
            bottom: 120,
            right: 24,
            child: Text('☁️', style: TextStyle(fontSize: 36, color: Colors.white.withValues(alpha: 0.5))),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: HOME SCREEN (Mirip HomeScreen.tsx)
  // ==========================================
  Widget _buildHomeScreenContent() {
    final childName = _child?.displayName ?? (_child != null ? 'Peserta ${_child!.childCode}' : 'Sahabat Kogo');

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card Putih Melengkung dengan Maskot (Sesuai Figma HomeScreen)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Badge Status Auto-Sync Latar Belakang Non-Intrusif
                StreamBuilder<SyncStatus>(
                  stream: SyncService.instance.statusStream,
                  initialData: SyncService.instance.currentStatus,
                  builder: (context, snapshot) {
                    final status = snapshot.data ?? SyncStatus.idle;
                    Color badgeBg = const Color(0xFFF3F4F6);
                    Color badgeFg = const Color(0xFF6B7280);
                    String badgeText = 'Online';
                    IconData badgeIcon = Icons.wifi_rounded;

                    if (status == SyncStatus.syncing) {
                      badgeBg = const Color(0xFFEFF6FF);
                      badgeFg = const Color(0xFF2563EB);
                      badgeText = 'Menyinkronkan data...';
                      badgeIcon = Icons.sync_rounded;
                    } else if (status == SyncStatus.success) {
                      badgeBg = const Color(0xFFF0FDF4);
                      badgeFg = const Color(0xFF16A34A);
                      badgeText = 'Data tersimpan otomatis';
                      badgeIcon = Icons.cloud_done_rounded;
                    } else if (status == SyncStatus.offline) {
                      badgeBg = const Color(0xFFFFFBEB);
                      badgeFg = const Color(0xFFD97706);
                      badgeText = 'Offline (Tersimpan aman)';
                      badgeIcon = Icons.cloud_queue_rounded;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 14, color: badgeFg),
                          const SizedBox(width: 5),
                          Text(
                            badgeText,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: badgeFg),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Salam ramah anak (Kompatibilitas dengan teks tes unit 'Halo,' & 'Ayo belajar')
                Text(
                  'Halo, $childName! 👋',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Ayo belajar bicara & bersuara hari ini!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D9488), // Teal-600
                  ),
                ),

                const SizedBox(height: 18),

                // Maskot Kogo dengan animasi Melayang & Bergoyang
                AnimatedBuilder(
                  animation: _mascotAnimController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _mascotBobAnimation.value),
                      child: Transform.rotate(
                        angle: _mascotWiggleAnimation.value,
                        child: child,
                      ),
                    );
                  },
                  child: GestureDetector(
                    onTap: () {
                      KogoVoiceManager.instance.playGreeting(childName);
                    },
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFDE047), Color(0xFFFB923C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('🐻', style: TextStyle(fontSize: 54)),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  'Selamat datang di perjalanan belajarmu! 🎉',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),

                const SizedBox(height: 14),

                // Hero Banner Mulai Belajar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Kogo Voice Learning',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const StagePage()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Mulai Belajar Sekarang',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Grid 4 Kategori Belajar Berwarna-warni (Persis Figma HomeScreen.tsx)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 12, top: 4),
                  child: Text(
                    'Pilihan Pelajaran',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.15,
                  children: [
                    _buildCategoryCard(
                      title: 'Latihan Huruf',
                      icon: Icons.menu_book_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF87171), Color(0xFFDC2626)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shadowColor: const Color(0xFFF87171).withValues(alpha: 0.4),
                      onTap: () => _openStageByIndex(0),
                    ),
                    _buildCategoryCard(
                      title: 'Kata Dua Suku Kata',
                      icon: Icons.chat_bubble_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFB923C), Color(0xFFEA580C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shadowColor: const Color(0xFFFB923C).withValues(alpha: 0.4),
                      onTap: () => _openStageByIndex(1),
                    ),
                    _buildCategoryCard(
                      title: 'Kata Tiga Suku Kata',
                      icon: Icons.volume_up_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shadowColor: const Color(0xFF2DD4BF).withValues(alpha: 0.4),
                      onTap: () => _openStageByIndex(2),
                    ),
                    _buildCategoryCard(
                      title: 'Beberapa Kata',
                      icon: Icons.forum_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shadowColor: const Color(0xFFA855F7).withValues(alpha: 0.4),
                      onTap: () => _openStageByIndex(3),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Menu Cepat Tambahan: Tahap Belajar & Pencapaian (Memenuhi test expectation)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildSmallQuickCard(
                    title: 'Tahap Belajar',
                    subtitle: 'Semua level',
                    icon: Icons.alt_route_rounded,
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StagePage()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSmallQuickCard(
                    title: 'Pencapaian',
                    subtitle: 'Lencana & Bintang',
                    icon: Icons.military_tech_rounded,
                    color: const Color(0xFFEAB308),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChildProgressPage()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Menu Testing/Dev: Kogo Voice Playground
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildSmallQuickCard(
              title: 'Voice Playground',
              subtitle: 'Tes Kualitas Suara Kogo',
              icon: Icons.record_voice_over_rounded,
              color: const Color(0xFF8B5CF6),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const KogoVoicePlaygroundPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required Gradient gradient,
    required Color shadowColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallQuickCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: REWARDS SCREEN (Mirip RewardsScreen.tsx)
  // ==========================================
  Widget _buildRewardsScreenContent() {
    final tiers = [
      {
        'level': 'Perunggu',
        'colors': [const Color(0xFFFB923C), const Color(0xFFD97706)],
        'icon': Icons.military_tech_rounded,
        'earned': _completedQuestions >= 1,
        'progress': (_completedQuestions >= 1 ? 1.0 : (_completedQuestions / 1.0)).clamp(0.0, 1.0),
      },
      {
        'level': 'Perak',
        'colors': [const Color(0xFFCBD5E1), const Color(0xFF64748B)],
        'icon': Icons.star_rounded,
        'earned': _correctAttempts >= 5,
        'progress': (_correctAttempts / 5.0).clamp(0.0, 1.0),
      },
      {
        'level': 'Emas',
        'colors': [const Color(0xFFFBBF24), const Color(0xFFD97706)],
        'icon': Icons.emoji_events_rounded,
        'earned': _correctAttempts >= 10,
        'progress': (_correctAttempts / 10.0).clamp(0.0, 1.0),
      },
      {
        'level': 'Berlian',
        'colors': [const Color(0xFF38BDF8), const Color(0xFF2563EB)],
        'icon': Icons.workspace_premium_rounded,
        'earned': _unlockedAchievements >= 3,
        'progress': (_unlockedAchievements / 3.0).clamp(0.0, 1.0),
      },
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // Header Judul Hadiah
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_rounded, color: Color(0xFFD97706), size: 28),
                SizedBox(width: 8),
                Text(
                  'Hadiah',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Selebrasi Maskot
          const Text('🎉', style: TextStyle(fontSize: 70)),

          const SizedBox(height: 20),

          // Daftar Kartu Hadiah
          ...tiers.map((tier) {
            final colors = tier['colors'] as List<Color>;
            final level = tier['level'] as String;
            final icon = tier['icon'] as IconData;
            final earned = tier['earned'] as bool;
            final progress = tier['progress'] as double;
            final percentText = '${(progress * 100).toInt()}% Selesai';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: colors.first.withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 34),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  level,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                if (earned) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 22),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFE5E7EB),
                                valueColor: AlwaysStoppedAnimation<Color>(colors.first),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              earned ? 'Selesai! 🎉' : percentText,
                              style: TextStyle(
                                fontSize: 12,
                                color: earned ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                                fontWeight: earned ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (earned)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF34D399), Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '✓ Diraih!',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          // Pesan Motivasi
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC084FC), Color(0xFFF472B6)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC084FC).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Column(
              children: [
                Text(
                  'Terus Belajar! 🌟',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  'Selesaikan lebih banyak pelajaran untuk membuka hadiah menakjubkan!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: PROFILE SCREEN (Mirip ProfileScreen.tsx)
  // ==========================================
  Widget _buildProfileScreenContent() {
    final childName = _child?.displayName ?? (_child != null ? 'Peserta ${_child!.childCode}' : 'Sahabat Kogo');
    final childCode = _child?.childCode ?? 'P001';
    final childAge = _child?.age != null ? '${_child!.age} tahun' : '6 tahun';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // Header Profil
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_rounded, color: Color(0xFF9333EA), size: 28),
                SizedBox(width: 8),
                Text(
                  'Profil Saya',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Foto Profil / Maskot Avatar Gadis
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFC084FC), Color(0xFFEC4899)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC084FC).withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('👧', style: TextStyle(fontSize: 54)),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Kartu Informasi Profil
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildProfileDetailRow(
                  label: 'Nama Lengkap',
                  value: childName,
                  icon: Icons.person_outline_rounded,
                  colors: const [Color(0xFFC084FC), Color(0xFFF472B6)],
                ),
                const Divider(height: 24),
                _buildProfileDetailRow(
                  label: 'ID / Username Peserta',
                  value: childCode,
                  icon: Icons.badge_outlined,
                  colors: const [Color(0xFF60A5FA), Color(0xFF22D3EE)],
                ),
                const Divider(height: 24),
                _buildProfileDetailRow(
                  label: 'Usia',
                  value: childAge,
                  icon: Icons.cake_outlined,
                  colors: const [Color(0xFFFB923C), Color(0xFFF87171)],
                ),
                if (_child?.schoolName != null && _child!.schoolName!.isNotEmpty) ...[
                  const Divider(height: 24),
                  _buildProfileDetailRow(
                    label: 'Sekolah / TK',
                    value: _child!.schoolName!,
                    icon: Icons.school_outlined,
                    colors: const [Color(0xFF34D399), Color(0xFF059669)],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Kartu Statistik Progres
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, color: Color(0xFF9333EA), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Statistik Progress',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStatItem(
                  label: 'Soal Selesai',
                  value: '$_completedQuestions',
                  icon: Icons.check_circle_outline_rounded,
                  colors: const [Color(0xFF4ADE80), Color(0xFF10B981)],
                ),
                const SizedBox(height: 12),
                _buildStatItem(
                  label: 'Total Percobaan',
                  value: '$_totalAttempts',
                  icon: Icons.history_rounded,
                  colors: const [Color(0xFF38BDF8), Color(0xFF2563EB)],
                ),
                const SizedBox(height: 12),
                _buildStatItem(
                  label: 'Akurasi Jawaban',
                  value: '${_accuracy.toStringAsFixed(0)}%',
                  icon: Icons.insights_rounded,
                  colors: const [Color(0xFFFBBF24), Color(0xFFF97316)],
                ),
                const SizedBox(height: 12),
                _buildStatItem(
                  label: 'Lencana Diraih',
                  value: '$_unlockedAchievements',
                  icon: Icons.workspace_premium_rounded,
                  colors: const [Color(0xFFC084FC), Color(0xFFEC4899)],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Status Sinkronisasi Otomatis Penelitian (Otomatis Latar Belakang)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: StreamBuilder<SyncStatus>(
              stream: SyncService.instance.statusStream,
              initialData: SyncService.instance.currentStatus,
              builder: (context, snapshot) {
                final status = snapshot.data ?? SyncStatus.idle;
                IconData statusIcon;
                Color statusColor;
                String statusLabel;
                String statusDesc;

                switch (status) {
                  case SyncStatus.syncing:
                    statusIcon = Icons.sync_rounded;
                    statusColor = const Color(0xFF2563EB);
                    statusLabel = 'Sinkronisasi Berjalan...';
                    statusDesc = 'Data pembelajaran sedang dikirim otomatis ke server PostgreSQL.';
                    break;
                  case SyncStatus.success:
                    statusIcon = Icons.cloud_done_rounded;
                    statusColor = const Color(0xFF16A34A);
                    statusLabel = 'Tersinkronisasi Otomatis';
                    statusDesc = 'Seluruh sesi & rekaman evaluasi tersimpan rapi di server penelitian.';
                    break;
                  case SyncStatus.offline:
                    statusIcon = Icons.cloud_off_rounded;
                    statusColor = const Color(0xFFD97706);
                    statusLabel = 'Mode Offline (Tersimpan Lokal)';
                    statusDesc = 'Data tersimpan aman di SQLite lokal dan akan otomatis sinkron saat terhubung.';
                    break;
                  case SyncStatus.idle:
                    statusIcon = Icons.cloud_queue_rounded;
                    statusColor = const Color(0xFF0D9488);
                    statusLabel = 'Sinkronisasi Otomatis Aktif';
                    statusDesc = 'Aplikasi otomatis menyinkronkan data setiap soal selesai dijawab.';
                    break;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          statusLabel,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                        const Spacer(),
                        // Opsi lanjutan untuk peneliti melakukan paksa sinkronisasi
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, size: 18, color: Color(0xFF9CA3AF)),
                          tooltip: 'Pengaturan Sinkronisasi Peneliti',
                          onPressed: _showSyncDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statusDesc,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.3),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Tombol Ganti Akun / Keluar
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                final nav = Navigator.of(context);
                await _sessionManager.logoutChild();
                if (mounted) {
                  nav.pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text(
                'Ganti Akun / Keluar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Maskot Beruang
          const Text('🐻', style: TextStyle(fontSize: 50)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Menampilkan dialog sinkronisasi manual untuk peneliti
  void _showSyncDialog() {
    final urlController = TextEditingController(text: 'http://192.168.1.10:4000');
    final tokenController = TextEditingController();
    bool isSyncing = false;
    String? statusMessage;
    bool isSuccess = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.cloud_upload_rounded, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text('Sinkronisasi Data Riset', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Masukkan alamat server backend lokal dan token autentikasi peneliti:',
                      style: TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: urlController,
                      enabled: !isSyncing,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Base URL Backend',
                        hintText: 'http://192.168.1.10:4000',
                        prefixIcon: const Icon(Icons.lan_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tokenController,
                      enabled: !isSyncing,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Access Token Peneliti',
                        hintText: 'Tempel JWT token di sini',
                        prefixIcon: const Icon(Icons.key_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSuccess ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                              size: 18,
                              color: isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                statusMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSuccess ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSyncing ? null : () => Navigator.pop(dialogContext),
                  child: Text(isSuccess ? 'Tutup' : 'Batal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSyncing
                      ? null
                      : () async {
                          final rawUrl = urlController.text.trim();
                          final rawToken = tokenController.text.trim();

                          if (rawUrl.isEmpty) {
                            setDialogState(() {
                              statusMessage = 'Base URL tidak boleh kosong.';
                              isSuccess = false;
                            });
                            return;
                          }

                          final parsedUri = Uri.tryParse(rawUrl);
                          if (parsedUri == null || !parsedUri.hasScheme || parsedUri.host.isEmpty) {
                            setDialogState(() {
                              statusMessage = 'Format URL tidak valid. Gunakan format http://IP:PORT';
                              isSuccess = false;
                            });
                            return;
                          }

                          if (rawToken.isEmpty) {
                            setDialogState(() {
                              statusMessage = 'Token autentikasi wajib diisi.';
                              isSuccess = false;
                            });
                            return;
                          }

                          setDialogState(() {
                            isSyncing = true;
                            statusMessage = 'Menghubungi server dan mengirim data...';
                            isSuccess = false;
                          });

                          try {
                            final syncService = SyncService();
                            final result = await syncService.syncPendingData(
                              baseUrl: rawUrl,
                              authToken: rawToken,
                            );

                            setDialogState(() {
                              isSyncing = false;
                              if (result.success) {
                                isSuccess = true;
                                if (result.syncedSessions == 0 && result.syncedAttempts == 0) {
                                  statusMessage = 'Semua data lokal sudah tersinkronisasi sebelumnya (0 data tertunda).';
                                } else {
                                  statusMessage = 'Sukses! Berhasil menyinkronkan ${result.syncedSessions} sesi dan ${result.syncedAttempts} percobaan.';
                                }
                              } else {
                                isSuccess = false;
                                final errorDetails = result.errors.isNotEmpty
                                    ? '\nAlasan: ${result.errors.take(2).join('; ')}'
                                    : '';
                                if (result.isPartialSuccess) {
                                  statusMessage = 'Sebagian tersinkron: ${result.syncedSessions} sesi, ${result.syncedAttempts} percobaan. Gagal: ${result.failedItems} item.$errorDetails';
                                } else if (result.isAllFailed) {
                                  statusMessage = 'Sinkronisasi gagal: Seluruh ${result.failedItems} item ditolak server.$errorDetails';
                                } else {
                                  statusMessage = (result.message ?? 'Sinkronisasi gagal.') + errorDetails;
                                }
                              }
                            });
                          } catch (e) {
                            setDialogState(() {
                              isSyncing = false;
                              isSuccess = false;
                              statusMessage = 'Gagal menghubungi server: $e';
                            });
                          }
                        },
                  child: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Mulai Sinkron'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileDetailRow({
    required String label,
    required String value,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
      ],
    );
  }
}
