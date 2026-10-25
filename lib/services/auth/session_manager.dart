import '../../data/models/child_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/research_session_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/child_repository.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/research_session_repository.dart';
import '../../data/repositories/user_repository.dart';
import 'auth_remote_service.dart';
import 'hash_service.dart';

class SessionManager {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  final ChildRepository _childRepository = ChildRepository();
  final DeviceRepository _deviceRepository = DeviceRepository();
  final ResearchSessionRepository _sessionRepository = ResearchSessionRepository();
  final UserRepository _userRepository = UserRepository();

  DeviceModel? _currentDevice;
  ChildModel? _currentChild;
  UserModel? _currentUser;
  ResearchSessionModel? _currentSession;
  String? _authToken;

  DeviceModel? get currentDevice => _currentDevice;
  ChildModel? get currentChild => _currentChild;
  UserModel? get currentUser => _currentUser;
  ResearchSessionModel? get currentSession => _currentSession;
  String? get authToken => _authToken;

  bool get isChildLoggedIn => _currentChild != null;
  bool get isResearcherLoggedIn => _currentUser != null;
  bool get hasActiveSession => _currentSession != null;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  void setCurrentChild(ChildModel? child) {
    _currentChild = child;
    _currentUser = null;
  }


  /// Inisialisasi atau daftarkan identitas device saat aplikasi berjalan.
  Future<DeviceModel> initDevice({
    required String deviceId,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    final device = await _deviceRepository.getOrCreateDevice(
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      platform: platform,
      appVersion: appVersion,
    );
    _currentDevice = device;
    return device;
  }

  /// Login anak menggunakan childCode + PIN.
  /// Mendukung autentikasi lokal SQLite dan remote backend Express (jika terhubung).
  Future<ChildModel?> loginChild({
    required String childCode,
    required String pin,
    String? username,
    String? password,
  }) async {
    // 1. Coba login remote ke backend jika username & password disediakan
    if (username != null && password != null) {
      final remoteResult = await AuthRemoteService.instance.login(
        username: username,
        password: password,
      );
      if (remoteResult.success) {
        setAuthToken(remoteResult.accessToken);
        // Simpan / update ke SQLite lokal
        final childToSave = ChildModel(
          childCode: remoteResult.username?.toUpperCase() ?? childCode,
          displayName: remoteResult.fullName ?? remoteResult.username ?? childCode,
          age: remoteResult.ageYears ?? 6,
          schoolName: remoteResult.schoolName,
          remoteUserId: remoteResult.userId,
          pinHash: HashService.hashPassword(pin.isNotEmpty ? pin : '1234'),
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );
        final saved = await _childRepository.upsertChild(childToSave);
        _currentChild = saved;
        _currentUser = null;
        return saved;
      }
    }

    // 2. Fallback autentikasi lokal SQLite dengan childCode dan PIN
    final child = await _childRepository.authenticate(childCode, pin);
    if (child != null) {
      _currentChild = child;
      _currentUser = null; // Pisahkan konteks sesi researcher vs child
    }
    return child;
  }

  /// Login researcher / guru menggunakan username + password.
  Future<UserModel?> loginResearcher({
    required String username,
    required String password,
  }) async {
    final user = await _userRepository.authenticate(username, password);
    if (user != null) {
      _currentUser = user;
      _currentChild = null; // Pisahkan konteks sesi researcher vs child
    }
    return user;
  }

  /// Memulai sesi penelitian untuk anak yang sedang login pada device saat ini.
  Future<ResearchSessionModel> startResearchSession({String? notes}) async {
    if (_currentChild == null || _currentChild!.id == null) {
      throw StateError('Tidak dapat memulai sesi: Belum ada anak yang login.');
    }
    if (_currentDevice == null || _currentDevice!.id == null) {
      throw StateError('Tidak dapat memulai sesi: Device belum diinisialisasi.');
    }

    final session = await _sessionRepository.startSession(
      childId: _currentChild!.id!,
      deviceId: _currentDevice!.id!,
      notes: notes,
    );

    _currentSession = session;
    return session;
  }

  /// Mengakhiri sesi penelitian yang sedang berlangsung.
  Future<ResearchSessionModel?> endResearchSession({String? notes}) async {
    if (_currentSession == null || _currentSession!.id == null) {
      return null;
    }

    final ended = await _sessionRepository.endSession(
      sessionId: _currentSession!.id!,
      notes: notes,
    );

    _currentSession = null;
    return ended;
  }

  /// Mengambil riwayat sesi khusus anak yang sedang login (isolasi data).
  Future<List<ResearchSessionModel>> getMySessions() async {
    if (_currentChild == null || _currentChild!.id == null) {
      return [];
    }
    return _sessionRepository.getSessionsByChildId(_currentChild!.id!);
  }

  /// Logout anak dan tutup sesi aktif jika masih terbuka.
  Future<void> logoutChild() async {
    if (_currentSession != null) {
      await endResearchSession(notes: 'Auto-ended on child logout');
    }
    _currentChild = null;
    _authToken = null;
  }

  /// Logout researcher.
  void logoutResearcher() {
    _currentUser = null;
    _authToken = null;
  }
}

