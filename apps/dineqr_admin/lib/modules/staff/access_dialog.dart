import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';

/// How the access editor lists permissions. Every [Permission] appears in
/// exactly one group (a test checks it, so a new permission is not forgotten).
const accessGroups = <(String, List<Permission>)>[
  (
    'Orders and kitchen',
    [
      Permission.viewOrders,
      Permission.createOrders,
      Permission.manageKitchen,
      Permission.serveOrders,
      Permission.cancelOrders,
    ],
  ),
  (
    'Menu and tables',
    [
      Permission.viewMenu,
      Permission.manageMenu,
      Permission.manageCategories,
      Permission.viewTables,
      Permission.manageTables,
    ],
  ),
  (
    'Bills and payments',
    [
      Permission.viewBills,
      Permission.collectPayments,
      Permission.viewPayments,
      Permission.reconcilePayments,
      Permission.issueRefunds,
    ],
  ),
  (
    'Dashboard and reports',
    [
      Permission.viewDashboard,
      Permission.viewFinancials,
      Permission.viewReports,
      Permission.exportReports,
    ],
  ),
  (
    'Administration',
    [
      Permission.manageInventory,
      Permission.manageSettings,
      Permission.manageStaff,
      Permission.viewAuditLog,
    ],
  ),
];

const _notes = {
  Permission.manageStaff:
      'Can add staff and reset their passwords. Owner accounts stay protected.',
  Permission.viewFinancials: 'Needed to see revenue figures.',
};

/// Asks the owner what [account] may do. Returns the chosen permissions, or
/// null if the dialog was cancelled.
Future<Set<Permission>?> showAccessDialog(
  BuildContext context,
  StaffAccount account,
) => showDialog<Set<Permission>>(
  context: context,
  builder: (_) => AccessDialog(account: account),
);

class AccessDialog extends StatefulWidget {
  const AccessDialog({required this.account, super.key});

  final StaffAccount account;

  @override
  State<AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<AccessDialog> {
  late final Set<Permission> _selected = {...widget.account.permissions};

  StaffRole get _role => widget.account.role;

  static bool _dependsOn(Permission permission, Permission other) {
    for (var need = permission.requires; need != null; need = need.requires) {
      if (need == other) return true;
    }
    return false;
  }

  void _toggle(Permission permission, bool on) => setState(() {
    if (on) {
      _selected.add(permission);
      // An action is no use without the screen it lives on.
      for (var need = permission.requires; need != null; need = need.requires) {
        _selected.add(need);
      }
    } else {
      _selected.remove(permission);
      _selected.removeWhere((other) => _dependsOn(other, permission));
    }
  });

  void _useRoleDefaults() => setState(() {
    _selected
      ..clear()
      ..addAll(_role.permissions);
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Access for ${widget.account.name}',
        style: AppTypography.sectionTitle,
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _role == StaffRole.custom
                    ? 'Nothing is allowed until you switch it on. Switch on '
                          'what this person needs.'
                    : 'Starts from what a ${_role.label} can do. Switch '
                          'anything on or off for this person.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Wraps instead of overflowing on a small phone at large text.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_selected.length} of ${Permission.values.length} allowed',
                    style: AppTypography.cardTitle,
                  ),
                  TextButton(
                    onPressed: _useRoleDefaults,
                    child: Text(
                      _role == StaffRole.custom
                          ? 'Clear all'
                          : 'Reset to ${_role.label}',
                    ),
                  ),
                ],
              ),
              for (final (title, permissions) in accessGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    title,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final permission in permissions)
                  SwitchListTile(
                    key: ValueKey('access-${permission.name}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.success,
                    title: Text(permission.label),
                    subtitle: _notes[permission] == null
                        ? null
                        : Text(
                            _notes[permission]!,
                            style: AppTypography.caption,
                          ),
                    value: _selected.contains(permission),
                    onChanged: (on) => _toggle(permission, on),
                  ),
              ],
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
          onPressed: () => Navigator.pop(context, {..._selected}),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
