import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../services/audio/kogo_voice_manager.dart';
import '../../../../services/audio/voice_cache.dart';
import '../../../../services/audio/voice_message.dart';
import '../../../../services/audio/voice_message_context.dart';
import '../../../../services/audio/voice_message_planner.dart';

enum PlaygroundCategory {
  intro('INTRO'),
  instruction('INSTRUCTION'),
  correct('CORRECT'),
  almostCorrect('ALMOST CORRECT'),
  incorrect('INCORRECT'),
  retry('RETRY'),
  streak('STREAK'),
  transition('TRANSITION'),
  completion('COMPLETION'),
  noRecognition('NO RECOGNITION');

  final String label;
  const PlaygroundCategory(this.label);
}

class KogoVoicePlaygroundPage extends StatefulWidget {
  const KogoVoicePlaygroundPage({super.key});

  @override
  State<KogoVoicePlaygroundPage> createState() => _KogoVoicePlaygroundPageState();
}

class _KogoVoicePlaygroundPageState extends State<KogoVoicePlaygroundPage> {
  final KogoVoiceManager _voiceManager = KogoVoiceManager.instance;
  final VoiceMessagePlanner _planner = VoiceMessagePlanner.instance;
  final VoiceCache _voiceCache = VoiceCache.instance;

  // Selected Category
  PlaygroundCategory _selectedCategory = PlaygroundCategory.correct;

  // Context Parameters
  String _selectedStage = 'Dua Suku Kata';
  final List<String> _stages = const [
    'Huruf',
    'Dua Suku Kata',
    'Tiga Suku Kata',
    'Banyak Suku Kata',
  ];

  String _selectedActivity = 'Listen & Repeat';
  final List<String> _activities = const [
    'Listen & Repeat',
    'Find Object',
    'Matching Object',
    'Listen Carefully',
  ];

  int _attempt = 1;
  final List<int> _attempts = const [1, 2, 3];

  double _similarity = 100.0;
  final List<double> _similarities = const [100.0, 90.0, 80.0, 50.0];

  bool _isCorrect = true;

  int _streak = 0;
  final List<int> _streaks = const [0, 1, 2, 3, 5];

  // Status & Telemetry
  String _currentResponseText = '-';
  String _playbackStatus = 'Idle'; // Idle / Playing / Completed / Error
  String _lastError = '';
  int? _latencyMs;
  bool _isCacheHit = false;
  String _currentEmotionTag = '-';
  String _currentAudioSource = 'ELEVEN_V4_TURBO'; // ELEVEN_V4_TURBO or LOCAL_HUMAN_AUDIO
  final String _voiceId = 'cgSgspJ2msm6clMCkdW9';
  final String _modelName = 'eleven_v4_turbo';
  final String _transportName = 'Text-to-Dialogue WebSocket';

  // Variations list
  List<String> _candidateVariations = [];
  String _lastPlayedText = '';

  // Sequence playback state
  bool _isSequencePlaying = false;
  int _sequenceCancelToken = 0;

  @override
  void initState() {
    super.initState();
    _refreshVariations();
  }

  @override
  void dispose() {
    _sequenceCancelToken++;
    _voiceManager.stop();
    super.dispose();
  }

  String _mapActivityToKey(String activity) {
    switch (activity) {
      case 'Find Object':
        return 'find_object';
      case 'Matching Object':
        return 'matching';
      case 'Listen Carefully':
        return 'listen_carefully';
      case 'Listen & Repeat':
      default:
        return 'listen_repeat';
    }
  }

  VoiceMessageContext _buildContext() {
    return VoiceMessageContext(
      targetWord: _selectedStage == 'Huruf'
          ? 'b'
          : _selectedStage == 'Tiga Suku Kata'
              ? 'sepatu'
              : _selectedStage == 'Banyak Suku Kata'
                  ? 'matahari'
                  : 'bola',
      attemptNumber: _attempt,
      isCorrect: _isCorrect,
      similarity: _similarity,
      streak: _streak,
      isCompleted: _selectedCategory == PlaygroundCategory.completion,
      isEmptyRecognition: _selectedCategory == PlaygroundCategory.noRecognition,
      questionIndex: 2,
      totalQuestions: 5,
      activity: _mapActivityToKey(_selectedActivity),
    );
  }

