import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../services/audio/kogo_voice_manager.dart';

enum IcebreakingType {
  surpriseStar,
  colorBalloons,
  catchStars,
}

/// Dialog mini game interaktif ramah anak untuk icebreaking setiap 5 pertanyaan.
class IcebreakingDialog extends StatefulWidget {
  final IcebreakingType type;
  final VoidCallback onContinue;

  const IcebreakingDialog({
    super.key,
    required this.type,
    required this.onContinue,
  });

  static Future<void> show(
    BuildContext context, {
    IcebreakingType? type,
    required VoidCallback onContinue,
  }) {
    final randomType = type ??
        IcebreakingType.values[math.Random().nextInt(IcebreakingType.values.length)];

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => IcebreakingDialog(
        type: randomType,
        onContinue: onContinue,
      ),
    );
  }

  @override
  State<IcebreakingDialog> createState() => _IcebreakingDialogState();
}

class _IcebreakingDialogState extends State<IcebreakingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  int _score = 0;
  bool _completed = false;
  Timer? _autoCloseTimer;

  // Mini-game state
  // 1. Surprise Star
  bool _starPopped = false;

  // 2. Color Balloons (5 balloons)
  late final List<bool> _balloonsPopped;
  final List<Color> _balloonColors = const [
    Color(0xFFFF5964),
    Color(0xFFFFB703),
    Color(0xFF38B000),
    Color(0xFF0077B6),
    Color(0xFF9D4EDD),
  ];

  // 3. Catch Stars (5 stars)
  late final List<Offset> _starPositions;
  late final List<bool> _starsCollected;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _balloonsPopped = List.filled(5, false);
    _starsCollected = List.filled(5, false);

    final rng = math.Random();
    _starPositions = List.generate(
      5,
      (_) => Offset(0.15 + rng.nextDouble() * 0.7, 0.2 + rng.nextDouble() * 0.5),
    );

    // Play cheerful audio greeting
    KogoVoiceManager.instance.playEncouragement('listen_repeat');

    // Auto-advance after 15 seconds if idle
    _autoCloseTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) _handleDone();
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _handleDone() {
    if (_completed) return;
    _completed = true;
    _autoCloseTimer?.cancel();
    Navigator.of(context, rootNavigator: true).pop();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
          border: Border.all(color: const Color(0xFFFFD166), width: 3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: _buildGameBody(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _handleDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B4A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 4,
              ),
              child: Text(
                _score > 0 ? 'Lanjut Belajar! 🚀' : 'Lewati / Lanjut ⏩',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title = 'Waktunya Istirahat & Main! 🎉';
    String subtitle = 'Hebat! Kamu sudah menjawab 5 pertanyaan.';

    switch (widget.type) {
      case IcebreakingType.surpriseStar:
        title = 'Bintang Kejutan! ⭐';
        subtitle = 'Ketuk bintang besar untuk melihat kejutan!';
        break;
      case IcebreakingType.colorBalloons:
        title = 'Letuskan Balon! 🎈';
        subtitle = 'Ketuk semua balon warna-warni sampai meletus!';
        break;
      case IcebreakingType.catchStars:
        title = 'Tangkap Bintang Jatuh! 🌟';
        subtitle = 'Ketuk bintang yang bersinar untuk menangkapnya!';
        break;
    }

    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF6B4A),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 14, color: Color(0xFF718096)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildGameBody() {
    switch (widget.type) {
      case IcebreakingType.surpriseStar:
        return _buildSurpriseStarGame();
      case IcebreakingType.colorBalloons:
        return _buildColorBalloonsGame();
      case IcebreakingType.catchStars:
        return _buildCatchStarsGame();
    }
  }

  // GAME 1: Bintang Kejutan
  Widget _buildSurpriseStarGame() {
    return Center(
      child: GestureDetector(
        onTap: () {
          if (!_starPopped) {
            setState(() {
              _starPopped = true;
              _score = 100;
            });
            Timer(const Duration(milliseconds: 1400), () {
              if (mounted) _handleDone();
            });
          }
        },
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final scale = _starPopped
                ? 1.4
                : 1.0 + (_animController.value * 0.15);
            return Transform.scale(
              scale: scale,
              child: _starPopped
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.auto_awesome, size: 100, color: Color(0xFFFFB703)),
                        SizedBox(height: 12),
                        Text(
                          'HOREEE! KAMU JUARA! 🎊',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF6B4A),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      padding: const EdgeInsets.all(28),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF3CD),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x33FFB703),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 96,
                        color: Color(0xFFFFB703),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  // GAME 2: Balon Warna-Warni
  Widget _buildColorBalloonsGame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(5, (index) {
            final isPopped = _balloonsPopped[index];
            final color = _balloonColors[index];

            return GestureDetector(
              onTap: () {
                if (!isPopped) {
                  setState(() {
                    _balloonsPopped[index] = true;
                    _score += 20;
                  });
                  if (_balloonsPopped.every((b) => b)) {
                    Timer(const Duration(milliseconds: 800), () {
                      if (mounted) _handleDone();
                    });
                  }
                }
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isPopped ? 0.2 : 1.0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 65,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(25),
                          bottom: Radius.circular(25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: isPopped
                          ? const Icon(Icons.flash_on, color: Colors.white, size: 28)
                          : const SizedBox.shrink(),
                    ),
                    Container(
                      width: 2,
                      height: 25,
                      color: const Color(0xFFCBD5E0),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  // GAME 3: Tangkap Bintang Jatuh
  Widget _buildCatchStarsGame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: List.generate(5, (index) {
            if (_starsCollected[index]) return const SizedBox.shrink();
            final pos = _starPositions[index];
            final posX = pos.dx * constraints.maxWidth;
            final posY = pos.dy * constraints.maxHeight;

            return Positioned(
              left: posX,
              top: posY,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _starsCollected[index] = true;
                    _score += 20;
                  });
                  if (_starsCollected.every((s) => s)) {
                    Timer(const Duration(milliseconds: 800), () {
                      if (mounted) _handleDone();
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFAEB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFB703).withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    size: 36,
                    color: Color(0xFFFFB703),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
