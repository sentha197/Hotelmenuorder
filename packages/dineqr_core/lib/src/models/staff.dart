/// Actions and data a staff member may access. Checked in the state layer
/// for every privileged action, not only by hiding navigation.
enum Permission {
  viewDashboard('View dashboard'),
  viewFinancials('View revenue and financial figures'),
  viewOrders('View orders'),
  createOrders('Create orders for tables'),
  manageKitchen('Accept and prepare orders'),
  serveOrders('Mark orders served'),
  cancelOrders('Cancel orders'),
  viewMenu('View menu'),
  manageMenu('Edit dishes and prices'),
  manageCategories('Edit categories'),
  viewTables('View tables'),
  manageTables('Edit tables and QR codes'),
  viewBills('View bills'),
  collectPayments('Record payments'),
  viewPayments('View payment history'),
  reconcilePayments('Reconcile pending payments'),
  issueRefunds('Issue refunds'),
  viewReports('View reports'),
  exportReports('Export reports'),
  manageInventory('Manage inventory'),
  manageStaff('Manage staff and roles'),
  manageSettings('Change restaurant settings'),
  viewAuditLog('View activity log');

  const Permission(this.label);

  final String label;
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
  accountant('Accountant', 'Financial reports, bills, refunds and exports.');

  const StaffRole(this.label, this.description);

  final String label;
  final String description;

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

  bool can(Permission permission) => isActive && role.can(permission);

  StaffAccount copyWith({
    String? name,
    StaffRole? role,
    bool? isActive,
    DateTime? lastLoginAt,
    String? passwordHash,
    String? salt,
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'hash': passwordHash,
    'salt': salt,
    'createdAt': createdAt.toIso8601String(),
    'active': isActive,
    if (lastLoginAt != null) 'lastLogin': lastLoginAt!.toIso8601String(),
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
