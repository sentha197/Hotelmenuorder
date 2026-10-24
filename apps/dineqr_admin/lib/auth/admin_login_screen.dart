import 'dart:ui' show lerpDouble;

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/admin_theme.dart';
import '../brand/admin_backdrop.dart';
import '../brand/admin_brand.dart';
import '../shell/admin_modules.dart';
import '../state/admin_session_controller.dart';

/// Staff sign-in, the first screen of the admin app after the splash.
///
/// With [playLaunchIntro], the first frame matches the splash's last one
/// (the white DineQR symbol, [launchMarkWidth] wide, centred on the lit
/// admin backdrop). The symbol then glides into the header while the form
/// rises in. Demo accounts are listed only in the offline demo.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, this.playLaunchIntro = false});

  /// Width of the symbol on the native launch screens (logical pixels). The
  /// launch images are generated at this size by
  /// `tool/generate_brand_assets_test.dart`.
  static const launchMarkWidth = 120.0;

  final bool playLaunchIntro;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _stackKey = GlobalKey();
  final _markSlot = GlobalKey();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  bool _obscure = true;
  String? _error;
  String? _notice;
  int _errorCount = 0;

  /// Where the symbol settles, relative to the screen (measured after the
  /// first layout). Null until measured.
  Rect? _slot;

  @override
  void initState() {
    super.initState();
    _notice = context.read<AdminSessionController>().takeEndedReason();
    if (widget.playLaunchIntro) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
    } else {
      _intro.value = 1;
    }
  }

  void _startIntro() {
    if (!mounted) return;
    if (Motion.reduced(context)) {
      _intro.value = 1;
      return;
    }
    final slot = _markSlot.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (slot == null || stack == null || !slot.hasSize) {
      _intro.value = 1;
      return;
    }
    final topLeft = slot.localToGlobal(Offset.zero, ancestor: stack);
    setState(() => _slot = topLeft & slot.size);
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      await context.read<AdminSessionController>().signIn(
        _email.text,
        _password.text,
      );
      HapticFeedback.mediumImpact();
    } on AuthException catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _error = error.error.message;
        _errorCount++;
      });
      _password.clear();
    }
  }

  void _useDemo(String email) {
    setState(() {
      _email.text = email;
      _password.text = DemoCredentials.password;
      _error = null;
    });
  }

  Future<void> _forgotPassword(bool demo) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Forgot your password?', style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ask the restaurant owner to reset it from Staff → Reset '
              'password. Email reset links need the DineQR server, which '
              'is not connected to this build.',
              style: AppTypography.bodySecondary,
            ),
            if (demo) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'In this offline demo every demo account uses the password '
                '${DemoCredentials.password}.',
                style: AppTypography.bodySecondary,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Got it',
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final form = _LoginCard(
      formKey: _form,
      email: _email,
      password: _password,
      passwordFocus: _passwordFocus,
      obscure: _obscure,
      busy: admin.isBusy,
      error: _error,
      notice: _notice,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onSubmit: _signIn,
      onForgot: () => _forgotPassword(admin.isDemo),
    );
    final demo = admin.isDemo ? _DemoAccounts(onPick: _useDemo) : null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AdminColors.navy,
        body: Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            // Already lit: the splash blooms it in before handing over.
            const AdminBackdrop(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 880;
                  final mark = _MarkSlot(
                    key: _markSlot,
                    intro: _intro,
                    width: wide ? 96 : 88,
                  );
                  return wide
                      ? _WideLayout(
                          intro: _intro,
                          mark: mark,
                          form: form,
                          demo: demo,
                          errorCount: _errorCount,
                        )
                      : _NarrowLayout(
                          intro: _intro,
                          mark: mark,
                          form: form,
                          demo: demo,
                          errorCount: _errorCount,
                        );
                },
              ),
            ),
            // The symbol travelling from the launch-screen position.
            if (_slot != null)
              AnimatedBuilder(
                animation: _intro,
                builder: (context, _) {
                  if (_intro.isCompleted) return const SizedBox.shrink();
                  final slot = _slot!;
                  final screen = constraintsOf(context);
                  final t = Motion.emphasized.transform(
                    const Interval(0, 0.7).transform(_intro.value),
                  );
                  final width = lerpDouble(
                    AdminLoginScreen.launchMarkWidth,
                    slot.width,
                    t,
                  )!;
                  final center = Offset.lerp(
                    screen.center(Offset.zero),
                    slot.center,
                    t,
                  )!;
                  final height = width / DineQrMark.aspectRatio;
                  return Positioned(
                    left: center.dx - width / 2,
                    top: center.dy - height / 2,
                    child: DineQrMark(
                      size: width,
                      tone: DineQrTone.inverted,
                      semanticLabel: null,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Size constraintsOf(BuildContext context) => MediaQuery.sizeOf(context);
}

/// Where the symbol sits in the layout. Hidden while the travelling copy
/// is in flight so the two never show at once.
class _MarkSlot extends StatelessWidget {
  const _MarkSlot({super.key, required this.intro, required this.width});

  final Animation<double> intro;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: intro,
      builder: (context, child) =>
          Opacity(opacity: intro.isCompleted ? 1 : 0, child: child),
      child: DineQrMark(size: width, tone: DineQrTone.inverted),
    );
  }
}

/// Stagger helper: [child] fades and rises in during [begin]–[end] of the
/// intro.
class _IntroItem extends StatelessWidget {
  const _IntroItem({
    required this.intro,
    required this.begin,
    required this.child,
    this.end = 1,
  });

  final Animation<double> intro;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: intro,
      builder: (context, child) {
        final t = Interval(
          begin,
          end,
          curve: Motion.brand,
        ).transform(intro.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.intro,
    required this.mark,
    required this.form,
    required this.demo,
    required this.errorCount,
  });

  final Animation<double> intro;
  final Widget mark;
  final Widget form;
  final Widget? demo;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(height: AppSpacing.md),
              _IntroItem(
                intro: intro,
                begin: 0.35,
                end: 0.8,
                child: const _Title(center: true),
              ),
              const SizedBox(height: AppSpacing.xl),
              _IntroItem(
                intro: intro,
                begin: 0.45,
                child: ShakeOnChange(trigger: errorCount, child: form),
              ),
              if (demo != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _IntroItem(intro: intro, begin: 0.55, child: demo!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.intro,
    required this.mark,
    required this.form,
    required this.demo,
    required this.errorCount,
  });

  final Animation<double> intro;
  final Widget mark;
  final Widget form;
  final Widget? demo;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 48, 40, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark,
                const SizedBox(height: AppSpacing.lg),
                _IntroItem(
                  intro: intro,
                  begin: 0.35,
                  end: 0.8,
                  child: const _Title(center: false),
                ),
                const Spacer(),
                _IntroItem(
                  intro: intro,
                  begin: 0.5,
                  child: Text(
                    'Orders, kitchen, bills and reports\nfor your restaurant team.',
                    style: AppTypography.display.copyWith(
                      color: AdminColors.frameText,
                      fontSize: 30,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _IntroItem(
                  intro: intro,
                  begin: 0.6,
                  child: const Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _Capability(Icons.receipt_long_rounded, 'Live orders'),
                      _Capability(
                        Icons.soup_kitchen_rounded,
                        'Kitchen display',
                      ),
                      _Capability(
                        Icons.point_of_sale_rounded,
                        'Bills & payments',
                      ),
                      _Capability(Icons.insights_rounded, 'Reports'),
                      _Capability(Icons.qr_code_2_rounded, 'Table QR codes'),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 480,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IntroItem(
                    intro: intro,
                    begin: 0.4,
                    child: ShakeOnChange(trigger: errorCount, child: form),
                  ),
                  if (demo != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _IntroItem(intro: intro, begin: 0.55, child: demo!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.center});

  final bool center;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        const DineQrAdminLockup(height: 44, showMark: false),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Restaurant management',
          style: AppTypography.bodySecondary.copyWith(
            color: AdminColors.frameMuted,
          ),
        ),
      ],
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: AppRadii.pill,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.warmOrange),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.label.copyWith(color: AdminColors.frameText),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.email,
    required this.password,
    required this.passwordFocus,
    required this.obscure,
    required this.busy,
    required this.error,
    required this.notice,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgot,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final FocusNode passwordFocus;
  final bool obscure;
  final bool busy;
  final String? error;
  final String? notice;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Staff sign in',
                style: AppTypography.headline.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 2),
              Text(
                'Use the account your restaurant gave you.',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (notice != null) ...[
                _Banner(text: notice!, color: AppColors.info),
                const SizedBox(height: AppSpacing.md),
              ],
              AnimatedSize(
                duration: Motion.of(context, Motion.medium),
                curve: Motion.standard,
                child: error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _Banner(text: error!, color: AppColors.error),
                      ),
              ),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                autocorrect: false,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter your email.';
                  if (!text.contains('@') || !text.contains('.')) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => passwordFocus.requestFocus(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: password,
                focusNode: passwordFocus,
                obscureText: obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value ?? '').isEmpty ? 'Enter your password.' : null,
                onFieldSubmitted: (_) => onSubmit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : onForgot,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              PrimaryButton(
                label: 'Sign in',
                icon: Icons.login_rounded,
                isLoading: busy,
                onPressed: busy ? null : onSubmit,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Sessions end after 8 hours. Repeated failures lock '
                      'sign-in for a minute.',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              color == AppColors.error
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: AppTypography.label.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DemoTag(onDark: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Demo accounts (offline demo only)',
                  style: AppTypography.label.copyWith(
                    color: AdminColors.frameText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap a role to fill in its sign-in. Password for every demo '
            'account: ${DemoCredentials.password}',
            style: AppTypography.caption.copyWith(
              color: AdminColors.frameMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final account in DemoCredentials.accounts)
                Pressable(
                  onTap: () => onPick(account.email),
                  semanticLabel: 'Use the ${account.role.label} demo account',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AdminColors.frameRaised,
                      borderRadius: AppRadii.pill,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          account.role.workspace.icon,
                          size: 15,
                          color: AppColors.warmOrange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          account.role.label,
                          style: AppTypography.label.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
