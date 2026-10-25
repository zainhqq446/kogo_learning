import 'dart:math';
import 'kogo_voice_style.dart';
import 'voice_message.dart';
import 'voice_message_context.dart';

/// Selector & Planner pesan suara kontekstual dengan pemahaman progres, streak, attempt,
/// micro-reactions spontan, dan rotasi tanpa pengulangan dalam 3 event terakhir.
class VoiceMessageSelector {
  VoiceMessageSelector._internal();
  static final VoiceMessageSelector instance = VoiceMessageSelector._internal();

  final Random _random = Random();
  final List<String> _recentTexts = [];


  // ---------------------------------------------------------
  // MICRO-REACTIONS (Spontan, natural untuk anak usia 5–6 tahun)
  // ---------------------------------------------------------
  final List<String> correctMicroReactions = const [
    'Wah!',
    'Yeay!',
    'Wow!',
    'Keren!',
    'Bagus!',
  ];

  final List<String> streakMicroReactions = const [
    'Wow!',
    'Luar biasa!',
    'Wah hebat!',
    'Yeay!',
  ];

  final List<String> completionMicroReactions = const [
    'Yeay!',
    'Hore!',
    'Wah!',
  ];

  final List<String> retryMicroReactions = const [
    'Hmm...',
    'Yuk...',
    'Tarik napas dulu...',
    'Enggak apa-apa...',
  ];

  // ---------------------------------------------------------
  // KUMPULAN PESAN BERVARIASI (8–12 Variasi per Kategori)
  // ---------------------------------------------------------

  // 1. INTRO / START
  final List<String> introOptions = const [
    'Yuk, kita mulai petualangan seru ini!',
    'Siap? Ayo kita belajar bersama-sama!',
    'Halo teman kecil! Yuk, kita mulai ya!',
    'Hari ini kita akan bermain sambil belajar. Siap?',
    'Ayo buka telinga dan perhatikan baik-baik!',
    'Wah, ada permainan baru nih. Yuk kita coba!',
    'Bersiap ya, Kogo siap menemani kamu!',
    'Yuk, dengarkan dulu sebelum menjawab.',
    'Ayo mulai, kamu pasti hebat hari ini!',
    'Siap untuk tantangan hari ini? Yuk gas!',
  ];

  // 2. SOAL / QUESTION PROMPTS
  final List<String> questionPrompts = const [
    'Siap? Coba perhatikan yang ini.',
    'Sekarang giliran kamu, ya!',
    'Ayo perhatikan gambarnya baik-baik.',
    'Nah, coba dengarkan baik-baik ya.',
    'Menurutmu, apa ya jawabannya?',
    'Ayo, kamu pasti bisa menebak yang ini!',
    'Yuk, coba yang ini bersama Kogo.',
    'Perhatikan kata ini baik-baik ya.',
    'Sekarang coba lihat yang satu ini.',
    'Ayo tunjukkan kehebatanmu di soal ini!',
  ];

  // 3. CORRECT (Genuinely excited, bright, warm)
  final List<String> correctOptions = const [
    'Wah, benar!',
    'Yeay! Kamu bisa!',
    'Bagus banget!',
    'Wah, hebat! Jawabanmu tepat!',
    'Wow... benar sekali!',
    'Pintar! Kamu teliti sekali!',
    'Mantap! Jawabanmu pas!',
    'Keren sekali, teruskan ya!',
    'Aku suka semangatmu, tepat sekali!',
    'Luar biasa! Benar tanpa ragu!',
    'Hebat! Kamu makin jago!',
    'Tepat sekali! Kogo bangga sama kamu!',
  ];

  // 4. ALMOST CORRECT (Optimistic, encouraging, calm, playful)
  final List<String> almostOptions = const [
    'Hampir! Kamu sudah dekat banget.',
    'Sedikit lagi! Coba sekali lagi ya.',
    'Bagus, suaramu sudah hampir pas!',
    'Wah, hampir tepat! Yuk coba lagi pelan-pelan.',
    'Sudah dekat sekali! Jangan menyerah ya.',
    'Sedikit lagi kena! Ayo ulangi dengan jelas.',
    'Hebat kok, tinggal sedikit lagi yang pas!',
    'Kogo dengar hampir cocok! Sekali lagi yaa.',
    'Wah nyaris sempurna! Ayo coba lagi!',
  ];

