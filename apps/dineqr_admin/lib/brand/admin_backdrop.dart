import 'package:flutter/material.dart';

import '../app/admin_theme.dart';

/// The admin frame's backdrop: burgundy to charcoal, lit by a soft red glow
/// from the top-left and an orange one from the bottom-right. Shared by the
/// splash and the sign-in screen, so one hands over to the other without a
/// visible change.
///
/// [reveal] (0-1) blooms it in from the plain launch-screen colour
/// ([AdminColors.navy]): the gradient first, the lights a little after.
class AdminBackdrop extends StatelessWidget {
  const AdminBackdrop({super.key, this.reveal = 1});

  final double reveal;

  @override
  Widget build(BuildContext context) {
    final base = Curves.easeOut.transform(reveal.clamp(0.0, 1.0));
    final glow = Curves.easeOut.transform(
      ((reveal - 0.15) / 0.85).clamp(0.0, 1.0),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AdminColors.navy),
        Opacity(
          opacity: base,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AdminColors.frame,
                  AdminColors.navy,
                  Color(0xFF12090B),
                ],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
        ),
        Opacity(
          opacity: glow,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.7, -0.75),
                radius: 1.0,
                colors: [Color(0x40D62828), Color(0x00D62828)],
              ),
            ),
          ),
        ),
        Opacity(
          opacity: glow * 0.8,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.9, 0.95),
                radius: 0.9,
                colors: [Color(0x30FF6A00), Color(0x00FF6A00)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
