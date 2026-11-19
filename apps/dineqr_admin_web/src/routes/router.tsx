import { Compass } from 'lucide-react';
import { lazy, Suspense, useEffect, type ComponentType, type LazyExoticComponent, type ReactNode } from 'react';
import { Navigate, Outlet, ScrollRestoration, useLocation, type RouteObject } from 'react-router';
import { Button } from '@/components/ui/Button';
import { DialogHost } from '@/components/ui/Dialog';
import { Empty, PageSkeleton, PermissionNotice } from '@/components/ui/Feedback';
import { Toaster } from '@/components/ui/Toast';
import type { Permission } from '@/core/access';
import { AppShell } from '@/layouts/AppShell';
import { LoginScreen, SplashScreen } from '@/pages/auth/AuthPages';
import { queryClient } from '@/state/data';
import { useAccess, useSession } from '@/state/session';
import { modulesFor } from './modules';

/**
 * One home: the splash while the saved session is restored, the sign-in
 * until a valid session exists, then the role's workspace. Deep links land
 * here too, so no module opens without signing in (AdminGate).
 */
function Gate() {
  const { phase } = useSession();
  useEffect(() => {
    // The next staff member starts from fresh data.
    if (phase === 'signedOut') queryClient.clear();
  }, [phase]);
  if (phase === 'restoring' || phase === 'restoreFailed') return <SplashScreen />;
  if (phase === 'signedOut') return <LoginScreen />;
  return <AppShell />;
}

function RootLayout() {
  return (
    <>
      <Gate />
      <DialogHost />
      <Toaster />
      <ScrollRestoration />
    </>
  );
}

/** Lands on the role's main module (the first in its workspace order). */
function Home() {
  const { actor } = useAccess();
  if (!actor) return null;
  const first = modulesFor(actor)[0];
  return first ? <Navigate to={first.path} replace /> : null;
}

/** A page that needs [permission] shows a notice instead for roles without it (AdminGuard). */
function Guarded({ permission, children }: { permission: Permission; children: ReactNode }) {
  const { can } = useAccess();
  if (!can(permission)) return <PermissionNotice permission={permission} />;
  return <Suspense fallback={<div className="mx-auto max-w-7xl px-4 pt-8 sm:px-6 lg:px-8"><PageSkeleton /></div>}>{children}</Suspense>;
}

function NotFound() {
  const location = useLocation();
  return (
    <Empty
      icon={Compass}
      title="Page not found"
      message={`Nothing lives at ${location.pathname}.`}
      action={
        <Button variant="primary" onClick={() => window.history.length > 1 ? window.history.back() : window.location.assign('/')}>
          Go back
        </Button>
      }
    />
  );
}

type Loader<T> = () => Promise<T>;
const page = <T,>(load: Loader<T>, pick: (m: T) => ComponentType): LazyExoticComponent<ComponentType> => lazy(async () => ({ default: pick(await load()) }));

const dashboard = () => import('@/pages/dashboard/DashboardPage');
const orders = () => import('@/pages/orders/OrdersPages');
const kitchen = () => import('@/pages/kitchen/KitchenPage');
const service = () => import('@/pages/service/ServicePage');
const bills = () => import('@/pages/billing/BillsPages');
const menu = () => import('@/pages/menu/MenuPages');
const offers = () => import('@/pages/offers/OffersPages');
const tables = () => import('@/pages/tables/TablesPages');
const reports = () => import('@/pages/reports/ReportsPage');
const inventory = () => import('@/pages/inventory/InventoryPage');
const staff = () => import('@/pages/staff/StaffPage');
const settings = () => import('@/pages/settings/SettingsPage');
const legal = () => import('@/pages/legal/LegalPages');
const activity = () => import('@/pages/activity/ActivityPage');