  // 5. INCORRECT / RETRY (Gentle, reassuring, never disappointed)
  final List<String> wrongOptions = const [
    'Enggak apa-apa, kita coba pelan-pelan ya.',
    'Tenang saja, ayo kita ulangi bersama-sama.',
    'Yuk coba lagi, Kogo yakin kamu pasti bisa.',
    'Tarik napas dulu... lalu coba lagi ya.',
    'Belum pas, tapi enggak apa-apa, coba yang lain!',
    'Tidak masalah, belajar memang butuh latihan.',
    'Ayo pelan-pelan saja, perhatikan lagi ya.',
    'Jangan terburu-buru, ayo coba sekali lagi.',
  ];

  // 6. ATTEMPT 1, 2, 3 (Attempt-aware)
  final List<String> attempt1Options = const [
    'Ayo coba, kamu pasti bisa!',
    'Yuk, coba tebak sekarang.',
    'Silakan dicoba yaa.',
  ];

  final List<String> attempt2Options = const [
    'Yuk, coba lagi! Kamu makin dekat.',
    'Sekali lagi ya, pelan-pelan saja.',
    'Ayo coba lagi, dengarkan baik-baik.',
  ];

  final List<String> attempt3Options = const [
    'Enggak apa-apa. Kita coba pelan-pelan, ya.',
    'Tenang saja, kakak bantu dari sini ya.',
    'Bagus sudah berusaha, yuk coba lagi!',
  ];

  // 7. NO RECOGNITION (Patient, calm, helpful)
  final List<String> noRecognitionOptions = const [
    'Belum terdengar. Yuk, coba dekatkan suaramu!',
    'Suaramu belum terdengar jelas. Coba tekan mikrofon lagi, ya!',
    'Suaranya masih malu-malu nih. Ayo bicara lagi yaa!',
    'Yuk coba lagi, tekan mikrofon dan katakan dengan jelas!',
    'Kogo belum dengar suaramu. Coba sekali lagi ya!',
    'Bicaralah lebih dekat ke mikrofon, Kogo siap mendengar!',
  ];

  // 8. STREAK >= 3 (Energetic, celebratory, spontaneous)
  final List<String> streakOptions = const [
    'Wow! Kamu lagi hebat banget hari ini!',
    'Luar biasa! Sudah berkali-kali benar berturut-turut!',
    'Yeay! Tiga kali benar berturut-turut!',
    'Hebat! Jawabanmu benar terus nih!',
    'Kamu makin pintar dan jago!',
    'Wah, rekor baru! Semuanya benar!',
    'Luar biasa! Kogo kagum sekali!',
    'Keren banget! Teruskan sampai selesai ya!',
  ];

  // 9. TRANSITIONS (Warm, conversational, motivating)
  final List<String> transitionOptions = const [
    'Yuk lanjut ke soal berikutnya!',
    'Ayo kita coba yang berikutnya.',
    'Siap untuk soal berikut?',
    'Masih semangat? Ayo lanjut!',
    'Bagus! Kita meluncur ke pertanyaan berikutnya.',
    'Mantap! Ayo lihat soal yang ini.',
    'Wah, seru ya! Yuk teruskan.',
    'Ayo, lanjut lagi!',
  ];

  // 10. PROGRESS-AWARE PROMPTS
  final List<String> progressMidOptions = const [
    'Wah, kamu sudah melangkah jauh!',
    'Hebat! Setengah jalan sudah kamu lewati!',
    'Masih semangat kan? Keren sekali!',
  ];

  final List<String> progressNearEndOptions = const [
    'Wah, tinggal sedikit lagi selesai!',
    'Sebentar lagi selesai, ayo semangat!',
    'Tinggal beberapa soal lagi, kamu hebat!',
  ];

  final List<String> progressLastQuestionOptions = const [
    'Ini soal yang terakhir ya! Yuk selesaikan dengan ceria!',
    'Satu soal lagi! Ayo tunjukkan yang terbaik!',
    'Ini yang terakhir untuk sesi ini, siap?',
  ];

