import {
  BadgePercent,
  Briefcase,
  ChartColumn,
  ChefHat,
  ConciergeBell,
  Crown,
  FileText,
  History,
  IdCard,
  Landmark,
  LayoutDashboard,
  Package,
  QrCode,
  ReceiptText,
  Scale,
  Settings,
  Store,
  UtensilsCrossed,
  type LucideIcon,
} from 'lucide-react';
import { allPermissions, type Permission, type StaffAccount, type StaffRole, Staff } from '@/core/access';

/** Sections of the admin app and the permission each needs (AdminModule). */
export type ModuleId =
  | 'dashboard'
  | 'service'
  | 'orders'
  | 'kitchen'
  | 'bills'
  | 'menu'
  | 'offers'
  | 'tables'
  | 'reports'
  | 'inventory'
  | 'staff'
  | 'settings'
  | 'legal'
  | 'activity';

export interface AdminModule {
  id: ModuleId;
  label: string;
  path: string;
  icon: LucideIcon;
  permission: Permission;
  /** One line for the command bar. */
  hint: string;
}

export const modules: readonly AdminModule[] = [
  { id: 'dashboard', label: 'Dashboard', path: '/dashboard', icon: LayoutDashboard, permission: 'viewDashboard', hint: 'Today at a glance' },
  { id: 'service', label: 'Service', path: '/service', icon: ConciergeBell, permission: 'serveOrders', hint: 'Ready to serve and your tables' },
  { id: 'orders', label: 'Orders', path: '/orders', icon: ReceiptText, permission: 'viewOrders', hint: 'Live and past orders' },
  { id: 'kitchen', label: 'Kitchen', path: '/kitchen', icon: ChefHat, permission: 'manageKitchen', hint: 'Kitchen display' },
  { id: 'bills', label: 'Bills', path: '/bills', icon: FileText, permission: 'viewBills', hint: 'Bills paid at the billing counter, and refunds' },
  { id: 'menu', label: 'Menu', path: '/menu', icon: UtensilsCrossed, permission: 'viewMenu', hint: 'Dishes and categories' },
  { id: 'offers', label: 'Offers', path: '/offers', icon: BadgePercent, permission: 'manageOffers', hint: 'Special offers, combos and coupons' },
  { id: 'tables', label: 'Tables & QR', path: '/tables', icon: QrCode, permission: 'viewTables', hint: 'Tables, takeaway and QR codes' },
  { id: 'reports', label: 'Reports', path: '/reports', icon: ChartColumn, permission: 'viewReports', hint: 'Sales, taxes and exports' },
  { id: 'inventory', label: 'Inventory', path: '/inventory', icon: Package, permission: 'manageInventory', hint: 'Stock and adjustments' },
  { id: 'staff', label: 'Staff', path: '/staff', icon: IdCard, permission: 'manageStaff', hint: 'Accounts, roles and access' },
  { id: 'settings', label: 'Settings', path: '/settings', icon: Settings, permission: 'manageSettings', hint: 'Restaurant, billing counter and restrictions' },
  { id: 'legal', label: 'Terms & Privacy', path: '/legal', icon: Scale, permission: 'manageSettings', hint: 'Documents and acceptances' },
  { id: 'activity', label: 'Activity log', path: '/activity', icon: History, permission: 'viewAuditLog', hint: 'Who did what, and when' },
];

export const moduleById = (id: ModuleId) => modules.find((m) => m.id === id)!;

/**
 * How a role's workspace is presented: its name, icon and module order (its
 * main work first). Presentation only: what a role may do is its
 * permissions, enforced by the server.
 */
export const workspaces: Record<StaffRole, { title: string; icon: LucideIcon; order: ModuleId[] }> = {
  owner: {
    title: 'Owner',
    icon: Crown,
    order: ['dashboard', 'orders', 'kitchen', 'bills', 'service', 'menu', 'offers', 'tables', 'reports', 'inventory', 'staff', 'settings', 'legal', 'activity'],
  },
  manager: {
    title: 'Operations',
    icon: Briefcase,
    order: ['dashboard', 'orders', 'kitchen', 'service', 'tables', 'menu', 'offers', 'inventory', 'bills', 'reports', 'activity'],
  },
  // No set order: whatever the owner switched on, in the usual order.
  custom: { title: 'Custom', icon: IdCard, order: [] },
  cashier: { title: 'Counter', icon: Store, order: ['bills', 'orders', 'tables', 'dashboard'] },
  kitchen: { title: 'Kitchen', icon: ChefHat, order: ['kitchen', 'orders', 'menu'] },
  waiter: { title: 'Service', icon: ConciergeBell, order: ['service', 'orders', 'tables', 'bills', 'menu'] },
  accountant: { title: 'Finance', icon: Landmark, order: ['dashboard', 'reports', 'bills', 'orders', 'activity'] },
};

/**
 * Modules a staff member can open, in their role's order (AdminModule.forRole).
 * The first one is where they land after signing in.
 */
export function modulesFor(staff: StaffAccount): AdminModule[] {
  const granted = Staff.permissions(staff);
  const allowed = new Set(modules.filter((m) => granted.has(m.permission)).map((m) => m.id));
  const ordered: AdminModule[] = [];
  for (const id of workspaces[staff.role].order) {
    if (allowed.delete(id)) ordered.push(moduleById(id));
  }
  // Anything permitted but not placed in the role's order still shows.
  for (const m of modules) if (allowed.has(m.id)) ordered.push(m);
  return ordered;
}

/** "Owner workspace", or the custom role's own name. */
export const workspaceTitle = (staff: StaffAccount) => (staff.role === 'custom' ? Staff.roleLabel(staff) : workspaces[staff.role].title);

export const everyPermission = allPermissions;
