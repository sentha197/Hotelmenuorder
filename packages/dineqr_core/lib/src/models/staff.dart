/// Actions and data a staff member may access. Checked in the state layer
/// for every privileged action, not only by hiding navigation.
enum Permission {
  viewDashboard('View dashboard'),
  viewFinancials('View revenue and financial figures'),
  viewOrders('View orders'),
  createOrders('Create orders for tables', requires: Permission.viewOrders),
  manageKitchen('Accept and prepare orders'),
  serveOrders('Mark orders served'),
  cancelOrders('Cancel orders', requires: Permission.viewOrders),
  viewMenu('View menu'),
  manageMenu('Edit dishes and prices', requires: Permission.viewMenu),
  manageCategories('Edit categories', requires: Permission.viewMenu),
  viewTables('View tables'),
  manageTables('Edit tables and QR codes', requires: Permission.viewTables),
  viewBills('View bills'),
  collectPayments('Record payments', requires: Permission.viewBills),
  viewPayments('View payment history'),
  reconcilePayments(
    'Reconcile pending payments',
    requires: Permission.viewBills,
  ),
  issueRefunds('Issue refunds', requires: Permission.viewBills),
  viewReports('View reports'),
  exportReports('Export reports', requires: Permission.viewReports),
  manageInventory('Manage inventory'),
  manageStaff('Manage staff and roles'),
  manageSettings('Change restaurant settings'),
  viewAuditLog('View activity log');

  const Permission(this.label, {this.requires});

  final String label;

  /// The permission whose screen this one's action lives on. Without it the
  /// person could not reach the action, so the access editor switches the two
  /// together.
  final Permission? requires;

  /// The permissions named in [names] (unknown names are ignored).
  static Set<Permission> parseAll(Iterable<Object?> names) {
    final wanted = names.toSet();
    return {
      for (final permission in values)
        if (wanted.contains(permission.name)) permission,
    };
  }
}

enum StaffRole {
  owner('Owner', 'Full access to every module and setting.'),
  manager(
    'Manager',
    'Orders, kitchen, menu, tables, inventory and operations.',
  ),
  cashier(
    'Cashier',
    'Counter orders (POS), bills, payments, receipts and reconciliation.',
  ),
  kitchen('Kitchen staff', 'Kitchen queue: accept, prepare and mark ready.'),
  waiter('Service staff', 'Tables, orders, serving and bill access.'),
  accountant('Accountant', 'Financial reports, bills, refunds and exports.'),

  /// A role the owner names (e.g. "Officer"). It starts with no access; the
  /// owner switches on what that person needs. See [StaffAccount.roleTitle].
  custom('Custom role', 'Only what the owner chooses. Starts with no access.');

  const StaffRole(this.label, this.description);

  final String label;
  final String description;

  /// Longest name an owner can give a custom role.
  static const maxTitleLength = 30;