const Dashboard = page(dashboard, (m) => m.DashboardPage);
const Orders = page(orders, (m) => m.OrdersPage);
const OrderDetail = page(orders, (m) => m.OrderDetailPage);
const NewOrder = page(orders, (m) => m.NewOrderPage);
const Kitchen = page(kitchen, (m) => m.KitchenPage);
const Service = page(service, (m) => m.ServicePage);
const Bills = page(bills, (m) => m.BillsPage);
const BillDetail = page(bills, (m) => m.BillDetailPage);
const Receipt = page(bills, (m) => m.ReceiptPage);
const Menu = page(menu, (m) => m.MenuPage);
const DishEditor = page(menu, (m) => m.DishEditorPage);
const Offers = page(offers, (m) => m.OffersPage);
const PromotionEditor = page(offers, (m) => m.PromotionEditorPage);
const Tables = page(tables, (m) => m.TablesPage);
const QrSheet = page(tables, (m) => m.QrSheetPage);
const Reports = page(reports, (m) => m.ReportsPage);
const ReportPrint = page(reports, (m) => m.ReportPrintPage);
const Inventory = page(inventory, (m) => m.InventoryPage);
const StaffPage = page(staff, (m) => m.StaffPage);
const Settings = page(settings, (m) => m.SettingsPage);
const Legal = page(legal, (m) => m.LegalPage);
const LegalEditor = page(legal, (m) => m.LegalEditorPage);
const LegalPreview = page(legal, (m) => m.LegalPreviewPage);
const Activity = page(activity, (m) => m.ActivityPage);

const guard = (permission: Permission, Component: ComponentType) => (
  <Guarded permission={permission}>
    <Component />
  </Guarded>
);

export const routes: RouteObject[] = [
  {
    element: <RootLayout />,
    children: [
      {
        element: <Outlet />,
        children: [
          { index: true, element: <Home /> },
          { path: 'dashboard', element: guard('viewDashboard', Dashboard) },
          { path: 'service', element: guard('serveOrders', Service) },
          { path: 'orders', element: guard('viewOrders', Orders) },
          { path: 'orders/new', element: guard('createOrders', NewOrder) },
          { path: 'orders/:orderId', element: guard('viewOrders', OrderDetail) },
          { path: 'kitchen', element: guard('manageKitchen', Kitchen) },
          { path: 'bills', element: guard('viewBills', Bills) },
          { path: 'bills/:invoiceId', element: guard('viewBills', BillDetail) },
          { path: 'bills/:invoiceId/receipt', element: guard('viewBills', Receipt) },
          { path: 'menu', element: guard('viewMenu', Menu) },
          { path: 'menu/dishes/new', element: guard('manageMenu', DishEditor) },
          { path: 'menu/dishes/:itemId', element: guard('manageMenu', DishEditor) },
          { path: 'offers', element: guard('manageOffers', Offers) },
          { path: 'offers/new/:kind', element: guard('manageOffers', PromotionEditor) },
          { path: 'offers/edit/:promotionId', element: guard('manageOffers', PromotionEditor) },
          { path: 'tables', element: guard('viewTables', Tables) },
          { path: 'tables/print', element: guard('viewTables', QrSheet) },
          { path: 'reports', element: guard('viewReports', Reports) },
          { path: 'reports/print', element: guard('exportReports', ReportPrint) },
          { path: 'inventory', element: guard('manageInventory', Inventory) },
          { path: 'staff', element: guard('manageStaff', StaffPage) },
          { path: 'settings', element: guard('manageSettings', Settings) },
          { path: 'legal', element: guard('manageSettings', Legal) },
          { path: 'legal/new/:kind', element: guard('manageSettings', LegalEditor) },
          { path: 'legal/drafts/:versionId', element: guard('manageSettings', LegalEditor) },
          { path: 'legal/versions/:versionId', element: guard('manageSettings', LegalPreview) },
          { path: 'activity', element: guard('viewAuditLog', Activity) },
          { path: '*', element: <NotFound /> },
        ],
      },
    ],
  },
];
