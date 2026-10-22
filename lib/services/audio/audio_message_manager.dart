import 'dart:math';

/// Tipe kategori pesan suara dalam Kogo Voice Learning.
enum AudioCategory {
  instruction,
  speechInvitation,
  correct,
  almostCorrect,
  incorrect,
  noRecognition,
  streak,
  completion,
  word,
}

/// Konteks pembelajaran anak untuk menentukan respon suara yang relevan.
class AudioContextInfo {
  final String targetWord;
  final int attemptNumber;
  final bool? isCorrect;
  final double similarityPercent;
  final int streak;
  final bool isCompleted;
  final bool isEmptyRecognition;

  const AudioContextInfo({
    required this.targetWord,
    this.attemptNumber = 1,
    this.isCorrect,
    this.similarityPercent = 0.0,
    this.streak = 0,
    this.isCompleted = false,
    this.isEmptyRecognition = false,
  });
}

/// Model untuk item audio yang siap diputar.
class AudioMessageItem {
  final AudioCategory category;
  final String assetPath;
  final String textRepresentation;

  const AudioMessageItem({
    required this.category,
    required this.assetPath,
    required this.textRepresentation,
  });
}

/// Manager pemilihan audio rekaman manusia (Human Audio) secara kontekstual,
/// ramah anak, dan bebas dari pengulangan berturut-turut.
class AudioMessageManager {
  AudioMessageManager._internal();
  static final AudioMessageManager instance = AudioMessageManager._internal();

  final Random _random = Random();
  final List<String> _recentAssetPaths = [];

  String? get lastAssetPath => _recentAssetPaths.isNotEmpty ? _recentAssetPaths.last : null;

