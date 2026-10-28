import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../state/staff_controller.dart';
import '../../widgets/admin_widgets.dart';
import 'access_dialog.dart';

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
    final custom = result.role == StaffRole.custom;
    StaffAccount? created;
    final added = await runAdminAction(
      context,
      () async {
        created = await context.read<StaffController>().addStaff(
          name: result.name,
          email: result.email,
          role: result.role,
          roleTitle: result.roleTitle,
          password: result.password,
        );
      },
      success: custom
          ? '${result.name} added. Now choose what they can access.'
          : '${result.name} added. Share the temporary password privately.',
    );
    // A role with its own name starts with no access, so ask for it now.
    final account = created;
    if (added && custom && account != null && context.mounted) {
      await _chooseAccess(context, account);
    }
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

/// Lets the owner choose what [account] may do, and saves it.
Future<void> _chooseAccess(BuildContext context, StaffAccount account) async {
  final permissions = await showAccessDialog(context, account);
  if (permissions == null || !context.mounted) return;
  await runAdminAction(
    context,
    () => context.read<StaffController>().changeAccess(account.id, permissions),
    success: 'Access updated for ${account.name}',
  );
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
          // The last option is any name the owner types (e.g. "Officer").
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
                        Text(
                          role == StaffRole.custom
                              ? (account.role == StaffRole.custom
                                    ? '${account.roleLabel} (rename)'
                                    : 'Another name…')
                              : role.label,
                          style: AppTypography.cardTitle,
                        ),
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

    var target = role;
    String? title;
    if (role == StaffRole.custom) {
      final typed = await askForText(
        context,
        title: 'Role name for ${account.name}',
        label: 'Role name, e.g. Officer',
        confirmLabel: 'Save',
        minLength: 2,
        maxLength: StaffRole.maxTitleLength,
      );
      // Typing a standard role's name picks that role.
      final named = typed == null ? null : StaffRole.fromText(typed);
      if (named == null || !context.mounted) return;
      target = named.role;
      title = named.title;
    }
    final staff = context.read<StaffController>();
    final changed = await runAdminAction(
      context,
      () => staff.changeRole(account.id, target, roleTitle: title),
      success: '${account.name} is now ${title ?? target.label}',
    );
    // A custom role begun from another role starts with no access.
    final updated = staff.byId(account.id);
    if (changed &&
        target == StaffRole.custom &&
        account.role != StaffRole.custom &&
        updated != null &&
        context.mounted) {
      await _chooseAccess(context, updated);
    }
  }

  Future<void> _changeAccess(BuildContext context) =>
      _chooseAccess(context, account);

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
                        account.roleLabel,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.orangeText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (account.hasCustomAccess)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softWhite,
                          borderRadius: AppRadii.pill,
                        ),
                        child: Text(
                          'Custom access',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
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
              if (value == 'access') _changeAccess(context);
              if (value == 'password') _resetPassword(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'role', child: Text('Change role')),
              // Owners always have full access, so there is nothing to change.
              PopupMenuItem(
                value: 'access',
                enabled: account.role != StaffRole.owner,
                child: const Text('Change access'),
              ),
              const PopupMenuItem(
                value: 'password',
                child: Text('Reset password'),
              ),
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
          // A custom role has no permissions of its own to describe.
          for (final role in StaffRole.values.where(
            (r) => r != StaffRole.custom,
          ))
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
  const _NewStaff(
    this.name,
    this.email,
    this.role,
    this.roleTitle,
    this.password,
  );

  final String name;
  final String email;
  final StaffRole role;

  /// The typed name of a custom role; null for a standard role.
  final String? roleTitle;
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
  final _role = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _role.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final weak = PasswordHasher.validateNew(_password.text);
    // A standard role's name picks that role; any other name is a custom role.
    final role = StaffRole.fromText(_role.text);
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter a name.');
    } else if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
    } else if (role == null) {
      setState(
        () => _error =
            'Role name must be 2 to ${StaffRole.maxTitleLength} characters.',
      );
    } else if (weak != null) {
      setState(() => _error = weak);
    } else {
      Navigator.pop(
        context,
        _NewStaff(
          _name.text,
          _email.text,
          role.role,
          role.title,
          _password.text,
        ),
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
              TextField(
                controller: _role,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Role',
                  helperText:
                      'Type any name, e.g. Officer; you choose its access '
                      'next. Standard roles: ${StaffRole.values.where((r) => r != StaffRole.custom).map((r) => r.label).join(', ')}.',
                  helperMaxLines: 5,
                ),
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
