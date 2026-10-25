import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/repositories/checkpoint_repository.dart';
import 'package:kogo_voice_learning/core/constants/image_dataset_catalog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Audit & Verifikasi Distribusi Dataset Checkpoint', () {
    late CheckpointRepository checkpointRepo;

    setUp(() {
      checkpointRepo = CheckpointRepository();
    });

    test('Katalog ImageDatasetCatalog memiliki tepat 450 gambar unik dan ada di disk', () {
      final entries = ImageDatasetCatalog.allEntries;
      expect(entries.length, equals(450));

      final uniqueWords = ImageDatasetCatalog.allWords.toSet();
      expect(uniqueWords.length, equals(450));

      int missingOnDisk = 0;
      for (final entry in entries) {
        final file = File(entry.assetPath);
        if (!file.existsSync()) {
          missingOnDisk++;
        }
      }
      expect(missingOnDisk, equals(0), reason: 'Semua 450 file gambar harus ada di disk');
    });

    test('Stage 1 menghasilkan 5 checkpoint huruf', () async {
      final cp1 = await checkpointRepo.getWordsForCheckpoint(stageId: 1, checkpointNumber: 1);
      final cp5 = await checkpointRepo.getWordsForCheckpoint(stageId: 1, checkpointNumber: 5);

      expect(cp1.length, equals(5)); // A, B, C, D, E
      expect(cp1.first.targetText, equals('A'));
      expect(cp5.isNotEmpty, isTrue); // U, V, W, X, Y, Z
    });

    test('Stage 2, 3, dan 4 masing-masing terdistribusi ke 25 checkpoint dengan 6 kata unik', () async {
      // Pastikan database terinisialisasi
      final db = await AppDatabase.instance.database;
      expect(db.isOpen, isTrue);

      final countRow = await db.rawQuery('SELECT COUNT(*) as c FROM learning_words');
      final totalWordsInDb = Sqflite.firstIntValue(countRow) ?? 0;
      expect(totalWordsInDb, equals(450), reason: 'Tabel learning_words harus berisi 450 entri dataset');

      for (int stageId = 2; stageId <= 4; stageId++) {
        final allStageWords = <String>{};

        for (int cp = 1; cp <= 25; cp++) {
          final words = await checkpointRepo.getWordsForCheckpoint(
            stageId: stageId,
            checkpointNumber: cp,
          );

          expect(words.length, equals(6), reason: 'Stage $stageId Checkpoint $cp harus berisi tepat 6 kata');

          for (final w in words) {
            expect(allStageWords.contains(w.targetText), isFalse,
                reason: 'Kata ${w.targetText} tidak boleh duplikat di stage $stageId');
            allStageWords.add(w.targetText);

            // Verifikasi gambar valid
            final q = w.toQuestionModel(lessonId: stageId * 100 + cp, orderIndex: 1);
            expect(q.imagePath, isNotNull, reason: 'Kata ${w.targetText} harus punya gambar valid');
            expect(File(q.imagePath!).existsSync(), isTrue,
                reason: 'Aset gambar ${q.imagePath} untuk kata ${w.targetText} harus ada di disk');
          }
        }

        expect(allStageWords.length, equals(150),
            reason: 'Stage $stageId harus memiliki total 150 kata unik terdistribusi merata');
      }
    });
  });
}
