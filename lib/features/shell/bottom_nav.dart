import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';

class NavItem {
  const NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Navigasi bawah Beranda / Hadiah / Profil (desain Figma): indikator
/// gradien ungu-pink yang meluncur, ikon aktif membesar, lencana hadiah baru.
class KogoBottomNav extends StatelessWidget {
  const KogoBottomNav({super.key, required this.index, required this.onTap, this.rewardBadge = 0});

  final int index;
  final ValueChanged<int> onTap;
  final int rewardBadge;

  static const items = [NavItem('Beranda', Icons.home_rounded), NavItem('Hadiah', Icons.emoji_events_rounded), NavItem('Profil', Icons.person_rounded)];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KogoColors.white,
        border: Border(top: BorderSide(color: KogoColors.purple200, width: 4)),
        boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 30, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    top: 0,
                    left: slot * index + slot / 2 - 24,
                    child: Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(gradient: KogoColors.r(KogoColors.purple500, KogoColors.pink500), borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavButton(item: items[i], active: i == index, badge: i == 1 ? rewardBadge : 0, onTap: () => onTap(i)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.badge, required this.onTap});

  final NavItem item;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      label: badge > 0 ? '${item.label}, $badge hadiah baru' : item.label,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.9,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSlide(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  offset: Offset(0, active ? -0.08 : 0),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    scale: active ? 1.15 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: active ? KogoColors.br(KogoColors.purple400, KogoColors.pink400) : null),
                      child: Icon(item.icon, size: 26, color: active ? KogoColors.white : KogoColors.gray400),
                    ),
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Entrance.pop(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 24),
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: KogoColors.r(KogoColors.red500, KogoColors.pink500),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: KogoColors.white, width: 2),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: KogoColors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: active ? KogoColors.purple600 : KogoColors.gray400),
            ),
          ],
        ),
      ),
    );
  }
}
