import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../state/staff_controller.dart';
import '../../widgets/admin_widgets.dart';

/// Staff accounts and roles (owner only).
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  @override
  void initState() {
    super.initState();
    // Fresh sign-in times and any changes made on another screen.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<StaffController>().load(),
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<_NewStaff>(
      context: context,
      builder: (_) => const _AddStaffDialog(),
    );
    if (result == null || !context.mounted) return;
    await runAdminAction(
      context,
      () => context.read<StaffController>().addStaff(
        name: result.name,
        email: result.email,
        role: result.role,
        password: result.password,
      ),
      success: '${result.name} added. Share the temporary password privately.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<StaffController>().staff;
    final me = context.watch<AdminSessionController>().actor;
    return AdminPage(
      title: 'Staff & roles',
      subtitle: '${staff.where((s) => s.isActive).length} active accounts',
      actions: [
        PrimaryButton(
          label: 'Add staff',
          icon: Icons.person_add_alt_1_rounded,
          expand: false,
          height: 44,
          onPressed: () => _add(context),
        ),
      ],
      children: [
        Text(
          'Roles decide what each person can see and change. In this offline '
          'demo they are enforced inside the app; a production backend must '
          'enforce them on every request.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final (index, account) in staff.indexed)
          FadeSlideIn(
            key: ValueKey(account.id),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _StaffCard(account: account, isMe: account.id == me?.id),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        const _RoleGuide(),
      ],
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.account, required this.isMe});

  final StaffAccount account;
  final bool isMe;

  Future<void> _changeRole(BuildContext context) async {
    final role = await showDialog<StaffRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          'Role for ${account.name}',
          style: AppTypography.sectionTitle,
        ),
        children: [
          for (final role in StaffRole.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, role),
              child: Row(
                children: [
                  Icon(
                    role == account.role
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(role.label, style: AppTypography.cardTitle),
                        Text(role.description, style: AppTypography.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (role == null || !context.mounted) return;
    await runAdminAction(
      context,
      () => context.read<StaffController>().changeRole(account.id, role),
      success: '${account.name} is now ${role.label}',
    );
  }

  Future<void> _resetPassword(BuildContext context) async {
    final password = await askForText(
      context,
      title: 'New password for ${account.name}',
      label: 'Temporary password (8+ letters and numbers)',
      confirmLabel: 'Set password',
      minLength: 8,
      maxLength: 40,
    );
    if (password == null || !context.mounted) return;
    await runAdminAction(
      context,
      () => context.read<StaffController>().resetPassword(account.id, password),
      success: 'Password updated. Share it privately.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: account.isActive
                ? AppColors.primarySoft
                : AppColors.softWhite,
            child: Text(
              account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
              style: AppTypography.sectionTitle.copyWith(
                color: account.isActive
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and role chip wrap on narrow screens.
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      isMe ? '${account.name} (you)' : account.name,
                      style: AppTypography.cardTitle,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.orangeSoft,
                        borderRadius: AppRadii.pill,
                      ),
                      child: Text(
                        account.role.label,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.orangeText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(account.email, style: AppTypography.caption),
                Text(
                  account.lastLoginAt == null
                      ? 'Never signed in'
                      : 'Last sign-in ${AppFormat.dateTime(account.lastLoginAt!)}',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Switch(
            value: account.isActive,
            activeThumbColor: AppColors.success,
            onChanged: isMe
                ? null
                : (value) => runAdminAction(
                    context,
                    () => context.read<StaffController>().setActive(
                      account.id,
                      value,
                    ),
                    success: value
                        ? '${account.name} activated'
                        : '${account.name} deactivated',
                  ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Staff actions',
            enabled: !isMe,
            onSelected: (value) {
              if (value == 'role') _changeRole(context);
              if (value == 'password') _resetPassword(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'role', child: Text('Change role')),
              PopupMenuItem(value: 'password', child: Text('Reset password')),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleGuide extends StatelessWidget {
  const _RoleGuide();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'What each role can do',
      child: Column(
        children: [
          for (final role in StaffRole.values)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: Text(role.label, style: AppTypography.cardTitle),
              subtitle: Text(role.description, style: AppTypography.caption),
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in Permission.values)
                      if (role.can(p))
                        Chip(
                          label: Text(p.label),
                          labelStyle: AppTypography.caption,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.softWhite,
                          side: BorderSide.none,
                        ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
        ],
      ),
    );
  }
}

class _NewStaff {
  const _NewStaff(this.name, this.email, this.role, this.password);

  final String name;
  final String email;
  final StaffRole role;
  final String password;
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  StaffRole _role = StaffRole.waiter;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final weak = PasswordHasher.validateNew(_password.text);
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter a name.');
    } else if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
    } else if (weak != null) {
      setState(() => _error = weak);
    } else {
      Navigator.pop(
        context,
        _NewStaff(_name.text, _email.text, _role, _password.text),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add staff', style: AppTypography.sectionTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<StaffRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in StaffRole.values)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: (value) => setState(() => _role = value ?? _role),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  helperText: 'At least 8 characters with letters and numbers',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
