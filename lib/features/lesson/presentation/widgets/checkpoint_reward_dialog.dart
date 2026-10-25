import 'dart:async';
import 'package:flutter/material.dart';


class CheckpointRewardDialog extends StatefulWidget {
  final int stageId;
  final int checkpointNumber;
  final String checkpointTitle;
  final VoidCallback onClaimed;

  const CheckpointRewardDialog({
    super.key,
    required this.stageId,
    required this.checkpointNumber,
    required this.checkpointTitle,
    required this.onClaimed,
  });

  static Future<void> show({
    required BuildContext context,
    required int stageId,
    required int checkpointNumber,
    required String checkpointTitle,
    required VoidCallback onClaimed,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CheckpointRewardDialog(
        stageId: stageId,
        checkpointNumber: checkpointNumber,
        checkpointTitle: checkpointTitle,
        onClaimed: onClaimed,
      ),
    );
  }

  @override
  State<CheckpointRewardDialog> createState() => _CheckpointRewardDialogState();
}

class _CheckpointRewardDialogState extends State<CheckpointRewardDialog>
    with TickerProviderStateMixin {
  late final AnimationController _mainAnimController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _chestPulseAnimation;

  late final AnimationController _starController1;
  late final AnimationController _starController2;
  late final AnimationController _starController3;

  Timer? _timer1;
  Timer? _timer2;
  Timer? _timer3;

  bool _isClaimed = false;

  @override
  void initState() {
    super.initState();

    _mainAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _mainAnimController,
      curve: Curves.easeOutBack,
    );

    _chestPulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(
        parent: _mainAnimController,
        curve: Curves.easeInOutSine,
      ),
    );

    _starController1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _starController2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _starController3 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _mainAnimController.forward().then((_) {
      if (!mounted) return;
      _timer1 = Timer(const Duration(milliseconds: 200), () {
        if (mounted) _starController1.forward();
      });
      _timer2 = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _starController2.forward();
      });
      _timer3 = Timer(const Duration(milliseconds: 800), () {
        if (mounted) _starController3.forward();
      });
    });
  }

  @override
  void dispose() {
    _timer1?.cancel();
    _timer2?.cancel();
    _timer3?.cancel();
    _mainAnimController.dispose();
    _starController1.dispose();
    _starController2.dispose();
    _starController3.dispose();
    super.dispose();
  }


  Widget _buildStar(AnimationController controller, double size) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: controller, curve: Curves.elasticOut),
      child: Icon(
        Icons.star_rounded,
        size: size,
        color: const Color(0xFFFFB800),
        shadows: [
          BoxShadow(
            color: const Color(0xFFFFB800).withValues(alpha: 0.5),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFFDF5),
                Color(0xFFFEF3C7),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFFFCD34D), width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge Peti Emas / Piala Kemenangan
              ScaleTransition(
                scale: _chestPulseAnimation,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD54F), Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('🎁', style: TextStyle(fontSize: 48)),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Title
              Text(
                'Luar Biasa!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF92400E),
                  shadows: [
                    Shadow(
                      color: Colors.amber.shade200,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Kamu berhasil menyelesaikan ${widget.checkpointTitle}!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFB45309),
                ),
              ),

              const SizedBox(height: 20),

              // Bintang 3 Staggered
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildStar(_starController1, 46),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildStar(_starController2, 60),
                  ),
                  const SizedBox(width: 8),
                  _buildStar(_starController3, 46),
                ],
              ),

              const SizedBox(height: 16),

              // Badge Hadiah Koin
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🪙', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 6),
                    Text(
                      '+50 Koin Bintang!',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // Tombol Klaim Hadiah
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: const Color(0xFF059669).withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: _isClaimed
                      ? null
                      : () {
                          setState(() {
                            _isClaimed = true;
                          });
                          Navigator.pop(context);
                          widget.onClaimed();
                        },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Klaim Hadiah 🚀',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
