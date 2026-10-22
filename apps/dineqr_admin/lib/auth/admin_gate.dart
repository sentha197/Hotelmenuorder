import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../shell/admin_shell.dart';
import '../state/admin_session_controller.dart';
import 'admin_login_screen.dart';

/// The admin app's home: the sign-in screen until a valid session exists,
/// then the role's workspace. A restored session opens the workspace
/// directly.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  /// The launch intro plays only for the sign-in screen the app opens on,
  /// not after signing out.
  bool _launching = true;

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AdminSessionController, String?>(
      (admin) => admin.actor?.id,
    );
    final intro = _launching && signedIn == null;
    _launching = false;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.slow),
        switchInCurve: Motion.brand,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: signedIn == null
            ? AdminLoginScreen(
                key: const ValueKey('login'),
                playLaunchIntro: intro,
              )
            : AdminShell(key: ValueKey('shell-$signedIn')),
      ),
    );
  }
}
