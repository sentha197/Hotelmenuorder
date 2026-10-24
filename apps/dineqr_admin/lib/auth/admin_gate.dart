import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../shell/admin_shell.dart';
import '../state/admin_session_controller.dart';
import 'admin_login_screen.dart';
import 'admin_splash_screen.dart';

/// The admin app's home: with [showSplash], the splash while the saved
/// session is restored; then the sign-in screen until a valid session
/// exists, and the role's workspace after it. A restored session opens the
/// workspace directly.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key, this.showSplash = false});

  final bool showSplash;

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  late bool _splash = widget.showSplash;

  /// The launch intro plays only for the sign-in screen the app opens on,
  /// not after signing out.
  bool _launching = true;

  /// The splash ends on the sign-in screen's first frame, so that one
  /// change happens at once rather than as a cross-fade.
  bool _instant = false;

  void _splashFinished(AdminSplashExit exit) {
    setState(() {
      _splash = false;
      _instant = exit == AdminSplashExit.signIn;
    });
    if (_instant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _instant = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AdminSessionController, String?>(
      (admin) => admin.actor?.id,
    );
    final Widget page;
    if (_splash) {
      page = AdminSplashScreen(
        key: const ValueKey('splash'),
        onFinished: _splashFinished,
      );
    } else {
      final intro = _launching && signedIn == null;
      _launching = false;
      page = signedIn == null
          ? AdminLoginScreen(
              key: const ValueKey('login'),
              playLaunchIntro: intro,
            )
          : AdminShell(key: ValueKey('shell-$signedIn'));
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AnimatedSwitcher(
        duration: _instant ? Duration.zero : Motion.of(context, Motion.slow),
        switchInCurve: Motion.brand,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: page,
      ),
    );
  }
}
