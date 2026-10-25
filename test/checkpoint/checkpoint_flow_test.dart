import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/features/lesson/presentation/widgets/checkpoint_reward_dialog.dart';

void main() {
  group('Verifikasi Widget Reward Checkpoint', () {
    testWidgets('CheckpointRewardDialog merender piala, bintang, dan tombol klaim', (tester) async {
      bool isClaimed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  CheckpointRewardDialog.show(
                    context: context,
                    stageId: 2,
                    checkpointNumber: 1,
                    checkpointTitle: 'Checkpoint 1',
                    onClaimed: () {
                      isClaimed = true;
                    },
                  );
                },
                child: const Text('Buka Dialog'),
              ),
            ),
          ),
        ),
      );

      // Tekan tombol untuk buka dialog
      await tester.tap(find.text('Buka Dialog'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verifikasi komponen dialog
      expect(find.text('Luar Biasa!'), findsOneWidget);
      expect(find.text('Kamu berhasil menyelesaikan Checkpoint 1!'), findsOneWidget);
      expect(find.text('+50 Koin Bintang!'), findsOneWidget);
      expect(find.text('Klaim Hadiah 🚀'), findsOneWidget);

      // Tekan tombol klaim
      await tester.tap(find.text('Klaim Hadiah 🚀'));
      await tester.pump();

      expect(isClaimed, isTrue);
    });
  });
}
