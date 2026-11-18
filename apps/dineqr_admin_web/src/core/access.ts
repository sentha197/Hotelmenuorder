import { parseInstant, parseOptionalInstant } from './time';

/**
 * Actions and data a staff member may access. The server authorises every
 * request by the account's role; the app mirrors it so screens show only
 * what a person can use (hiding a button is never the only guard).
 */
export type Permission =
  | 'viewDashboard'
  | 'viewFinancials'
  | 'viewOrders'
  | 'createOrders'
  | 'manageKitchen'
  | 'serveOrders'
  | 'cancelOrders'
  | 'viewMenu'
  | 'manageMenu'
  | 'manageCategories'
  | 'manageOffers'
  | 'viewTables'
  | 'manageTables'
  | 'viewBills'
  | 'collectPayments'
  | 'viewPayments'
  | 'reconcilePayments'
  | 'issueRefunds'
  | 'viewReports'
  | 'exportReports'
  | 'manageInventory'
  | 'manageStaff'
  | 'manageSettings'
  | 'viewAuditLog';

interface PermissionInfo {
  label: string;
  /** The permission whose screen this one's action lives on. */
  requires?: Permission;
}

export const permissionInfo: Record<Permission, PermissionInfo> = {
  viewDashboard: { label: 'View dashboard' },
  viewFinancials: { label: 'View revenue and financial figures' },
  viewOrders: { label: 'View orders' },
  createOrders: { label: 'Create orders for tables', requires: 'viewOrders' },
  manageKitchen: { label: 'Accept and prepare orders' },
  serveOrders: { label: 'Mark orders served' },
  cancelOrders: { label: 'Cancel orders', requires: 'viewOrders' },
  viewMenu: { label: 'View menu' },
  manageMenu: { label: 'Edit dishes and prices', requires: 'viewMenu' },
  manageCategories: { label: 'Edit categories', requires: 'viewMenu' },
  manageOffers: { label: 'Run offers, combos and coupons' },
  viewTables: { label: 'View tables' },
  manageTables: { label: 'Edit tables and QR codes', requires: 'viewTables' },
  viewBills: { label: 'View bills' },
  collectPayments: { label: 'Record payments', requires: 'viewBills' },
  viewPayments: { label: 'View payment history' },
  reconcilePayments: { label: 'Reconcile pending payments', requires: 'viewBills' },
  issueRefunds: { label: 'Issue refunds', requires: 'viewBills' },
  viewReports: { label: 'View reports' },
  exportReports: { label: 'Export reports', requires: 'viewReports' },
  manageInventory: { label: 'Manage inventory' },
  manageStaff: { label: 'Manage staff and roles' },
  manageSettings: { label: 'Change restaurant settings' },
  viewAuditLog: { label: 'View activity log' },
};

/** Every permission, in the server's (and the Flutter enum's) order. */
export const allPermissions = Object.keys(permissionInfo) as Permission[];

/** The permissions named in [names] (unknown names are ignored), in order. */
export function parsePermissions(names: readonly unknown[]): Set<Permission> {
  const wanted = new Set(names);
  return new Set(allPermissions.filter((p) => wanted.has(p)));
}

export type StaffRole = 'owner' | 'manager' | 'cashier' | 'kitchen' | 'waiter' | 'accountant' | 'custom';

export const staffRoles: readonly StaffRole[] = ['owner', 'manager', 'cashier', 'kitchen', 'waiter', 'accountant', 'custom'];

export const roleInfo: Record<StaffRole, { label: string; description: string }> = {
  owner: { label: 'Owner', description: 'Full access to every module and setting.' },
  manager: { label: 'Manager', description: 'Orders, kitchen, menu, tables, inventory and operations.' },
  cashier: { label: 'Cashier', description: 'Counter orders (POS), bills, payments, receipts and reconciliation.' },
  kitchen: { label: 'Kitchen staff', description: 'Kitchen queue: accept, prepare and mark ready.' },
  waiter: { label: 'Service staff', description: 'Tables, orders, serving and bill access.' },
  accountant: { label: 'Accountant', description: 'Financial reports, bills, refunds and exports.' },
  custom: { label: 'Custom role', description: 'Only what the owner chooses. Starts with no access.' },
};

/** Longest name an owner can give a custom role. */
export const MAX_ROLE_TITLE = 30;

const rolePermissions: Record<StaffRole, readonly Permission[]> = {
  owner: allPermissions,
  manager: [
    'viewDashboard',
    'viewOrders',
    'createOrders',
    'manageKitchen',
    'serveOrders',
    'cancelOrders',
    'viewMenu',
    'manageMenu',
    'manageCategories',
    'manageOffers',
    'viewTables',
    'manageTables',
    'viewBills',
    'collectPayments',
    'viewPayments',
    'viewReports',
    'manageInventory',
    'viewAuditLog',
  ],
  cashier: ['viewDashboard', 'viewOrders', 'createOrders', 'viewBills', 'collectPayments', 'viewPayments', 'reconcilePayments', 'viewTables'],
  kitchen: ['viewOrders', 'manageKitchen', 'viewMenu'],
  waiter: ['viewOrders', 'createOrders', 'serveOrders', 'viewMenu', 'viewTables', 'viewBills'],
  accountant: [
    'viewDashboard',
    'viewFinancials',
    'viewOrders',
    'viewBills',
    'viewPayments',
    'reconcilePayments',
    'issueRefunds',
    'viewReports',
    'exportReports',
    'viewAuditLog',
  ],
  custom: [],
};

