import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/repositories/stage_repository.dart';
import 'package:kogo_voice_learning/data/repositories/progress_repository.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    await AppDatabase.instance.close();
  });

  test('Benchmark Startup Flow (BEFORE Optimasi)', () async {
    // 1. Ukur Database Cold Creation & Open (first time initialization)
    await AppDatabase.instance.deleteDatabase();
    final swCold = Stopwatch()..start();
    await AppDatabase.instance.database;
    swCold.stop();
    final coldDbMs = swCold.elapsedMilliseconds;

    // 2. Ukur Database Warm Open (sudah ada di disk)
    await AppDatabase.instance.close();
    final swWarm = Stopwatch()..start();
    await AppDatabase.instance.database;
    swWarm.stop();
    final warmDbMs = swWarm.elapsedMilliseconds;

    // 3. Ukur HomePage _loadData() saat ini
    final stageRepo = StageRepository();
    final progressRepo = ProgressRepository();
    final childId = SessionManager.instance.currentChild?.id ?? 1;

    final swHomeData = Stopwatch()..start();
    final stages = await stageRepo.getAll();
    final summary = await progressRepo.getProgressSummary(childId);
    swHomeData.stop();
    final homeLoadDataMs = swHomeData.elapsedMilliseconds;

    // Detail breakdown HomePage:
    final swStagesOnly = Stopwatch()..start();
    await stageRepo.getAll();
    swStagesOnly.stop();
    final stagesOnlyMs = swStagesOnly.elapsedMilliseconds;

    final swProgressOnly = Stopwatch()..start();
    await progressRepo.getProgressSummary(childId);
    swProgressOnly.stop();
    final progressOnlyMs = swProgressOnly.elapsedMilliseconds;

    // ignore: avoid_print
    print('========================================');
    // ignore: avoid_print
    print('[STARTUP BENCHMARK - BEFORE]');
    // ignore: avoid_print
    print('Cold Database Init (create & seed): $coldDbMs ms');
    // ignore: avoid_print
    print('Warm Database Open: $warmDbMs ms');
    // ignore: avoid_print
    print('HomePage _loadData() Total: $homeLoadDataMs ms');
    // ignore: avoid_print
    print('  - StageRepository.getAll() (Critical for Home UI): $stagesOnlyMs ms');
    // ignore: avoid_print
    print('  - ProgressRepository.getProgressSummary() (Rewards/Profile): $progressOnlyMs ms');
    // ignore: avoid_print
    print('========================================');

    expect(stages.isNotEmpty, isTrue);
    expect(summary, isNotNull);
  });
}
