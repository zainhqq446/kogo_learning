import 'vocabulary.dart';

/// Empat materi pembelajaran sesuai rancangan halaman Home pada proposal
/// (Gambar 3.23) dan desain Figma.
enum Materi {
  huruf('letters', 'Latihan Huruf'),
  duaSuku('two-syllable', 'Kata Dua Suku Kata'),
  tigaSuku('three-syllable', 'Kata Tiga Suku Kata'),
  beberapaKata('multiple', 'Beberapa Kata');

  const Materi(this.code, this.title);

  /// Kode stabil yang disimpan di database (jangan diubah).
  final String code;
  final String title;

  List<VocabItem> get items => switch (this) {
    Materi.huruf => vocabHuruf,
    Materi.duaSuku => vocabDuaSuku,
    Materi.tigaSuku => vocabTigaSuku,
    Materi.beberapaKata => vocabBeberapaKata,
  };

  static Materi fromCode(String code) => Materi.values.firstWhere((m) => m.code == code, orElse: () => Materi.huruf);
}

/// Jenis permainan. Empat permainan utama sesuai proposal (Listen & Repeat,
/// Find Object, Missing Letter, Matching Object) ditambah dua aktivitas dari
/// desain Figma (Dengar & Pilih, Isi Huruf Kosong).
enum GameType {
  listenRepeat('speaking', 'Dengar & Ulangi', 'Dengar & Ulangi'),
  findObject('find-object', 'Cari Objek', 'Cari Objek'),
  missingLetter('missing-letter', 'Huruf Hilang', 'Huruf Hilang'),
  matching('matching', 'Permainan Cocokkan', 'Cocokkan'),
  listening('listening', 'Dengar & Pilih', 'Dengar & Pilih'),
  fillBlank('fill-blank', 'Isi Huruf Kosong', 'Isi Huruf');

  const GameType(this.code, this.title, this.mapLabel);

  /// Kode stabil yang disimpan di database (jangan diubah).
  final String code;

  /// Judul pada header halaman permainan.
  final String title;

  /// Label singkat pada peta petualangan.
  final String mapLabel;

  /// Permainan berbasis suara (voice recognition) — dipakai untuk metrik
  /// STT Accuracy Rate pada pengujian lapangan.
  bool get usesVoice => this == GameType.listenRepeat;

  static GameType fromCode(String code) => GameType.values.firstWhere((g) => g.code == code, orElse: () => GameType.listenRepeat);
}

/// Satu kelompok kecil kata (4 kata) yang dipelajari bersama.
class LearningUnit {
  const LearningUnit({required this.materi, required this.index, required this.items});

  final Materi materi;
  final int index;
  final List<VocabItem> items;

  List<GameType> get games => [
    GameType.listenRepeat,
    GameType.findObject,
    GameType.missingLetter,
    GameType.matching,
    // Aktivitas tambahan bergantian agar peta tidak monoton. Materi huruf
    // selalu memakai Dengar & Pilih karena Isi Huruf Kosong membutuhkan kata.
    if (materi == Materi.huruf || index.isEven) GameType.listening else GameType.fillBlank,
  ];
}

/// Satu titik (node) pada peta petualangan = satu permainan untuk satu unit.
class LearningNode {
  const LearningNode({required this.materi, required this.index, required this.unit, required this.game});

  final Materi materi;

  /// Urutan global dalam materi (0-based), dipakai sebagai kunci progres.
  final int index;
  final LearningUnit unit;
  final GameType game;

  bool get isFirstInUnit => unit.games.first == game;

  /// Seed deterministik agar susunan soal sama setiap kali node dibuka.
  int get seed => materi.index * 10007 + index * 131 + 17;
}

class Curriculum {
  Curriculum._();

  static const int unitSize = 4;
  static const int maxStarsPerNode = 3;

  static final Map<Materi, List<LearningUnit>> _units = {for (final m in Materi.values) m: _chunk(m)};

  static final Map<Materi, List<LearningNode>> _nodes = {for (final m in Materi.values) m: _buildNodes(m)};

  static List<LearningUnit> unitsOf(Materi materi) => _units[materi]!;
  static List<LearningNode> nodesOf(Materi materi) => _nodes[materi]!;

  static int get totalNodes => Materi.values.fold(0, (sum, m) => sum + nodesOf(m).length);
  static int get maxStars => totalNodes * maxStarsPerNode;

  /// Membagi kosakata ke unit berukuran seimbang (maksimal [unitSize]) agar
  /// tidak ada unit yang terlalu kecil untuk permainan Cocokkan.
  static List<LearningUnit> _chunk(Materi materi) {
    final items = materi.items;
    final unitCount = (items.length / unitSize).ceil();
    final base = items.length ~/ unitCount;
    final extra = items.length % unitCount;
    final units = <LearningUnit>[];
    var start = 0;
    for (var i = 0; i < unitCount; i++) {
      final size = base + (i < extra ? 1 : 0);
      units.add(LearningUnit(materi: materi, index: i, items: items.sublist(start, start + size)));
      start += size;
    }
    return units;
  }

  static List<LearningNode> _buildNodes(Materi materi) {
    final nodes = <LearningNode>[];
    for (final unit in unitsOf(materi)) {
      for (final game in unit.games) {
        nodes.add(LearningNode(materi: materi, index: nodes.length, unit: unit, game: game));
      }
    }
    return nodes;
  }

  /// Bintang 1–3 dari rasio jawaban benar pada percobaan pertama.
  static int starsFor({required int firstTryCorrect, required int total}) {
    if (total <= 0) return 1;
    final ratio = firstTryCorrect / total;
    if (ratio >= 0.999) return 3;
    if (ratio >= 0.5) return 2;
    return 1;
  }

  /// Semua item bergambar (dipakai sebagai pengecoh lintas materi).
  static List<VocabItem> get pictureItems => [...vocabDuaSuku, ...vocabTigaSuku];
}

/// Tingkatan hadiah pada halaman Pencapaian (proposal Gambar 3.29).
enum RewardTier {
  perunggu('Perunggu', 10),
  perak('Perak', 50),
  emas('Emas', 150),
  berlian('Berlian', 300);

  const RewardTier(this.title, this.minStars);

  final String title;
  final int minStars;

  bool isEarned(int stars) => stars >= minStars;

  /// Persentase kemajuan menuju tingkatan ini (0–100).
  int progressPercent(int stars) => ((stars / minStars).clamp(0.0, 1.0) * 100).round();

  static int earnedCount(int stars) => RewardTier.values.where((t) => t.isEarned(stars)).length;
}
