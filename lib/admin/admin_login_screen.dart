import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/theme/app_colors.dart';
import '../app/theme/app_theme.dart';
import '../app/theme/app_typography.dart';
import '../core/animations/motion.dart';
import '../core/brand/brand_surfaces.dart';
import '../core/brand/dineqr_logo.dart';
import '../core/widgets/app_buttons.dart';
import '../data/services/auth_service.dart';
import '../state/admin_session_controller.dart';

/// Staff sign-in. Separate from the guest app; demo accounts are listed
/// only in the offline demo.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  String? _error;
  String? _notice;
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    _notice = context.read<AdminSessionController>().takeEndedReason();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final canLeave = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.ember,
      body: BrandPanel(
        gradient: AppColors.nightGradient,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canLeave)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back'),
                        ),
                      ),
                    const FadeSlideIn(
                      child: DineQrMark(size: 110, tone: DineQrTone.inverted),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const FadeSlideIn(
                      index: 1,
                      child: DineQrWordmark(fontSize: 34, onDark: true),
                    ),
                    Text(
                      'RESTAURANT DASHBOARD',
                      style: AppTypography.overline.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FadeSlideIn(
                      index: 2,
                      child: ShakeOnChange(
                        trigger: _errorCount,
                        child: _LoginCard(
                          formKey: _form,
                          email: _email,
                          password: _password,
                          passwordFocus: _passwordFocus,
                          obscure: _obscure,
                          busy: admin.isBusy,
                          error: _error,
                          notice: _notice,
                          onToggleObscure: () =>
                              setState(() => _obscure = !_obscure),
                          onSubmit: _signIn,
                        ),
                      ),
                    ),
                    if (admin.isDemo) ...[
                      const SizedBox(height: AppSpacing.lg),
                      FadeSlideIn(
                        index: 3,
                        child: _DemoAccounts(onPick: _useDemo),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.floating,
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
              Text(
                'For restaurant staff only.',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (notice != null) ...[
                _Banner(text: notice!, color: AppColors.info),
                const SizedBox(height: AppSpacing.md),
              ],
              AnimatedSize(
                duration: Motion.of(context, Motion.medium),
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
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Sign in',
                icon: Icons.login_rounded,
                isLoading: busy,
                onPressed: busy ? null : onSubmit,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Sessions end automatically after 8 hours. Repeated failed '
                'attempts lock sign-in for a minute.',
                textAlign: TextAlign.center,
                style: AppTypography.caption,
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
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                    color: Colors.white,
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
              color: Colors.white.withValues(alpha: 0.8),
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
                      color: Colors.white,
                      borderRadius: AppRadii.pill,
                    ),
                    child: Text(
                      account.role.label,
                      style: AppTypography.label.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
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
