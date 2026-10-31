import { useLayoutEffect, type ComponentType } from 'react';
import { Outlet, ScrollRestoration, useLocation, type RouteObject } from 'react-router';
import { Ambient } from '../components/Ambient';
import { Toaster } from '../components/Toaster';
import { QrLoader } from '../components/ui';
import { ScannerPage } from '../pages/ScannerPage';
import { OrderingGuard, PageTransition, RootEntry, Shell } from '../pages/Shell';
import { TableEntryPage } from '../pages/TableEntryPage';
import { lockTheme } from '../theme';
import { paths } from './paths';

/** The brand page (/about) was designed dark: it stays dark in either theme. */
function ThemeScope() {
  const about = useLocation().pathname === paths.about;
  useLayoutEffect(() => {
    lockTheme(about ? 'dark' : null);
  }, [about]);
  return null;
}

function RootLayout() {
  return (
    <>
      <ThemeScope />
      <Ambient />
      <Outlet />
      <Toaster />
      <ScrollRestoration />
    </>
  );
}

/** Shown while a page's code loads on a cold start. */
function Loading() {
  return (
    <div className="entry entry--center">
      <QrLoader size={34} label="Loading" />
    </div>
  );
}

/** Ordering screens outside the tabs: they need the guest session too. */
function Guarded() {
  return (
    <OrderingGuard>
      <PageTransition>
        <Outlet />
      </PageTransition>
    </OrderingGuard>
  );
}

/**
 * Pages load on first use, so the scanner (the first screen of a direct
 * visit) and the table entry never wait for the menu or payment screens.
 */
const page =
  <M,>(load: () => Promise<M>, pick: (module: M) => ComponentType) =>
  async () => ({ Component: pick(await load()) });

const menu = () => import('../pages/MenuPage');
const orders = () => import('../pages/OrderPages');
const bills = () => import('../pages/BillPages');
const misc = () => import('../pages/MiscPages');

export const routes: RouteObject[] = [
  {
    element: <RootLayout />,
    hydrateFallbackElement: <Loading />,
    children: [
      // Direct visits: the scanner first (or a recent session resumes).
      { path: '/', element: <RootEntry /> },
      { path: '/scan', element: <ScannerPage /> },
      // What a table's QR code opens (Google Lens, the phone camera).
      { path: '/t/:table', element: <TableEntryPage /> },
      { path: '/takeaway', element: <TableEntryPage takeaway /> },
      {
        element: <Shell />,
        children: [
          { path: '/home', lazy: page(() => import('../pages/HomePage'), (m) => m.HomePage) },
          { path: '/menu', lazy: page(menu, (m) => m.MenuPage) },
          { path: '/cart', lazy: page(() => import('../pages/CartPage'), (m) => m.CartPage) },
          { path: '/orders', lazy: page(orders, (m) => m.OrdersPage) },
          { path: '/more', lazy: page(misc, (m) => m.MorePage) },
        ],
      },
      {
        element: <Guarded />,
        children: [
          { path: '/favorites', lazy: page(menu, (m) => () => <m.MenuPage favoritesOnly />) },
          { path: '/dish/:itemId', lazy: page(() => import('../pages/DishPage'), (m) => m.DishPage) },
          { path: '/checkout', lazy: page(() => import('../pages/CheckoutPage'), (m) => m.CheckoutPage) },
          { path: '/orders/:orderId', lazy: page(orders, (m) => m.OrderDetailsPage) },
          { path: '/orders/:orderId/placed', lazy: page(orders, (m) => m.OrderPlacedPage) },
          { path: '/orders/:orderId/track', lazy: page(orders, (m) => m.TrackingPage) },
          { path: '/bills/:invoiceId', lazy: page(bills, (m) => m.BillPage) },
          { path: '/bills/:invoiceId/pay', lazy: page(() => import('../pages/PaymentPage'), (m) => m.PaymentPage) },
          { path: '/bills/:invoiceId/split', lazy: page(() => import('../pages/SplitPaymentPage'), (m) => m.SplitPaymentPage) },
          { path: '/bills/:invoiceId/receipt', lazy: page(bills, (m) => m.ReceiptPage) },
          { path: '/payments', lazy: page(bills, (m) => m.PaymentHistoryPage) },
        ],
      },
      { path: '/credits', lazy: page(misc, (m) => m.CreditsPage) },
      { path: '/about', lazy: page(() => import('../pages/AboutPage'), (m) => m.AboutPage) },
      { path: '*', lazy: page(misc, (m) => m.NotFoundPage) },
    ],
  },
];