export const permissionsOfRole = (role: StaffRole): Set<Permission> => new Set(rolePermissions[role]);

export function parseRole(name: unknown): StaffRole {
  return staffRoles.includes(name as StaffRole) ? (name as StaffRole) : 'waiter';
}

/**
 * What a typed role name means: a built-in role (matched by its label or
 * key, ignoring case and spaces), otherwise a custom role with that name.
 * Null when the name is too short or too long to be a role name.
 */
export function roleFromText(text: string): { role: StaffRole; title: string | null } | null {
  const squash = (s: string) => s.toLowerCase().replace(/\s+/g, '');
  const name = text.trim();
  const typed = squash(name);
  for (const role of staffRoles) {
    if (role === 'custom') continue;
    if (typed === squash(roleInfo[role].label) || typed === squash(role)) return { role, title: null };
  }
  if (name.length < 2 || name.length > MAX_ROLE_TITLE) return null;
  return { role: 'custom', title: name };
}

/** A staff account as the API returns it (never with a password hash). */
export interface StaffAccount {
  id: string;
  name: string;
  /** Lower-case login email. */
  email: string;
  role: StaffRole;
  /** The owner's name for a custom role, e.g. "Officer". */
  roleTitle: string | null;
  createdAt: Date;
  isActive: boolean;
  lastLoginAt: Date | null;
  /** What the owner chose instead of the role's permissions; null = role defaults. */
  customPermissions: Set<Permission> | null;
}

export function staffFromApi(json: Record<string, unknown>): StaffAccount {
  return {
    id: String(json.id),
    name: String(json.name ?? ''),
    email: String(json.email ?? ''),
    role: parseRole(json.role),
    roleTitle: typeof json.roleTitle === 'string' ? json.roleTitle : null,
    createdAt: parseInstant(json.createdAt),
    isActive: (json.active as boolean | undefined) ?? true,
    lastLoginAt: parseOptionalInstant(json.lastLogin),
    // `permissions` is what the server allows this person; it differs from
    // the role's only when the owner customised it.
    customPermissions: json.customAccess === true && Array.isArray(json.permissions) ? parsePermissions(json.permissions) : null,
  };
}

export const Staff = {
  /** The owner's name for a custom role, otherwise the role's own label. */
  roleLabel: (s: StaffAccount) => (s.role === 'custom' && s.roleTitle ? s.roleTitle : roleInfo[s.role].label),
  /** Owners always have everything. */
  hasCustomAccess: (s: StaffAccount) => s.role !== 'owner' && s.customPermissions != null,
  permissions: (s: StaffAccount): Set<Permission> => (Staff.hasCustomAccess(s) ? s.customPermissions! : permissionsOfRole(s.role)),
  can: (s: StaffAccount, permission: Permission) => s.isActive && Staff.permissions(s).has(permission),
};

/** A sensitive action recorded for accountability (written by the server). */
export interface AuditEvent {
  id: string;
  at: Date;
  actorId: string;
  actorName: string;
  actorRole: string;
  /** Machine-readable action, e.g. `order.status`, `payment.refund`. */
  action: string;
  summary: string;
  targetId: string;
}

export function auditFromJson(json: Record<string, unknown>): AuditEvent {
  return {
    id: String(json.id),
    at: parseInstant(json.at),
    actorId: String(json.actor ?? ''),
    actorName: String(json.name ?? ''),
    actorRole: String(json.role ?? ''),
    action: String(json.action ?? ''),
    summary: String(json.summary ?? ''),
    targetId: String(json.target ?? ''),
  };
}

/** Thrown when the signed-in staff member may not perform an action. */
export class PermissionDeniedError extends Error {
  constructor(readonly permission: Permission) {
    super(`You do not have permission to ${permissionInfo[permission].label.toLowerCase()}.`);
  }
}

/** Thrown when an admin action runs without a valid session. */
export class SessionExpiredError extends Error {
  constructor() {
    super('Your session has ended. Please sign in again.');
  }
}

/** A rejected change, with a message for the form. */
export class ValidationError extends Error {}

/** A payment that cannot go ahead, with a message for staff. */
export class PaymentError extends Error {}

/** Password rule for new and reset passwords (same as the server). */
export function passwordProblem(password: string): string | null {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) return 'Use letters and numbers.';
  return null;
}

/** Groups shown in the access editor. */
export const accessGroups: readonly (readonly [string, readonly Permission[]])[] = [
  ['Orders and kitchen', ['viewOrders', 'createOrders', 'manageKitchen', 'serveOrders', 'cancelOrders']],
  ['Menu and tables', ['viewMenu', 'manageMenu', 'manageCategories', 'manageOffers', 'viewTables', 'manageTables']],
  ['Bills and payments', ['viewBills', 'collectPayments', 'viewPayments', 'reconcilePayments', 'issueRefunds']],
  ['Dashboard and reports', ['viewDashboard', 'viewFinancials', 'viewReports', 'exportReports']],
  ['Administration', ['manageInventory', 'manageSettings', 'manageStaff', 'viewAuditLog']],
];

export const accessNotes: Partial<Record<Permission, string>> = {
  manageStaff: 'Can add staff and reset their passwords. Owner accounts stay protected.',
  viewFinancials: 'Needed to see revenue figures.',
};