  // 11. COMPLETION (Proud, happy, warm)
  final List<String> completionOptions = const [
    'Yeay! Kamu sudah selesai! Hebat sekali!',
    'Kamu berhasil menyelesaikan semua soal dengan luar biasa!',
    'Keren! Terima kasih sudah belajar bersama Kogo hari ini!',
    'Wah, Kogo bangga sekali sama kamu! Semua selesai!',
    'Hari ini kamu luar biasa pintar dan ceria!',
    'Hore! Selesai! Kamu pantas dapat bintang emas!',
    'Hebat sekali! Sampai jumpa di latihan berikutnya ya!',
    'Petualangan selesai! Kamu juara hari ini!',
  ];

  // ---------------------------------------------------------
  // GAME INTROS (Activity-specific)
  // ---------------------------------------------------------
  final Map<String, List<String>> gameIntros = const {
    'find_object': [
      'Yuk, kita cari sesuatu! Dengar baik-baik ya.',
      'Ayo kita cari gambar yang tepat bersama-sama!',
      'Wah, ada banyak gambar! Yuk temukan benda yang dicari!',
      'Dengar baik-baik ya, menurutmu gambar mana yang cocok?',
    ],
    'matching': [
      'Yuk, kita cari pasangannya! Cari gambar yang cocok ya.',
      'Ayo pasangkan bagian-bagian kata ini sampai pas!',
      'Hmm... yang mana ya pasangannya? Yuk kita cari bersama!',
      'Ayo pasangkan gambar dan kata dengan tepat!',
    ],
    'listen_carefully': [
      'Sekarang waktunya dengar baik-baik. Dengarkan suaranya ya!',
      'Yuk, dengarkan suaranya dengan teliti. Siap?',
      'Buka telingamu lebar-lebar... dengarkan suaranya ya!',
      'Sekarang giliran telingamu yang beraksi. Dengarkan ya!',
    ],
    'missing_letter': [
      'Wah, ada huruf yang hilang! Ayo bantu lengkapi kata ini ya!',
      'Ayo tebak huruf apa yang hilang dari kata ini!',
      'Hurufnya bersembunyi nih! Yuk kita cari huruf yang hilang!',
      'Bantu Kogo melengkapi kata ini yuk, kira-kira huruf apa ya?',
    ],
    'listen_repeat': [
      'Yuk, kita mulai! Perhatikan gambarnya dan ikuti ucapan Kogo ya!',
      'Dengarkan dulu dengan santai, lalu tirukan ya!',
      'Sekarang waktunya kita berlatih bicara dengan riang!',
    ],
    'word_assembly': [
      'Wah, huruf-hurufnya tersebar! Ayo kita susun menjadi kata yang utuh!',
      'Yuk susun kepingan huruf ini sampai membentuk kata yang benar!',
      'Sentuh huruf-hurufnya secara berurutan untuk menyusun katanya ya!',
    ],
  };

  // ---------------------------------------------------------
  // GAME EXPLANATIONS / ENCOURAGEMENTS
  // ---------------------------------------------------------
  final Map<String, List<String>> gameEncouragements = const {
    'find_object': [
      'Menurutmu yang mana? Perhatikan baik-baik ya.',
      'Coba lihat sekeliling gambarnya, pelan-pelan saja.',
      'Ayo cari benda yang sesuai dengan kata tadi.',
    ],
    'word_assembly': [
      'Perhatikan huruf pertama dan huruf berikutnya ya.',
      'Ayo susun satu per satu, kamu pasti bisa!',
    ],
    'matching': [
      'Hmm... yang mana ya? Coba perhatikan baik-baik.',
      'Cari yang gambarnya cocok yaa.',
      'Ayo pasangkan, pelan-pelan saja.',
    ],
    'listen_carefully': [
      'Nah... kamu dengar apa tadi? Coba ingat-ingat ya.',
      'Dengarkan sekali lagi jika perlu, lalu pilih jawabannya.',
      'Kira-kira suara apa itu tadi ya?',
    ],
    'missing_letter': [
      'Coba baca pelan-pelan, huruf apa ya yang belum ada?',
      'Perhatikan susunan hurufnya, kamu pasti tahu!',
      'Ayo pilih huruf yang cocok untuk melengkapinya.',
    ],
    'listen_repeat': [
      'Katakan dengan santai dan jelas yaa.',
      'Ayo suarakan dengan gembira!',
      'Tarik napas, lalu ucapkan kata ini.',
    ],
  };