  // 1. INSTRUCTION
  final List<AudioMessageItem> instructionAudios = const [
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/instructions/instruction_01.mp3',
      textRepresentation: 'Yuk, dengarkan baik-baik ya!',
    ),
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/instructions/instruction_02.mp3',
      textRepresentation: 'Ayo kita coba bersama!',
    ),
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/instructions/instruction_03.mp3',
      textRepresentation: 'Sekarang giliran kamu yaa!',
    ),
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/instructions/instruction_04.mp3',
      textRepresentation: 'Dengarkan dulu, siap? Kita mulai!',
    ),
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/instructions/instruction_05.mp3',
      textRepresentation: 'Ayo kita belajar bersama dengan riang!',
    ),
  ];

  // 2. INVITATIONS (Prefix sebelum kata target)
  final List<AudioMessageItem> invitationAudios = const [
    AudioMessageItem(
      category: AudioCategory.speechInvitation,
      assetPath: 'assets/audio/invitations/invite_01.mp3',
      textRepresentation: 'Sekarang, coba ucapkan',
    ),
    AudioMessageItem(
      category: AudioCategory.speechInvitation,
      assetPath: 'assets/audio/invitations/invite_02.mp3',
      textRepresentation: 'Yuk, bilang kata ini',
    ),
    AudioMessageItem(
      category: AudioCategory.speechInvitation,
      assetPath: 'assets/audio/invitations/invite_03.mp3',
      textRepresentation: 'Ayo ikuti Kakak, katakan',
    ),
    AudioMessageItem(
      category: AudioCategory.speechInvitation,
      assetPath: 'assets/audio/invitations/invite_04.mp3',
      textRepresentation: 'Sekarang giliranmu, coba katakan',
    ),
    AudioMessageItem(
      category: AudioCategory.speechInvitation,
      assetPath: 'assets/audio/invitations/invite_05.mp3',
      textRepresentation: 'Ayo, kamu pasti bisa bilang',
    ),
  ];

  // 3. CORRECT PRAISE
  final List<AudioMessageItem> correctAudios = const [
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_01.mp3',
      textRepresentation: 'Hebat!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_02.mp3',
      textRepresentation: 'Wah, benar!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_03.mp3',
      textRepresentation: 'Bagus sekali!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_04.mp3',
      textRepresentation: 'Keren!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_05.mp3',
      textRepresentation: 'Yeay, kamu berhasil!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_06.mp3',
      textRepresentation: 'Pintar sekali!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_07.mp3',
      textRepresentation: 'Mantap, jawabanmu tepat!',
    ),
    AudioMessageItem(
      category: AudioCategory.correct,
      assetPath: 'assets/audio/correct/correct_08.mp3',
      textRepresentation: 'Luar biasa, kamu hebat!',
    ),
  ];

  // 4. ALMOST CORRECT
  final List<AudioMessageItem> almostCorrectAudios = const [
    AudioMessageItem(
      category: AudioCategory.almostCorrect,
      assetPath: 'assets/audio/almost_correct/almost_01.mp3',
      textRepresentation: 'Hampir benar! Coba lagi ya.',
    ),
    AudioMessageItem(
      category: AudioCategory.almostCorrect,
      assetPath: 'assets/audio/almost_correct/almost_02.mp3',
      textRepresentation: 'Sudah dekat! Ayo coba sekali lagi.',
    ),
    AudioMessageItem(
      category: AudioCategory.almostCorrect,
      assetPath: 'assets/audio/almost_correct/almost_03.mp3',
      textRepresentation: 'Bagus, sedikit lagi pasti pas!',
    ),
    AudioMessageItem(
      category: AudioCategory.almostCorrect,
      assetPath: 'assets/audio/almost_correct/almost_04.mp3',
      textRepresentation: 'Hampir berhasil! Coba pelan-pelan yaa.',
    ),
  ];

  // 5. INCORRECT / RETRY
  final List<AudioMessageItem> incorrectAudios = const [
    AudioMessageItem(
      category: AudioCategory.incorrect,
      assetPath: 'assets/audio/incorrect/retry_01.mp3',
      textRepresentation: 'Enggak apa-apa, yuk coba sekali lagi!',
    ),
    AudioMessageItem(
      category: AudioCategory.incorrect,
      assetPath: 'assets/audio/incorrect/retry_02.mp3',
      textRepresentation: 'Kita coba lagi yaa, kamu pasti bisa!',
    ),
    AudioMessageItem(
      category: AudioCategory.incorrect,
      assetPath: 'assets/audio/incorrect/retry_03.mp3',
      textRepresentation: 'Tenang saja, ayo kita ulangi bersama!',
    ),
    AudioMessageItem(
      category: AudioCategory.incorrect,
      assetPath: 'assets/audio/incorrect/retry_04.mp3',
      textRepresentation: 'Tarik napas dulu, lalu coba lagi yaa!',
    ),
  ];

  // 6. NO RECOGNITION
  final List<AudioMessageItem> noRecognitionAudios = const [
    AudioMessageItem(
      category: AudioCategory.noRecognition,
      assetPath: 'assets/audio/no_recognition/no_rec_01.mp3',
      textRepresentation: 'Suaramu belum terdengar jelas. Coba tekan mikrofon lagi ya!',
    ),
    AudioMessageItem(
      category: AudioCategory.noRecognition,
      assetPath: 'assets/audio/no_recognition/no_rec_02.mp3',
      textRepresentation: 'Belum terdengar nih. Yuk coba dekatkan suaramu!',
    ),
    AudioMessageItem(
      category: AudioCategory.noRecognition,
      assetPath: 'assets/audio/no_recognition/no_rec_03.mp3',
      textRepresentation: 'Suaranya masih malu-malu. Ayo katakan dengan jelas!',
    ),
  ];

  // 7. STREAK
  final List<AudioMessageItem> streakAudios = const [
    AudioMessageItem(
      category: AudioCategory.streak,
      assetPath: 'assets/audio/streak/streak_01.mp3',
      textRepresentation: 'Wah, hebat! Kamu keren sekali!',
    ),
    AudioMessageItem(
      category: AudioCategory.streak,
      assetPath: 'assets/audio/streak/streak_02.mp3',
      textRepresentation: 'Wow, kamu makin pintar!',
    ),
    AudioMessageItem(
      category: AudioCategory.streak,
      assetPath: 'assets/audio/streak/streak_03.mp3',
      textRepresentation: 'Luar biasa! Sudah berkali-kali benar!',
    ),
    AudioMessageItem(
      category: AudioCategory.streak,
      assetPath: 'assets/audio/streak/streak_04.mp3',
      textRepresentation: 'Yeay! Tiga kali benar berturut-turut!',
    ),
  ];

  // 8. COMPLETION
  final List<AudioMessageItem> completionAudios = const [
    AudioMessageItem(
      category: AudioCategory.completion,
      assetPath: 'assets/audio/completion/complete_01.mp3',
      textRepresentation: 'Yeay, kamu sudah selesai! Kamu hebat hari ini!',
    ),
    AudioMessageItem(
      category: AudioCategory.completion,
      assetPath: 'assets/audio/completion/complete_02.mp3',
      textRepresentation: 'Hebat sekali! Kamu berhasil menyelesaikan semua tantangan!',
    ),
    AudioMessageItem(
      category: AudioCategory.completion,
      assetPath: 'assets/audio/completion/complete_03.mp3',
      textRepresentation: 'Keren! Terima kasih sudah belajar bersama dengan ceria!',
    ),
  ];

  // 9. GAME INTROS & EXPLANATIONS
  final Map<String, List<AudioMessageItem>> gameIntroAudios = const {
    'find_object': [
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/find_object_intro_01.mp3',
        textRepresentation: 'Yuk, cari benda yang benar! Dengar baik-baik ya!',
      ),
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/find_object_intro_02.mp3',
        textRepresentation: 'Ayo kita cari gambar yang tepat bersama-sama!',
      ),
    ],
    'matching': [
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/matching_intro_01.mp3',
        textRepresentation: 'Yuk, kita cocokkan! Cari gambar yang cocok dengan pasangannya ya!',
      ),
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/matching_intro_02.mp3',
        textRepresentation: 'Ayo pasangkan bagian-bagian kata ini sampai pas!',
      ),
    ],
    'listen_carefully': [
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/listen_carefully_intro_01.mp3',
        textRepresentation: 'Sekarang dengarkan baik-baik ya, lalu pilih jawaban yang benar!',
      ),
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/listen_carefully_intro_02.mp3',
        textRepresentation: 'Yuk, dengarkan suaranya dengan teliti, siap?',
      ),
    ],
    'missing_letter': [
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/missing_letter_intro_01.mp3',
        textRepresentation: 'Wah, ada huruf yang hilang! Ayo bantu lengkapi kata ini ya!',
      ),
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/missing_letter_intro_02.mp3',
        textRepresentation: 'Ayo tebak huruf apa yang hilang dari kata ini!',
      ),
    ],
    'listen_repeat': [
      AudioMessageItem(
        category: AudioCategory.instruction,
        assetPath: 'assets/audio/games/listen_repeat_intro_01.mp3',
        textRepresentation: 'Yuk, dengarkan dulu! Lalu ikuti ucapan Kakak ya!',
      ),
    ],
  };

  // 10. GAME TRANSITIONS & ENCOURAGEMENTS
  final List<AudioMessageItem> transitionAudios = const [
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/games/transition_next_01.mp3',
      textRepresentation: 'Bagus! Sekarang kita lanjut ke soal berikutnya ya!',
    ),
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/games/transition_next_02.mp3',
      textRepresentation: 'Mantap! Ayo kita lanjutkan ke pertanyaan berikutnya!',
    ),
  ];

  final List<AudioMessageItem> encouragementAudios = const [
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/games/encouragement_look_01.mp3',
      textRepresentation: 'Ayo lihat baik-baik, menurutmu yang mana ya?',
    ),
    AudioMessageItem(
      category: AudioCategory.instruction,
      assetPath: 'assets/audio/games/encouragement_look_02.mp3',
      textRepresentation: 'Tenang saja, perhatikan gambarnya pelan-pelan ya!',
    ),
  ];

  // 11. DICTIONARY TARGET WORDS
  final Map<String, String> wordAssetPaths = const {
    'a': 'assets/audio/words/a.mp3',
    'b': 'assets/audio/words/b.mp3',
    'c': 'assets/audio/words/c.mp3',
    'd': 'assets/audio/words/d.mp3',
    'e': 'assets/audio/words/e.mp3',
    'apel': 'assets/audio/words/apel.mp3',
    'bola': 'assets/audio/words/bola.mp3',
    'buku': 'assets/audio/words/buku.mp3',
    'meja': 'assets/audio/words/meja.mp3',
    'sapi': 'assets/audio/words/sapi.mp3',
    'kaki': 'assets/audio/words/kaki.mp3',
    'sepatu': 'assets/audio/words/sepatu.mp3',
    'kereta': 'assets/audio/words/kereta.mp3',
    'kelinci': 'assets/audio/words/kelinci.mp3',
    'kamera': 'assets/audio/words/kamera.mp3',
    'helikopter': 'assets/audio/words/helikopter.mp3',
    'matahari': 'assets/audio/words/matahari.mp3',
    'laboratorium': 'assets/audio/words/laboratorium.mp3',
  };

  /// Memilih item audio berdasarkan konteks hasil belajar anak.
  AudioMessageItem selectFeedbackAudio(AudioContextInfo context) {
    if (context.isCompleted) {
      return _selectRandomNonRepeating(completionAudios);
    }

    if (context.isCorrect == true) {
      if (context.streak >= 3) {
        return _selectRandomNonRepeating(streakAudios);
      }
      return _selectRandomNonRepeating(correctAudios);
    }

    if (context.isEmptyRecognition) {
      return _selectRandomNonRepeating(noRecognitionAudios);
    }

    if (context.isCorrect == false) {
      if (context.similarityPercent >= 65.0) {
        return _selectRandomNonRepeating(almostCorrectAudios);
      }
      return _selectRandomNonRepeating(incorrectAudios);
    }

    return _selectRandomNonRepeating(instructionAudios);
  }

  /// Memilih ajakan berbicara (invitation prefix)
  AudioMessageItem selectInvitationAudio() {
    return _selectRandomNonRepeating(invitationAudios);
  }

  /// Memilih instruksi awal
  AudioMessageItem selectInstructionAudio() {
    return _selectRandomNonRepeating(instructionAudios);
  }

  /// Memilih audio selebrasi selesai
  AudioMessageItem selectCompletionAudio() {
    return _selectRandomNonRepeating(completionAudios);
  }

  /// Mengambil path audio untuk kata target tertentu jika tersedia di rekaman
  String? getWordAssetPath(String word) {
    final clean = word.trim().toLowerCase();
    return wordAssetPaths[clean];
  }

  AudioMessageItem _selectRandomNonRepeating(List<AudioMessageItem> options) {
    if (options.isEmpty) {
      throw StateError('Audio list is empty');
    }
    if (options.length == 1) {
      _recordHistory(options.first.assetPath);
      return options.first;
    }

    // Hindari pengulangan message yang sama dalam 3 event terakhir jika masih tersedia alternatif
    var candidates = options.where((item) => !_recentAssetPaths.contains(item.assetPath)).toList();
    if (candidates.isEmpty) {
      // Jika semua sudah ada di 3 event terakhir, hindari minimal yang paling terakhir (immediate repetition)
      final last = _recentAssetPaths.isNotEmpty ? _recentAssetPaths.last : null;
      candidates = options.where((item) => item.assetPath != last).toList();
    }
    final list = candidates.isNotEmpty ? candidates : options;
    final selected = list[_random.nextInt(list.length)];
    _recordHistory(selected.assetPath);
    return selected;
  }

  void _recordHistory(String assetPath) {
    _recentAssetPaths.add(assetPath);
    if (_recentAssetPaths.length > 3) {
      _recentAssetPaths.removeAt(0);
    }
  }

  /// Memilih intro ramah anak khusus jenis permainan
  AudioMessageItem selectGameIntro(String gameType) {
    final list = gameIntroAudios[gameType];
    if (list != null && list.isNotEmpty) {
      return _selectRandomNonRepeating(list);
    }
    return selectInstructionAudio();
  }

  /// Memilih transisi ke soal berikutnya
  AudioMessageItem selectTransitionAudio() {
    return _selectRandomNonRepeating(transitionAudios);
  }

  /// Memilih kalimat dorongan semangat selama bermain
  AudioMessageItem selectEncouragementAudio() {
    return _selectRandomNonRepeating(encouragementAudios);
  }

  void resetHistory() {
    _recentAssetPaths.clear();
  }
}