  VoiceMessage _planMessageForCategory(PlaygroundCategory category) {
    final ctx = _buildContext();
    final activityKey = _mapActivityToKey(_selectedActivity);

    switch (category) {
      case PlaygroundCategory.intro:
        return _planner.selectGameIntro(activityKey);

      case PlaygroundCategory.instruction:
        return _planner.selectSpeechPrompt(ctx.targetWord, attempt: _attempt);

      case PlaygroundCategory.correct:
        final correctCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          attemptNumber: _attempt,
          isCorrect: true,
          similarity: 100.0,
          streak: _streak,
          activity: activityKey,
        );
        return _planner.selectEvaluationMessage(correctCtx);

      case PlaygroundCategory.almostCorrect:
        final almostCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          attemptNumber: _attempt,
          isCorrect: false,
          similarity: _similarity >= 65.0 ? _similarity : 75.0,
          streak: 0,
          activity: activityKey,
        );
        return _planner.selectEvaluationMessage(almostCtx);

      case PlaygroundCategory.incorrect:
        final wrongCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          attemptNumber: 1,
          isCorrect: false,
          similarity: 30.0,
          streak: 0,
          activity: activityKey,
        );
        return _planner.selectEvaluationMessage(wrongCtx);

      case PlaygroundCategory.retry:
        final retryCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          attemptNumber: _attempt > 1 ? _attempt : 2,
          isCorrect: false,
          similarity: 40.0,
          streak: 0,
          activity: activityKey,
        );
        return _planner.selectEvaluationMessage(retryCtx);

      case PlaygroundCategory.streak:
        final streakCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          attemptNumber: 1,
          isCorrect: true,
          similarity: 100.0,
          streak: _streak >= 3 ? _streak : 3,
          activity: activityKey,
        );
        return _planner.selectEvaluationMessage(streakCtx);

      case PlaygroundCategory.transition:
        return _planner.selectTransition(ctx);

      case PlaygroundCategory.completion:
        final compCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          isCompleted: true,
          isCorrect: true,
          streak: _streak,
          questionIndex: 5,
          totalQuestions: 5,
          activity: activityKey,
        );
        return _planner.selectCompletionMessage(compCtx);

      case PlaygroundCategory.noRecognition:
        final emptyCtx = VoiceMessageContext(
          targetWord: ctx.targetWord,
          attemptNumber: _attempt,
          isEmptyRecognition: true,
          isCorrect: false,
          streak: 0,
          activity: activityKey,
        );
        return _planner.selectEvaluationMessage(emptyCtx);
    }
  }

  void _refreshVariations() {
    final category = _selectedCategory;
    final Set<String> candidates = {};
    for (int i = 0; i < 8; i++) {
      final msg = _planMessageForCategory(category);
      candidates.add(msg.fullSpokenText);
      if (candidates.length >= 4) break;
    }

    if (candidates.length < 3) {
      // Fallback pastikan selalu ada minimal 3 variasi eksplisit
      switch (category) {
        case PlaygroundCategory.intro:
          candidates.addAll(['Yuk, kita mulai!', 'Siap bermain?', 'Ayo belajar bersama!']);
          break;
        case PlaygroundCategory.instruction:
          candidates.addAll(['Dengarkan baik-baik, ya.', 'Coba perhatikan.', 'Yuk, ikuti Kogo.']);
          break;
        case PlaygroundCategory.correct:
          candidates.addAll(['Wah! Benar!', 'Yes! Kamu bisa!', 'Hebat!']);
          break;
        case PlaygroundCategory.almostCorrect:
          candidates.addAll(['Hmm... hampir.', 'Sedikit lagi.', 'Sudah dekat!']);
          break;
        case PlaygroundCategory.incorrect:
          candidates.addAll(['Enggak apa-apa.', 'Ayo coba lagi.', 'Belum tepat, yuk coba lagi.']);
          break;
        case PlaygroundCategory.retry:
          candidates.addAll(['Coba sekali lagi.', 'Yuk, ulangi.', 'Pelan-pelan, ya.']);
          break;
        case PlaygroundCategory.streak:
          candidates.addAll(['Wow, tiga kali!', 'Keren banget!', 'Kamu hebat!']);
          break;
        case PlaygroundCategory.transition:
          candidates.addAll(['Yuk lanjut.', 'Siap berikutnya?', 'Ayo terus!']);
          break;
        case PlaygroundCategory.completion:
          candidates.addAll(['Yeay! Selesai!', 'Kamu hebat hari ini!', 'Wah, kamu sudah selesai!']);
          break;
        case PlaygroundCategory.noRecognition:
          candidates.addAll(['Belum terdengar.', 'Coba bicara sedikit lebih jelas.', 'Yuk, coba lagi.']);
          break;
      }
    }

    setState(() {
      _candidateVariations = candidates.toList();
    });
  }

  Future<void> _playCategoryVoice(
    PlaygroundCategory category, {
    String? customText,
    bool cancelSequence = true,
  }) async {
    if (cancelSequence) {
      _sequenceCancelToken++;
      _isSequencePlaying = false;
    }

    // Hentikan suara sebelumnya
    await _voiceManager.stop();

    final msg = _planMessageForCategory(category);
    var textToPlay = customText ?? msg.fullSpokenText;

    // Mencegah dua response identik berturut-turut bila memungkinkan
    if (customText == null && textToPlay == _lastPlayedText && _candidateVariations.length > 1) {
      final alt = _candidateVariations.firstWhere(
        (v) => v != _lastPlayedText,
        orElse: () => textToPlay,
      );
      textToPlay = alt;
    }

    final cacheKey = 'tts_$textToPlay';
    final wasCached = _voiceCache.contains(cacheKey);

    final isPrerecorded = msg.assetPath != null && customText == null;
    final source = isPrerecorded ? 'LOCAL_HUMAN_AUDIO' : 'ELEVEN_V4_TURBO';

    setState(() {
      _currentResponseText = textToPlay;
      _currentEmotionTag = msg.emotion.name;
      _currentAudioSource = source;
      _playbackStatus = 'Playing';
      _lastError = '';
      _isCacheHit = wasCached;
    });

    final stopwatch = Stopwatch()..start();

    try {
      if (isPrerecorded) {
        await _voiceManager.provider.playHuman(msg.assetPath!);
      } else {
        await _voiceManager.provider.speakDynamicText(textToPlay);
      }
      stopwatch.stop();

      if (mounted) {
        setState(() {
          _playbackStatus = 'Completed';
          _latencyMs = stopwatch.elapsedMilliseconds;
          _lastPlayedText = textToPlay;
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _playbackStatus = 'Error';
          _lastError = 'Voice request failed. Error: $e';
          _latencyMs = stopwatch.elapsedMilliseconds;
        });
      }
    }
  }

  Future<void> _playSequence(List<PlaygroundCategory> sequence) async {
    _sequenceCancelToken++;
    final thisToken = _sequenceCancelToken;

    setState(() {
      _isSequencePlaying = true;
      _lastError = '';
    });

    for (final cat in sequence) {
      if (thisToken != _sequenceCancelToken || !mounted) break;

      setState(() {
        _selectedCategory = cat;
      });

      await _playCategoryVoice(cat, cancelSequence: false);

      // Jeda natural antar kalimat agar terdengar seperti percakapan nyata (350ms)
      await Future.delayed(const Duration(milliseconds: 350));
    }

    if (thisToken == _sequenceCancelToken && mounted) {
      setState(() {
        _isSequencePlaying = false;
        _playbackStatus = 'Completed Sequence';
      });
    }
  }

  Future<void> _handleStop() async {
    _sequenceCancelToken++;
    _isSequencePlaying = false;
    await _voiceManager.stop();
    if (mounted) {
      setState(() {
        _playbackStatus = 'Idle (Stopped)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Kogo Voice Playground',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded),
            tooltip: 'Bersihkan Cache Audio',
            onPressed: () {
              _voiceCache.clear();
              setState(() {
                _isCacheHit = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Audio cache berhasil dibersihkan!')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TELEMETRY & STATUS CARD
            _buildTelemetryCard(),

            const SizedBox(height: 16),

            // 2. CONTROLS BAR: PLAY, STOP, VARIATIONS
            _buildPrimaryControls(),

            const SizedBox(height: 16),

            // 3. CATEGORY SELECTOR
            _buildCategorySelector(),

            const SizedBox(height: 16),

            // 4. CANDIDATE VARIATIONS
            _buildVariationsSection(),

            const SizedBox(height: 16),

            // 5. CONTEXT TEST CONTROLS
            _buildContextTestControls(),

            const SizedBox(height: 16),

            // 6. SEQUENCE TESTS (Naturalness test)
            _buildSequenceTestSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard() {
    Color statusColor = const Color(0xFF64748B);
    if (_playbackStatus == 'Playing') {
      statusColor = const Color(0xFF2563EB);
    } else if (_playbackStatus.contains('Completed')) {
      statusColor = const Color(0xFF16A34A);
    } else if (_playbackStatus == 'Error') {
      statusColor = const Color(0xFFDC2626);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Status: $_playbackStatus',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (_isCacheHit)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Cache HIT',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (_latencyMs != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_latencyMs}ms',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
            const Divider(height: 18),
            _buildTelemetryRow('Current response', _currentResponseText, isHighlight: true),
            _buildTelemetryRow('Category', _selectedCategory.label),
            _buildTelemetryRow('Emotion / Delivery', _currentEmotionTag),
            _buildTelemetryRow('Source', _currentAudioSource),
            if (_currentAudioSource == 'LOCAL_HUMAN_AUDIO') ...[
              _buildTelemetryRow('Provider', 'Local Human Audio'),
            ] else ...[
              _buildTelemetryRow('Provider', 'ElevenLabs'),
              _buildTelemetryRow('Model', _modelName),
              _buildTelemetryRow('Voice', _voiceId),
              _buildTelemetryRow('Transport', _transportName),
            ],
            _buildTelemetryRow('Cache Items', '${_voiceCache.size} item'),
            if (_lastError.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  _lastError,
                  style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                color: isHighlight ? const Color(0xFF0F172A) : const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryControls() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            key: const Key('kogo_voice_playground_play_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text(
              'Play',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: () => _playCategoryVoice(_selectedCategory),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('kogo_voice_playground_stop_btn'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSequencePlaying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                  )
                : const Icon(Icons.stop_rounded, size: 20),
            label: Text(_isSequencePlaying ? 'Stop Seq' : 'Stop'),
            onPressed: _handleStop,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Generate Variations',
          onPressed: () {
            _refreshVariations();
          },
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pilihan Kategori Voice',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PlaygroundCategory.values.map((category) {
            final isSelected = category == _selectedCategory;
            return ChoiceChip(
              label: Text(category.label),
              selected: isSelected,
              selectedColor: const Color(0xFF2563EB),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedCategory = category;
                  });
                  _refreshVariations();
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVariationsSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Variasi Respons (Min 3)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.shuffle_rounded, size: 16),
                  label: const Text('Generate Variations', style: TextStyle(fontSize: 12)),
                  onPressed: _refreshVariations,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._candidateVariations.map((text) {
              final isCurrent = text == _currentResponseText;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCurrent ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent ? const Color(0xFF1E40AF) : const Color(0xFF334155),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.volume_up_rounded, size: 20),
                    color: const Color(0xFF2563EB),
                    tooltip: 'Putar variasi ini',
                    onPressed: () => _playCategoryVoice(_selectedCategory, customText: text),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildContextTestControls() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uji Parameter Konteks (Context Test)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 12),

            // Stage Dropdown
            Row(
              children: [
                const SizedBox(
                  width: 80,
                  child: Text('Stage:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedStage,
                    isDense: true,
                    isExpanded: true,
                    items: _stages.map((stage) {
                      return DropdownMenuItem(value: stage, child: Text(stage, style: const TextStyle(fontSize: 12)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedStage = val);
                      _refreshVariations();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Activity Dropdown
            Row(
              children: [
                const SizedBox(
                  width: 80,
                  child: Text('Activity:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedActivity,
                    isDense: true,
                    isExpanded: true,
                    items: _activities.map((act) {
                      return DropdownMenuItem(value: act, child: Text(act, style: const TextStyle(fontSize: 12)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedActivity = val);
                      _refreshVariations();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Attempt & Correct
            Row(
              children: [
                const SizedBox(
                  width: 80,
                  child: Text('Attempt:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ),
                ..._attempts.map((att) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$att'),
                      selected: _attempt == att,
                      onSelected: (sel) {
                        if (sel) setState(() => _attempt = att);
                        _refreshVariations();
                      },
                    ),
                  );
                }),
                const Spacer(),
                const Text('Correct:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                Switch(
                  value: _isCorrect,
                  onChanged: (val) {
                    setState(() => _isCorrect = val);
                    _refreshVariations();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Similarity & Streak
            Row(
              children: [
                const SizedBox(
                  width: 80,
                  child: Text('Similarity:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ),
                ..._similarities.map((sim) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text('${sim.toInt()}%'),
                      selected: _similarity == sim,
                      onSelected: (sel) {
                        if (sel) setState(() => _similarity = sim);
                        _refreshVariations();
                      },
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                const SizedBox(
                  width: 80,
                  child: Text('Streak:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ),
                ..._streaks.map((strk) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$strk'),
                      selected: _streak == strk,
                      onSelected: (sel) {
                        if (sel) setState(() => _streak = strk);
                        _refreshVariations();
                      },
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSequenceTestSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uji Naturalness & Rangkaian Suara (Sequence Test)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              key: const Key('kogo_voice_playground_seq_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.playlist_play_rounded),
              label: const Text('Play Sequence (Intro → Inst → Correct → Trans → Comp)'),
              onPressed: () {
                _playSequence([
                  PlaygroundCategory.intro,
                  PlaygroundCategory.instruction,
                  PlaygroundCategory.correct,
                  PlaygroundCategory.transition,
                  PlaygroundCategory.completion,
                ]);
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              key: const Key('kogo_voice_playground_err_seq_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.repeat_rounded),
              label: const Text('Play Error Sequence (Intro → Inst → Wrong → Retry → Almost → Correct)'),
              onPressed: () {
                _playSequence([
                  PlaygroundCategory.intro,
                  PlaygroundCategory.instruction,
                  PlaygroundCategory.incorrect,
                  PlaygroundCategory.retry,
                  PlaygroundCategory.almostCorrect,
                  PlaygroundCategory.correct,
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}
