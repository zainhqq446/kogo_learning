import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/services/auth/hash_service.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.deleteDatabase();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('HashService hashes and verifies PIN and passwords properly', () {
    final pinHash = HashService.hashPassword('1234');
    expect(pinHash, isNot(equals('1234')));
    expect(HashService.verify('1234', pinHash), isTrue);
    expect(HashService.verify('9999', pinHash), isFalse);
  });

  test('Child authentication, device identity, multi-child device sharing, and sessions', () async {
    final sessionManager = SessionManager.instance;

    // 1. Inisialisasi Device Identity
    final device = await sessionManager.initDevice(
      deviceId: 'samsung-tab-a9-001',
      deviceLabel: 'Tablet Kelas A',
      platform: 'android',
      appVersion: '1.0.0',
    );
    expect(device.id, isNotNull);
    expect(device.deviceId, equals('samsung-tab-a9-001'));

    // 2. Child 1 (P001) login dengan PIN yang benar
    final child1 = await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    expect(child1, isNotNull);
    expect(child1!.childCode, equals('P001'));
    expect(sessionManager.isChildLoggedIn, isTrue);

    // Gagal login dengan PIN salah
    final failedLogin = await sessionManager.loginChild(childCode: 'P001', pin: 'wrong-pin');
    expect(failedLogin, isNull);

    // Login kembali dengan benar
    await sessionManager.loginChild(childCode: 'P001', pin: '1234');

    // 3. Child 1 memulai research session pada device tersebut
    final session1 = await sessionManager.startResearchSession(notes: 'Sesi latihan huruf P001');
    expect(session1.id, isNotNull);
    expect(session1.childId, equals(child1.id));
    expect(session1.deviceId, equals(device.id));
    expect(session1.sessionNumber, equals(1));
    expect(session1.startedAt, isNotEmpty);
    expect(session1.endedAt, isNull);

    // Child 1 menyelesaikan research session
    final endedSession1 = await sessionManager.endResearchSession(notes: 'Sesi selesai sempurna');
    expect(endedSession1, isNotNull);
    expect(endedSession1!.endedAt, isNotNull);

    // Sesi kedua untuk Child 1 pada device yang sama (session_number bertambah)
    final session1Round2 = await sessionManager.startResearchSession(notes: 'Sesi 2 P001');
    expect(session1Round2.sessionNumber, equals(2));
    await sessionManager.endResearchSession();

    // 4. Logout Child 1
    await sessionManager.logoutChild();
    expect(sessionManager.isChildLoggedIn, isFalse);

    // 5. Child 2 (P002) login pada device yang SAMA (multi-child per device)
    final child2 = await sessionManager.loginChild(childCode: 'P002', pin: '1234');
    expect(child2, isNotNull);
    expect(child2!.childCode, equals('P002'));
    expect(child2.id, isNot(equals(child1.id)));

    // Child 2 memulai sesi pada device yang sama
    final sessionChild2 = await sessionManager.startResearchSession(notes: 'Sesi P002');
    expect(sessionChild2.childId, equals(child2.id));
    expect(sessionChild2.deviceId, equals(device.id));
    expect(sessionChild2.sessionNumber, equals(1)); // Nomor sesi pertama untuk child 2
    await sessionManager.endResearchSession();

    // 6. Verifikasi isolasi data: Child 2 hanya melihat sesi miliknya sendiri
    final child2Sessions = await sessionManager.getMySessions();
    expect(child2Sessions.length, equals(1));
    expect(child2Sessions.first.childId, equals(child2.id));

    await sessionManager.logoutChild();

    // 7. Login Peneliti / Guru (researcher)
    final researcher = await sessionManager.loginResearcher(
      username: 'researcher',
      password: 'kogo2026',
    );
    expect(researcher, isNotNull);
    expect(researcher!.role, equals('researcher'));
    expect(sessionManager.isResearcherLoggedIn, isTrue);

    // Password salah untuk researcher ditolak
    final failedResearcher = await sessionManager.loginResearcher(
      username: 'researcher',
      password: 'wrongpassword',
    );
    expect(failedResearcher, isNull);
  });
}
