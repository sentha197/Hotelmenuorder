import { BookOpen, Home, MoreHorizontal, ReceiptText, ShoppingBag } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import type { ReactNode } from 'react';
import { Navigate, NavLink, Outlet, useLocation } from 'react-router';
import { fade, page } from '../animations/variants';
import { Lockup } from '../components/brand';
import { iconSize, lockupHeight } from '../components/sizes';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useSelect, useStore } from '../state/store';
import { ScannerPage } from './ScannerPage';

/** `/`: a recent session resumes; otherwise the scanner is the first screen. */
export function RootEntry() {
  const { session } = useApp();
  useStore(session);
  if (session.resumableTable != null) return <Navigate to={paths.home} replace />;
  return <ScannerPage />;
}

/**
 * Ordering screens need the guest's server session. Without one (a deep
 * link, an expired session) the guest scans first; a resumed table that
 * stopped taking orders goes back to the scanner too.
 */
export function OrderingGuard({ children }: { children: ReactNode }) {
  const { session, settings } = useApp();
  useStore(session);
  useStore(settings);
  if (!session.canOrder) return <Navigate to={session.hasTable ? paths.scan : paths.root} replace />;
  if (!session.startedHere && settings.state === 'ready' && !settings.isOrderable(session.tableNumber!)) {
    return <Navigate to={paths.scan} replace />;
  }
  return <>{children}</>;
}

/**
 * A page's entrance (enter-only, so navigation never waits on it). Keyed by
 * the path, so it replays on every navigation, back and forward included;
 * with reduced motion it is a plain fade.
 */
export function PageTransition({ children }: { children: ReactNode }) {
  const { pathname } = useLocation();
  const reduced = useReducedMotion();
  return (
    <motion.div key={pathname} className="page-transition" variants={reduced ? fade : page} initial="hidden" animate="shown">
      {children}
    </motion.div>
  );
}

/** The five tabs (Home, Menu, Cart, Orders, More) with shared navigation. */
export function Shell() {
  return (
    <OrderingGuard>
      <div className="shell">
        <Nav />
        <main className="shell__main" id="main">
          <PageTransition>
            <Outlet />
          </PageTransition>
        </main>
      </div>
    </OrderingGuard>
  );
}

const tabs = [
  { to: paths.home, label: 'Home', icon: Home },
  { to: paths.menu, label: 'Menu', icon: BookOpen },
  { to: paths.cart, label: 'Cart', icon: ShoppingBag },
  { to: paths.orders, label: 'Orders', icon: ReceiptText },
  { to: paths.more, label: 'More', icon: MoreHorizontal },
] as const;

function Nav() {
  const { cart, orders } = useApp();
  const cartCount = useSelect(cart, (c) => c.totalQuantity);
  const active = useSelect(orders, (o) => o.currentOrders.length);
  const reduced = useReducedMotion();
  return (
    <nav className="nav" aria-label="Main">
      <div className="nav__brand">
        <Lockup height={lockupHeight.md} />
      </div>
      {tabs.map(({ to, label, icon: Icon }) => {
        const badge = to === paths.cart ? cartCount : to === paths.orders ? active : 0;
        return (
          <NavLink key={to} to={to} className="nav__item" aria-label={badge > 0 ? `${label}, ${badge}` : label}>
            {({ isActive }) => (
              <>
                {/* The active tab's glowing capsule slides between tabs. */}
                {isActive && (
                  <motion.span
                    layoutId="nav-pill"
                    className="nav__pill"
                    transition={reduced ? { duration: 0 } : { type: 'spring', stiffness: 500, damping: 38 }}
                  />
                )}
                <span className="nav__icon">
                  <Icon size={iconSize.xl} strokeWidth={isActive ? 2.3 : 1.9} />
                  <AnimatePresence>
                    {badge > 0 && (
                      <motion.span
                        key={badge}
                        className="count-badge nav__badge"
                        initial={reduced ? false : { scale: 0.4 }}
                        animate={{ scale: [1.35, 1] }}
                        exit={{ scale: 0, opacity: 0 }}
                        transition={{ duration: 0.3 }}
                        aria-hidden
                      >
                        {badge > 99 ? '99+' : badge}
                      </motion.span>
                    )}
                  </AnimatePresence>
                </span>
                <span className="nav__label">{label}</span>
              </>
            )}
          </NavLink>
        );
      })}
    </nav>
  );
}