  // ---------------------------------------------------------
  // SELECTION LOGIC
  // ---------------------------------------------------------

  /// Memilih pesan evaluasi berdasarkan VoiceMessageContext
  VoiceMessage selectEvaluationMessage(VoiceMessageContext context) {
    if (context.isCompleted) {
      return selectCompletionMessage(context);
    }

    // 1. STREAK CELEBRATION (streak >= 3 dan benar)
    if (context.isCorrect == true && context.streak >= 3) {
      final text = _selectNonRepeating(streakOptions);
      final micro = _maybePickMicro(streakMicroReactions, probability: 0.7);
      return VoiceMessage(
        text: text,
        microReaction: micro,
        emotion: VoiceEmotion.celebratory,
        voiceStyle: KogoVoiceStyle.celebratory,
        customInstruction: 'Express high excitement, celebrate consecutive wins, warm and energetic tone.',
      );
    }

    // 2. JAWABAN BENAR (CORRECT)
    if (context.isCorrect == true) {
      final text = _selectNonRepeating(correctOptions);
      final micro = _maybePickMicro(correctMicroReactions, probability: 0.6);
      return VoiceMessage(
        text: text,
        microReaction: micro,
        emotion: VoiceEmotion.excited,
        voiceStyle: KogoVoiceStyle.childFriendly,
        customInstruction: 'Sound genuinely excited and warm, acknowledging the child’s success with joy.',
      );
    }

    // 3. SUARA TIDAK TERDENGAR (EMPTY RECOGNITION)
    if (context.isEmptyRecognition) {
      final text = _selectNonRepeating(noRecognitionOptions);
      return VoiceMessage(
        text: text,
        emotion: VoiceEmotion.patient,
        voiceStyle: KogoVoiceStyle.gentleGuide,
        customInstruction: 'Sound patient, gentle, and helpful. Encourage the child to speak into the microphone without pressure.',
      );
    }

    // 4. JAWABAN HAMPIR BENAR (ALMOST CORRECT)
    if (context.isCorrect == false && context.similarity >= 65.0) {
      final text = _selectNonRepeating(almostOptions);
      return VoiceMessage(
        text: text,
        emotion: VoiceEmotion.encouraging,
        voiceStyle: KogoVoiceStyle.childFriendly,
        customInstruction: 'Sound optimistic, encouraging, and playful. Emphasize that the child is very close to getting it right.',
      );
    }

    // 5. ATTEMPT-AWARE RETRY (Percobaan ke-2 atau ke-3)
    if (context.isCorrect == false) {
      List<String> pool;
      if (context.attemptNumber == 2) {
        pool = attempt2Options;
      } else if (context.attemptNumber >= 3) {
        pool = attempt3Options;
      } else {
        pool = wrongOptions;
      }

      final text = _selectNonRepeating(pool);
      final micro = _maybePickMicro(retryMicroReactions, probability: 0.4);
      return VoiceMessage(
        text: text,
        microReaction: micro,
        emotion: VoiceEmotion.gentle,
        voiceStyle: KogoVoiceStyle.gentleGuide,
        customInstruction: 'Be gentle and reassuring, never disappointed or stern. Help the child feel safe to try again.',
      );
    }

    // Default fallback
    final text = _selectNonRepeating(questionPrompts);
    return VoiceMessage(text: text, emotion: VoiceEmotion.curious);
  }

  /// Memilih intro permainan ramah anak berdasarkan tipe aktivitas
  VoiceMessage selectGameIntro(String gameType) {
    final list = gameIntros[gameType] ?? introOptions;
    final text = _selectNonRepeating(list);
    return VoiceMessage(
      text: text,
      emotion: VoiceEmotion.playful,
      voiceStyle: KogoVoiceStyle.childFriendly,
      customInstruction: 'Sound cheerful, playful, and inviting. Welcome the young child to the game.',
    );
  }