  /// What a typed role name means: a built-in role (matched by its label or
  /// key, ignoring case and spaces), otherwise a custom role with that name.
  /// Null when the name is too short or too long to be a role name.
  static ({StaffRole role, String? title})? fromText(String text) {
    String squash(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final name = text.trim();
    final typed = squash(name);
    for (final role in values) {
      if (role == custom) continue;
      if (typed == squash(role.label) || typed == squash(role.name)) {
        return (role: role, title: null);
      }
    }
    if (name.length < 2 || name.length > maxTitleLength) return null;
    return (role: custom, title: name);
  }

  Set<Permission> get permissions => switch (this) {
    StaffRole.owner => Permission.values.toSet(),
    StaffRole.manager => const {
      Permission.viewDashboard,
      Permission.viewOrders,
      Permission.createOrders,
      Permission.manageKitchen,
      Permission.serveOrders,
      Permission.cancelOrders,
      Permission.viewMenu,
      Permission.manageMenu,
      Permission.manageCategories,
      Permission.viewTables,
      Permission.manageTables,
      Permission.viewBills,
      Permission.collectPayments,
      Permission.viewPayments,
      Permission.viewReports,
      Permission.manageInventory,
      Permission.viewAuditLog,
    },
    StaffRole.cashier => const {
      Permission.viewDashboard,
      Permission.viewOrders,
      // Counter orders at the POS.
      Permission.createOrders,
      Permission.viewBills,
      Permission.collectPayments,
      Permission.viewPayments,
      Permission.reconcilePayments,
      Permission.viewTables,
    },
    StaffRole.kitchen => const {
      Permission.viewOrders,
      Permission.manageKitchen,
      Permission.viewMenu,
    },
    StaffRole.waiter => const {
      Permission.viewOrders,
      Permission.createOrders,
      Permission.serveOrders,
      Permission.viewMenu,
      Permission.viewTables,
      Permission.viewBills,
    },
    StaffRole.accountant => const {
      Permission.viewDashboard,
      Permission.viewFinancials,
      Permission.viewOrders,
      Permission.viewBills,
      Permission.viewPayments,
      Permission.reconcilePayments,
      Permission.issueRefunds,
      Permission.viewReports,
      Permission.exportReports,
      Permission.viewAuditLog,
    },
    StaffRole.custom => const {},
  };

  bool can(Permission permission) => permissions.contains(permission);

  static StaffRole parse(String? name) => StaffRole.values.firstWhere(
    (role) => role.name == name,
    orElse: () => StaffRole.waiter,
  );
}

/// A staff login. Only a salted hash of the password is stored.
class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.passwordHash,
    required this.salt,
    required this.createdAt,
    this.isActive = true,
    this.lastLoginAt,
    this.customPermissions,
    this.roleTitle,
  });

  factory StaffAccount.fromJson(Map<String, dynamic> json) => StaffAccount(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    role: StaffRole.parse(json['role'] as String?),
    passwordHash: json['hash'] as String,
    salt: json['salt'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    isActive: json['active'] as bool? ?? true,
    lastLoginAt: json['lastLogin'] == null
        ? null
        : DateTime.parse(json['lastLogin'] as String),
    customPermissions: json['access'] == null
        ? null
        : Permission.parseAll(json['access'] as List<dynamic>),
    roleTitle: json['title'] as String?,
  );

  final String id;
  final String name;

  /// Lower-case login email.
  final String email;
  final StaffRole role;
  final String passwordHash;
  final String salt;
  final DateTime createdAt;
  final bool isActive;
  final DateTime? lastLoginAt;

  /// What the owner chose for this person instead of their role's
  /// permissions; null means the role's defaults apply.
  final Set<Permission>? customPermissions;

  /// The owner's name for a [StaffRole.custom] role, e.g. "Officer".
  final String? roleTitle;

  /// What to call this person's role: the owner's name for a custom role,
  /// otherwise the role's own label.
  String get roleLabel =>
      role == StaffRole.custom && (roleTitle ?? '').isNotEmpty
      ? roleTitle!
      : role.label;

  /// Owners always have everything.
  bool get hasCustomAccess =>
      role != StaffRole.owner && customPermissions != null;

  /// What this person may do: their custom access, or their role's.
  Set<Permission> get permissions =>
      hasCustomAccess ? customPermissions! : role.permissions;

  bool can(Permission permission) =>
      isActive && permissions.contains(permission);

  /// A new [role] starts from that role's own permissions, so custom access
  /// and any custom role name are dropped unless [customPermissions] or
  /// [roleTitle] is given (both are kept when the role is unchanged).
  /// [clearCustomPermissions] goes back to the role's defaults.
  StaffAccount copyWith({
    String? name,
    StaffRole? role,
    String? roleTitle,
    bool? isActive,
    DateTime? lastLoginAt,
    String? passwordHash,
    String? salt,
    Set<Permission>? customPermissions,
    bool clearCustomPermissions = false,
  }) => StaffAccount(
    id: id,
    name: name ?? this.name,
    email: email,
    role: role ?? this.role,
    passwordHash: passwordHash ?? this.passwordHash,
    salt: salt ?? this.salt,
    createdAt: createdAt,
    isActive: isActive ?? this.isActive,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    customPermissions:
        customPermissions ??
        (clearCustomPermissions || (role != null && role != this.role)
            ? null
            : this.customPermissions),
    roleTitle:
        roleTitle ??
        (role != null && role != this.role ? null : this.roleTitle),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    if (roleTitle != null) 'title': roleTitle,
    'hash': passwordHash,
    'salt': salt,
    'createdAt': createdAt.toIso8601String(),
    'active': isActive,
    if (lastLoginAt != null) 'lastLogin': lastLoginAt!.toIso8601String(),
    if (customPermissions != null)
      'access': [
        for (final p in Permission.values)
          if (customPermissions!.contains(p)) p.name,
      ],
  };
}

/// A signed-in staff session. Expires after a fixed period.
class AdminSession {
  const AdminSession({
    required this.staffId,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory AdminSession.fromJson(Map<String, dynamic> json) => AdminSession(
    staffId: json['staff'] as String,
    issuedAt: DateTime.parse(json['issued'] as String),
    expiresAt: DateTime.parse(json['expires'] as String),
  );

  final String staffId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
    'staff': staffId,
    'issued': issuedAt.toIso8601String(),
    'expires': expiresAt.toIso8601String(),
  };
}

/// A sensitive action recorded for accountability.
class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.at,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.summary,
    this.targetId = '',
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
    id: json['id'] as String,
    at: DateTime.parse(json['at'] as String),
    actorId: json['actor'] as String? ?? '',
    actorName: json['name'] as String? ?? '',
    actorRole: json['role'] as String? ?? '',
    action: json['action'] as String,
    summary: json['summary'] as String? ?? '',
    targetId: json['target'] as String? ?? '',
  );

  final String id;
  final DateTime at;
  final String actorId;
  final String actorName;
  final String actorRole;

  /// Machine-readable action, e.g. `order.status`, `payment.refund`.
  final String action;

  /// Human-readable description.
  final String summary;
  final String targetId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'actor': actorId,
    'name': actorName,
    'role': actorRole,
    'action': action,
    'summary': summary,
    if (targetId.isNotEmpty) 'target': targetId,
  };
}
