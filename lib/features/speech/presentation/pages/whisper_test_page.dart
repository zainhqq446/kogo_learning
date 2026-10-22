import 'package:flutter/material.dart';

import '../../../../services/speech/whisper_speech_service.dart';

class WhisperTestPage extends StatefulWidget {
  const WhisperTestPage({super.key});

  @override
  State<WhisperTestPage> createState() => _WhisperTestPageState();
}

class _WhisperTestPageState extends State<WhisperTestPage> {
  final WhisperSpeechService _whisperService =
      WhisperSpeechService.instance;

  bool _preparing = false;
  bool _ready = false;
  bool _isRecording = false;

  bool _useBaseModel = false;

  double _downloadProgress = 0;

  String _status = 'Model belum siap.';
  String _recognizedText = '';

  String? _errorMessage;

  double? _recordedSeconds;
  Duration? _inferenceTime;
  Duration? _measuredInferenceTime;
  Duration? _totalElapsed;
  double? _speechSeconds;

  Future<void> _autoStopAndTranscribe() async {
    if (!_isRecording) {
      return;
    }

    if (mounted) {
      setState(() {
        _status = 'Memproses suara...';
      });
    }

    await _stopAndTranscribe();
  }

  Future<void> _prepareWhisper() async {
    if (_preparing || _isRecording) {
      return;
    }

    setState(() {
      _preparing = true;
      _errorMessage = null;
      _status = _useBaseModel
          ? 'Menyiapkan Whisper Base...'
          : 'Menyiapkan Whisper Tiny...';
      _downloadProgress = 0;
    });

    try {
      await _whisperService.initialize(
        useBaseModel: _useBaseModel,
        onDownloadProgress: (progress) {
          if (!mounted) {
            return;
          }

          setState(() {
            _downloadProgress = progress;
            _status =
                'Mengunduh model... '
                '${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _ready = true;
        _preparing = false;
        _status = _useBaseModel
            ? 'Whisper Base siap.'
            : 'Whisper Tiny siap.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _preparing = false;
        _ready = false;
        _status = 'Gagal menyiapkan Whisper.';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _startRecording() async {
  if (!_ready || _isRecording) {
    return;
  }

  setState(() {
    _isRecording = true;
    _recognizedText = '';
    _errorMessage = null;
    _status = 'Mendengarkan...';

    _recordedSeconds = null;
    _speechSeconds = null;
    _inferenceTime = null;
    _measuredInferenceTime = null;
    _totalElapsed = null;
  });

  try {
    await _whisperService.startRecording(
      onSpeechEnded: _autoStopAndTranscribe,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _status = 'Silakan berbicara...';
    });
  } catch (e) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isRecording = false;
      _status = 'Gagal memulai rekaman.';
      _errorMessage = e.toString();
    });
  }
}

  Future<void> _stopAndTranscribe() async {
    if (!_isRecording) {
      return;
    }

    setState(() {
      _status = 'Memproses suara...';
    });

    try {
      final result =
          await _whisperService.stopAndTranscribe(
        useBaseModel: _useBaseModel,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecording = false;
        _recognizedText = result.text;

        _recordedSeconds = result.recordedSeconds;
        _inferenceTime = result.inferenceTime;
        _measuredInferenceTime =
            result.measuredInferenceTime;
        _totalElapsed = result.totalElapsed;

        _status = 'Transkripsi selesai.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecording = false;
        _status = 'Transkripsi gagal.';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) {
      return;
    }

    try {
      await _whisperService.cancelRecording();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = e.toString();
      });

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isRecording = false;
      _recognizedText = '';
      _status = 'Rekaman dibatalkan.';
    });
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '-';
    }

    final milliseconds = duration.inMilliseconds;

    if (milliseconds < 1000) {
      return '$milliseconds ms';
    }

    return '${(milliseconds / 1000).toStringAsFixed(2)} detik';
  }

  void _changeModel(bool value) {
    if (_preparing || _isRecording) {
      return;
    }

    setState(() {
      _useBaseModel = value;
      _ready = false;

      _recognizedText = '';
      _errorMessage = null;

      _downloadProgress = 0;

      _recordedSeconds = null;
      _inferenceTime = null;
      _measuredInferenceTime = null;
      _totalElapsed = null;

      _status = value
          ? 'Model Base belum siap.'
          : 'Model Tiny belum siap.';
    });
  }

  @override
  void dispose() {
    _whisperService.cancelRecording();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whisper Test'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),

            const Icon(
              Icons.graphic_eq,
              size: 80,
            ),

            const SizedBox(height: 20),

            Text(
              'Tes Voice Recognition',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 10),

            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
              ),
            ),

            const SizedBox(height: 24),

            SwitchListTile(
              value: _useBaseModel,
              onChanged:
                  (_preparing || _isRecording) ? null : _changeModel,
              title: const Text(
                'Gunakan Whisper Base',
              ),
              subtitle: Text(
                _useBaseModel
                    ? 'Lebih berat, kandidat uji akurasi.'
                    : 'Lebih ringan, kandidat uji latency.',
              ),
            ),

            const SizedBox(height: 16),

            if (_preparing) ...[
              LinearProgressIndicator(
                value: _downloadProgress > 0
                    ? _downloadProgress
                    : null,
              ),

              const SizedBox(height: 8),

              Text(
                '${(_downloadProgress * 100).toStringAsFixed(0)}%',
              ),
            ],

            if (!_ready && !_preparing)
              FilledButton.icon(
                onPressed: _prepareWhisper,
                icon: const Icon(Icons.download),
                label: Text(
                  _useBaseModel
                      ? 'Siapkan Whisper Base'
                      : 'Siapkan Whisper Tiny',
                ),
              ),

            if (_ready) ...[
              const SizedBox(height: 8),

              if (!_isRecording)
                FilledButton.icon(
                  onPressed: _startRecording,
                  icon: const Icon(Icons.mic),
                  label: const Text(
                    'Mulai Berbicara',
                  ),
                ),

              if (_isRecording)
                FilledButton.icon(
                  onPressed: _stopAndTranscribe,
                  icon: const Icon(Icons.stop),
                  label: const Text(
                    'Selesai & Proses',
                  ),
                ),

              const SizedBox(height: 10),

              if (_isRecording)
                OutlinedButton(
                  onPressed: _cancelRecording,
                  child: const Text(
                    'Batalkan',
                  ),
                ),
            ],

            const SizedBox(height: 28),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
              child: Column(
                children: [
                  const Text(
                    'Hasil Transkripsi',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    _recognizedText.isEmpty
                        ? 'Belum ada hasil.'
                        : _recognizedText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Benchmark',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  _BenchmarkRow(
                    label: 'Durasi rekaman',
                    value: _recordedSeconds == null
                        ? '-'
                        : '${_recordedSeconds!.toStringAsFixed(2)} detik',
                  ),

                  _BenchmarkRow(
                    label: 'Durasi speech',
                    value: _speechSeconds == null
                        ? '-'
                        : '${_speechSeconds!.toStringAsFixed(2)} detik',
                  ),

                  _BenchmarkRow(
                    label: 'Inference native',
                    value: _formatDuration(
                      _inferenceTime,
                    ),
                  ),

                  _BenchmarkRow(
                    label: 'Inference terukur',
                    value: _formatDuration(
                      _measuredInferenceTime,
                    ),
                  ),

                  _BenchmarkRow(
                    label: 'Total waktu',
                    value: _formatDuration(
                      _totalElapsed,
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 20),

              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkRow extends StatelessWidget {
  final String label;
  final String value;

  const _BenchmarkRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}