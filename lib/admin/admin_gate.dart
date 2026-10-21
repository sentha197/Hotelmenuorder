import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/animations/motion.dart';
import '../state/admin_session_controller.dart';
import 'admin_login_screen.dart';
import 'admin_shell.dart';

/// Entry to the staff area: the sign-in screen until a valid session
/// exists, then the dashboard shell.
class AdminGate extends StatelessWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AdminSessionController, String?>(
      (admin) => admin.actor?.id,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: signedIn == null
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.slow),
        switchInCurve: Motion.brand,
        child: signedIn == null
            ? const AdminLoginScreen(key: ValueKey('login'))
            : AdminShell(key: ValueKey('shell-$signedIn')),
      ),
    );
  }
}
