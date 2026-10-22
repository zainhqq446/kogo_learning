import 'package:flutter/material.dart';

import '../../../../services/speech/restricted_vocabulary_speech_service.dart';

class RestrictedVocabularyTestPage extends StatefulWidget {
  const RestrictedVocabularyTestPage({super.key});

  @override
  State<RestrictedVocabularyTestPage> createState() =>
      _RestrictedVocabularyTestPageState();
}

class _RestrictedVocabularyTestPageState
    extends State<RestrictedVocabularyTestPage> {
  final RestrictedVocabularySpeechService _service =
      RestrictedVocabularySpeechService();

  final List<String> _words = const [
    'apel',
    'bola',
    'buku',
    'meja',
    'kursi',
    'pipi',
    'mata',
    'kaki',
    'gigi',
    'tangan',
    'baju',
    'botol',
    'lampu',
    'kayu',
    'bebek',
    'kucing',
    'ikan',
    'rumah',
    'jendela',
    'sepatu',
  ];

  String _selectedWord = 'apel';
  String _partial = '';
  String _result = '';
  String _selectedResult = '';
  List<String> _alternates = [];
  double _confidence = 0;
  bool _isFinal = false;
  bool _listening = false;
  bool _correct = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.initialize();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _listening = true;
      _partial = '';
      _result = '';
      _selectedResult = '';
      _alternates = [];
      _confidence = 0;
      _isFinal = false;
      _correct = false;
      _error = '';
    });

    await _service.startListening(
      targetWord: _selectedWord,

      // Untuk pengujian pertama kita sengaja hanya
      // memberikan target sebagai vocabulary.
      vocabulary: [_selectedWord],

      onPartial: (text) {
        if (!mounted) return;

        setState(() {
          _partial = text;
        });
      },

      onResult: (result) {
        if (!mounted) return;

        final isCorrect =
            _service.matchesTarget(result.selectedText);

        setState(() {
          _result = result.recognizedText;
          _selectedResult = result.selectedText;
          _alternates = result.alternates;
          _confidence = result.confidence;
          _isFinal = result.isFinal;
          _correct = isCorrect;
        });
      },

      onError: (message) {
        if (!mounted) return;

        setState(() {
          _listening = false;
          _error = message;
        });
      },
    );

    if (mounted) {
      setState(() {
        _listening = _service.isListening;
      });
    }
  }

  Future<void> _stop() async {
    await _service.stopListening();

    if (!mounted) return;

    setState(() {
      _listening = false;
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Restricted Vocabulary Test',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Target Kata',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              initialValue: _selectedWord,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: _words.map(
                (word) {
                  return DropdownMenuItem(
                    value: word,
                    child: Text(
                      word,
                      style: const TextStyle(
                        fontSize: 20,
                      ),
                    ),
                  );
                },
              ).toList(),
              onChanged: _listening
                  ? null
                  : (value) {
                      if (value == null) return;

                      setState(() {
                        _selectedWord = value;
                      });
                    },
            ),

            const SizedBox(height: 30),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    _listening
                        ? Icons.mic
                        : Icons.mic_none,
                    size: 80,
                  ),

                  const SizedBox(height: 15),

                  Text(
                    _listening
                        ? 'Silakan ucapkan "$_selectedWord"'
                        : 'Tekan MULAI',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_listening)
              ElevatedButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text(
                  'STOP',
                  style: TextStyle(fontSize: 18),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.mic),
                label: const Text(
                  'MULAI',
                  style: TextStyle(fontSize: 18),
                ),
              ),

            const SizedBox(height: 30),

            _ResultCard(
              title: 'Partial',
              value: _partial.isEmpty ? '-' : _partial,
            ),

            const SizedBox(height: 12),

            _ResultCard(
              title: 'Hasil Final',
              value: _result.isEmpty ? '-' : _result,
            ),

            const SizedBox(height: 12),

            _ResultCard(
              title: 'Hasil Terpilih',
              value: _selectedResult.isEmpty
                  ? '-'
                  : _selectedResult,
            ),

            const SizedBox(height: 12),

            _ResultCard(
              title: 'Alternates',
              value: _alternates.isEmpty
                  ? '-'
                  : _alternates.join('\n'),
            ),

            const SizedBox(height: 12),

            _ResultCard(
              title: 'Confidence',
              value: _confidence == 0
                  ? 'N/A'
                  : _confidence.toStringAsFixed(3),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _correct
                    ? 'BENAR'
                    : (_isFinal ? 'BELUM BENAR' : '-'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                _error,
                style: const TextStyle(
                  fontSize: 15,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final String value;

  const _ResultCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}