  /// Memilih dorongan semangat / bantuan pemikiran selama permainan
  VoiceMessage selectGameEncouragement(String gameType) {
    final list = gameEncouragements[gameType] ?? questionPrompts;
    final text = _selectNonRepeating(list);
    return VoiceMessage(
      text: text,
      emotion: VoiceEmotion.curious,
      voiceStyle: KogoVoiceStyle.childFriendly,
      customInstruction: 'Sound curious and supportive, prompting the child to think calmly.',
    );
  }

  /// Memilih transisi ke soal berikutnya, mempertimbangkan progres
  VoiceMessage selectTransition(VoiceMessageContext context) {
    String text;
    if (context.isLastQuestion) {
      text = _selectNonRepeating(progressLastQuestionOptions);
    } else if (context.isNearEnd) {
      text = _selectNonRepeating(progressNearEndOptions);
    } else if (context.progress >= 0.5 && _random.nextBool()) {
      text = _selectNonRepeating(progressMidOptions);
    } else {
      text = _selectNonRepeating(transitionOptions);
    }

    return VoiceMessage(
      text: text,
      emotion: VoiceEmotion.warm,
      voiceStyle: KogoVoiceStyle.childFriendly,
      customInstruction: 'Sound motivating and smooth, guiding the child to the next challenge without rushing.',
    );
  }

  /// Memilih selebrasi selesai aktivitas
  VoiceMessage selectCompletionMessage(VoiceMessageContext context) {
    final text = _selectNonRepeating(completionOptions);
    final micro = _maybePickMicro(completionMicroReactions, probability: 0.8);
    return VoiceMessage(
      text: text,
      microReaction: micro,
      emotion: VoiceEmotion.celebratory,
      voiceStyle: KogoVoiceStyle.celebratory,
      customInstruction: 'Sound immensely proud, happy, and warm. Celebrate the child’s achievement like a caring companion.',
    );
  }

  /// Memilih prompt ajakan pengucapan kata target
  VoiceMessage selectSpeechPrompt(String targetWord, {int attempt = 1}) {
    final word = targetWord.trim();
    String template;
    if (attempt > 1) {
      template = 'Yuk coba lagi, ucapkan {word}.';
    } else {
      final templates = [
        'Sekarang, coba ucapkan {word}.',
        'Yuk, bilang {word}!',
        'Ayo ikuti Kakak, katakan {word}.',
        'Sekarang giliranmu, coba katakan {word}.',
        'Coba katakan {word}, kamu pasti bisa!',
      ];
      template = _selectNonRepeating(templates);
    }

    final populated = template.replaceAll('{word}', word);
    return VoiceMessage(
      text: populated,
      emotion: VoiceEmotion.playful,
      voiceStyle: KogoVoiceStyle.childFriendly,
      customInstruction: 'Speak clearly with gentle emphasis on the target word "$word", inviting the child warmly.',
      isStatic: false,
    );
  }

  // ---------------------------------------------------------
  // HELPER ROTASI & HISTORY (Mencegah repetisi dalam 3 event)
  // ---------------------------------------------------------
  String _selectNonRepeating(List<String> options) {
    if (options.isEmpty) return '';
    if (options.length == 1) {
      _recordHistory(options.first);
      return options.first;
    }

    // 1. Prioritaskan opsi yang tidak ada di 3 event terakhir
    var candidates = options.where((item) => !_recentTexts.contains(item)).toList();
    if (candidates.isEmpty) {
      // 2. Jika seluruh opsi sudah ada di 3 event terakhir, hindari minimal yang paling terakhir
      final last = _recentTexts.isNotEmpty ? _recentTexts.last : null;
      candidates = options.where((item) => item != last).toList();
    }

    final list = candidates.isNotEmpty ? candidates : options;
    final selected = list[_random.nextInt(list.length)];
    _recordHistory(selected);
    return selected;
  }

  void _recordHistory(String text) {
    _recentTexts.add(text);
    if (_recentTexts.length > 3) {
      _recentTexts.removeAt(0);
    }
  }

  String? _maybePickMicro(List<String> reactions, {double probability = 0.5}) {
    if (reactions.isEmpty || _random.nextDouble() > probability) {
      return null;
    }
    return reactions[_random.nextInt(reactions.length)];
  }

  void resetHistory() {
    _recentTexts.clear();
  }
}

/// Alias typedef untuk memenuhi spesifikasi VoiceMessagePlanner
typedef VoiceMessagePlanner = VoiceMessageSelector;
