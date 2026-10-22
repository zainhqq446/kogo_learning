import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/constants/image_dataset_catalog.dart';

void main() {
  group('ImageDatasetCatalog Tests', () {
    test('ImageDatasetCatalog contains exactly 450 valid entries', () {
      expect(ImageDatasetCatalog.totalCount, equals(450));
      expect(ImageDatasetCatalog.allWords.length, equals(450));
      expect(ImageDatasetCatalog.allEntries.length, equals(450));
    });

    test('All 450 asset paths point to real physical files on disk', () {
      for (final entry in ImageDatasetCatalog.allEntries) {
        final file = File(entry.assetPath);
        expect(file.existsSync(), isTrue, reason: 'File does not exist: ${entry.assetPath}');
      }
    });

    test('Resolves words cleanly with direct match', () {
      expect(ImageDatasetCatalog.findAssetPath('pisang'), equals('assets/dataset_gambar/1_dua_suku_kata/kata_benda/pisang.png'));
      expect(ImageDatasetCatalog.findAssetPath('Apel'), equals('assets/dataset_gambar/1_dua_suku_kata/kata_benda/apel.png'));
      expect(ImageDatasetCatalog.findAssetPath('sepatu'), equals('assets/dataset_gambar/2_tiga_suku_kata/kata_benda/sepatu.png'));
      expect(ImageDatasetCatalog.findAssetPath('helikopter'), equals('assets/dataset_gambar/3_lebih_dari_tiga_suku_kata/kata_benda/helikopter.png'));
    });

    test('Resolves hyphenated segments and lesson targets properly', () {
      // Suku kata gabungan: "Bu - ku" -> "buku"
      expect(ImageDatasetCatalog.findAssetPath('Bu - ku'), equals('assets/dataset_gambar/1_dua_suku_kata/kata_benda/buku.png'));
      // Pasangan huruf & kata: "A - Apel" -> "apel"
      expect(ImageDatasetCatalog.findAssetPath('A - Apel'), equals('assets/dataset_gambar/1_dua_suku_kata/kata_benda/apel.png'));
      // Tiga suku kata: "Se - pa - tu" -> "sepatu"
      expect(ImageDatasetCatalog.findAssetPath('Se - pa - tu'), equals('assets/dataset_gambar/2_tiga_suku_kata/kata_benda/sepatu.png'));
      // Lebih dari tiga suku kata: "He - li - kop - ter" -> "helikopter"
      expect(ImageDatasetCatalog.findAssetPath('He - li - kop - ter'), equals('assets/dataset_gambar/3_lebih_dari_tiga_suku_kata/kata_benda/helikopter.png'));
    });

    test('Returns null gracefully for non-existent items', () {
      expect(ImageDatasetCatalog.findAssetPath(null), isNull);
      expect(ImageDatasetCatalog.findAssetPath(''), isNull);
      expect(ImageDatasetCatalog.findAssetPath('unknown_xyz_object'), isNull);
    });
  });
}
