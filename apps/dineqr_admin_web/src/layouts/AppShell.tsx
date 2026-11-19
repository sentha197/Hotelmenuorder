import { ChevronsLeft, ChevronsRight, LayoutGrid, LogOut, Monitor, Moon, Search, Sun, type LucideIcon } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from 'react';
import { NavLink, useLocation, useNavigate, useOutlet } from 'react-router';
import { LiveUpdates } from '@/api/realtime';
import { DineQrMark, Lockup } from '@/components/brand/Brand';
import { cn } from '@/components/ui/cn';
import { Dialog, confirmDialog } from '@/components/ui/Dialog';
import { roleInfo, Staff, type StaffAccount } from '@/core/access';
import { modulesFor, workspaceTitle, type AdminModule, type ModuleId } from '@/routes/modules';
import { requireBackend } from '@/services/backend';
import { liveHandlers, livePatchers, useOrders } from '@/state/data';
import { Session, useAccess } from '@/state/session';
import { useTheme, type ThemePreference } from '@/theme/theme';

const SIDEBAR_KEY = 'dineqr.admin.sidebar';

function readCollapsed() {
  try {
    return window.localStorage.getItem(SIDEBAR_KEY) === 'collapsed';
  } catch {
    return false;
  }
}

/** Live-update connection state, for the indicator in the top bar. */
function useLiveConnected() {
  const realtime = requireBackend().realtime;
  return useSyncExternalStore(
    (l) => realtime.onStateChange(l),
    () => realtime.isConnected,
  );
}

/**
 * Keeps the signed-in workspace current: live updates from the server (with
 * a 30 s poll while they are down), a warm-up, and the session-expiry check.
 */
function useWorkspaceSync(staffId: string) {
  useEffect(() => {
    const { realtime } = requireBackend();
    const live = new LiveUpdates(realtime, liveHandlers, undefined, livePatchers);
    void realtime.start();
    const expiry = setInterval(() => void Session.checkExpiry(), 30_000);
    const onVisible = () => document.visibilityState === 'visible' && void Session.checkExpiry();
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      live.dispose();
      void realtime.stop();
      clearInterval(expiry);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [staffId]);
}

/**
 * The page this transition wrapper was created for. A plain <Outlet /> always
 * renders the current route, so while the previous page faded out its wrapper
 * rendered the new page as well: every screen was built twice and the copy
 * torn down again (with every animated card re-measured), which held the
 * screen blank for seconds on big lists. Each wrapper now keeps its own page.
 */
function FrozenOutlet() {
  const outlet = useOutlet();
  const [frozen] = useState(outlet);
  return frozen;
}

/** Counts shown on navigation items (new orders, ready orders). */
function useBadges() {
  const orders = useOrders().data ?? [];

  const placed = orders.filter((o) => o.status === 'placed').length;
  const ready = orders.filter((o) => o.status === 'readyToServe').length;
  return (id: ModuleId) => (id === 'orders' || id === 'kitchen' ? placed : id === 'service' ? ready : 0);
}

async function signOut() {
  const ok = await confirmDialog({ title: 'Sign out?', message: 'You will need to sign in again to use DineQR Admin.', confirmLabel: 'Sign out', icon: LogOut });
  if (ok) await Session.signOut();
}

export function AppShell() {
  const { actor } = useAccess();
  if (!actor) return null;
  return <Workspace staff={actor} />;
}

function Workspace({ staff }: { staff: StaffAccount }) {
  useWorkspaceSync(staff.id);
  const location = useLocation();
  const navigate = useNavigate();
  const mods = useMemo(() => modulesFor(staff), [staff]);
  const badgeFor = useBadges();
  const [collapsed, setCollapsed] = useState(readCollapsed);
  const [palette, setPalette] = useState(false);
  const [more, setMore] = useState(false);
  const current = mods.find((m) => location.pathname === m.path || location.pathname.startsWith(`${m.path}/`));

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPalette((p) => !p);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    document.title = current ? `${current.label} · DineQR Admin` : 'DineQR Admin';
  }, [current]);

  const toggle = () =>
    setCollapsed((c) => {
      try {
        window.localStorage.setItem(SIDEBAR_KEY, c ? 'expanded' : 'collapsed');
      } catch {
        // Remembered for this page only.
      }
      return !c;
    });

  const primary = mods.slice(0, 4);
  const rest = mods.slice(4);

  return (
    <div className="relative min-h-dvh">
      <div className="app-backdrop" aria-hidden />
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[70] focus:rounded-lg focus:bg-panel-solid focus:px-3 focus:py-2">
        Skip to content
      </a>
      {/* Side navigation from tablets up. */}
      <motion.aside
        animate={{ width: collapsed ? 84 : 264 }}
        transition={{ type: 'spring', stiffness: 380, damping: 40 }}
        className="no-print fixed inset-y-0 left-0 z-30 hidden flex-col border-r border-white/5 text-[#f6ecec] md:flex"
        style={{ background: 'var(--sidebar)' }}
      >
        <div className={cn('flex h-[72px] shrink-0 items-center', collapsed ? 'justify-center' : 'justify-between pl-5 pr-3')}>
          {collapsed ? <DineQrMark size={42} tone="inverted" /> : <Lockup height={34} trim onDark />}
          {!collapsed && (
            <button type="button" onClick={toggle} aria-label="Collapse navigation" title="Collapse navigation" className="grid h-8 w-8 place-items-center rounded-lg text-white/50 hover:bg-white/8 hover:text-white">
              <ChevronsLeft size={17} aria-hidden />
            </button>
          )}
        </div>
        {collapsed && (
          <button type="button" onClick={toggle} aria-label="Expand navigation" title="Expand navigation" className="mx-auto mb-2 grid h-8 w-8 place-items-center rounded-lg text-white/50 hover:bg-white/8 hover:text-white">
            <ChevronsRight size={17} aria-hidden />
          </button>
        )}
        {!collapsed && <p className="px-5 pb-2 text-[10.5px] font-semibold uppercase tracking-[0.16em] text-white/35">{workspaceTitle(staff)} workspace</p>}
        <nav className="no-scrollbar flex-1 overflow-y-auto px-3 pb-4" aria-label="Modules">
          <ul className="flex flex-col gap-1">
            {mods.map((m) => (
              <li key={m.id}>
                <SideItem module={m} collapsed={collapsed} badge={badgeFor(m.id)} active={current?.id === m.id} />
              </li>
            ))}
          </ul>
        </nav>
        <div className={cn('border-t border-white/8 p-3', collapsed && 'flex flex-col items-center gap-2')}>
          {collapsed ? (
            <>
              <Avatar staff={staff} />
              <button type="button" onClick={() => void signOut()} aria-label="Sign out" title="Sign out" className="grid h-9 w-9 place-items-center rounded-lg text-white/55 hover:bg-white/8 hover:text-white">
                <LogOut size={17} aria-hidden />
              </button>
            </>
          ) : (
            <div className="flex items-center gap-3 rounded-xl bg-white/[0.04] p-2.5">
              <Avatar staff={staff} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13px] font-semibold">{staff.name}</p>
                <p className="truncate text-[11.5px] text-white/50">{Staff.roleLabel(staff)}</p>
              </div>
              <button type="button" onClick={() => void signOut()} aria-label="Sign out" title="Sign out" className="grid h-9 w-9 shrink-0 place-items-center rounded-lg text-white/55 hover:bg-white/8 hover:text-white">
                <LogOut size={17} aria-hidden />
              </button>
            </div>
          )}
        </div>
      </motion.aside>

      <div className={cn('relative z-10 flex min-h-dvh flex-col transition-[padding] duration-300', collapsed ? 'md:pl-[84px]' : 'md:pl-[264px]')}>
        <TopBar staff={staff} title={current?.label ?? 'DineQR Admin'} onSearch={() => setPalette(true)} />
        <main id="main" className="relative flex-1">
          <AnimatePresence mode="wait" initial={false}>
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.22, ease: [0.22, 1, 0.36, 1] }}
            >
              {mods.length === 0 ? (
                <p className="mx-auto max-w-md px-6 py-24 text-center text-[14px] text-muted">Nothing is switched on for your account yet. Ask the owner to give you access.</p>
              ) : (
                <FrozenOutlet />
              )}
            </motion.div>
          </AnimatePresence>
        </main>
      </div>

      {/* Bottom navigation on phones: the first four modules, then More. */}
      {mods.length >= 2 && (
        <nav className="no-print fixed inset-x-0 bottom-0 z-30 border-t border-line bg-panel-solid/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-xl md:hidden" aria-label="Modules">
          <ul className="grid" style={{ gridTemplateColumns: `repeat(${primary.length + (rest.length ? 1 : 0)}, minmax(0, 1fr))` }}>
            {primary.map((m) => (
              <li key={m.id}>
                <BottomItem icon={m.icon} label={m.label} badge={badgeFor(m.id)} active={current?.id === m.id} onClick={() => navigate(m.path)} />
              </li>
            ))}
            {rest.length > 0 && (
              <li>
                <BottomItem icon={LayoutGrid} label="More" badge={rest.reduce((s, m) => s + badgeFor(m.id), 0)} active={!!current && rest.includes(current)} onClick={() => setMore(true)} />
              </li>
            )}
          </ul>
        </nav>
      )}

      <Dialog open={more} onClose={() => setMore(false)} title="More" description={`${workspaceTitle(staff)} workspace`}>
        <div className="grid grid-cols-3 gap-3 pb-4 sm:grid-cols-4">
          {rest.map((m, i) => (
            <motion.button
              key={m.id}
              type="button"
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.03 }}
              onClick={() => {
                setMore(false);
                navigate(m.path);
              }}
              className="flex flex-col items-center gap-2 rounded-2xl p-2 text-center"
            >
              <span className={cn('relative grid h-14 w-14 place-items-center rounded-2xl', current?.id === m.id ? 'brand-fill shadow-glow' : 'border border-line bg-panel-2 text-brand-text')}>
                <m.icon size={22} aria-hidden />
                {badgeFor(m.id) > 0 && <span className="absolute -right-1 -top-1 grid h-5 min-w-5 place-items-center rounded-full bg-brand px-1 text-[10px] font-bold text-white">{badgeFor(m.id)}</span>}
              </span>
              <span className="text-[12px] font-medium leading-tight text-ink">{m.label}</span>
            </motion.button>
          ))}
        </div>
      </Dialog>

      <QuickSwitch open={palette} onClose={() => setPalette(false)} modules={mods} />
    </div>
  );
}

function SideItem({ module: m, collapsed, badge, active }: { module: AdminModule; collapsed: boolean; badge: number; active: boolean }) {
  return (
    <NavLink
      to={m.path}
      title={collapsed ? m.label : undefined}
      className={cn('group relative flex items-center rounded-xl text-[13.5px] font-medium outline-none transition-colors', collapsed ? 'h-11 justify-center' : 'h-11 gap-3 px-3', active ? 'text-white' : 'text-white/60 hover:bg-white/[0.06] hover:text-white')}
    >
      {active && (
        <motion.span
          layoutId="nav-active"
          className="absolute inset-0 rounded-xl bg-[linear-gradient(120deg,#b5121b,#d62828_60%,#ff6a00)] shadow-[0_8px_28px_-10px_rgba(214,40,40,0.8)]"
          transition={{ type: 'spring', stiffness: 460, damping: 38 }}
        />
      )}
      <span className="relative">
        <m.icon size={19} aria-hidden />
        {badge > 0 && collapsed && <span className="absolute -right-2 -top-2 grid h-4 min-w-4 place-items-center rounded-full bg-[#ff8a00] px-1 text-[9px] font-bold text-black">{badge}</span>}
      </span>
      {!collapsed && <span className="relative min-w-0 flex-1 truncate">{m.label}</span>}
      {!collapsed && badge > 0 && <span className={cn('relative grid h-5 min-w-5 place-items-center rounded-full px-1.5 text-[10.5px] font-bold', active ? 'bg-white/25 text-white' : 'bg-[#ff8a00] text-black')}>{badge}</span>}
    </NavLink>
  );
}

function BottomItem({ icon: Icon, label, badge, active, onClick }: { icon: LucideIcon; label: string; badge: number; active: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} aria-current={active ? 'page' : undefined} className="relative flex h-[62px] w-full flex-col items-center justify-center gap-1">
      {active && <motion.span layoutId="bottom-active" className="absolute top-0 h-[3px] w-10 rounded-b-full brand-fill" />}
      <span className={cn('relative grid h-8 w-14 place-items-center rounded-full transition-colors', active ? 'bg-brand/12 text-brand-text' : 'text-muted')}>
        <Icon size={20} aria-hidden />
        {badge > 0 && <span className="absolute -top-1 right-2 grid h-4 min-w-4 place-items-center rounded-full bg-brand px-1 text-[9px] font-bold text-white">{badge}</span>}
      </span>
      <span className={cn('max-w-full truncate px-1 text-[10.5px] font-medium', active ? 'text-ink' : 'text-muted')}>{label}</span>
    </button>
  );
}

function Avatar({ staff, size = 36 }: { staff: StaffAccount; size?: number }) {
  return (
    <span className="grid shrink-0 place-items-center rounded-full brand-fill font-bold text-white ring-2 ring-white/10" style={{ width: size, height: size, fontSize: size * 0.42 }} aria-hidden>
      {staff.name ? staff.name[0]!.toUpperCase() : '?'}
    </span>
  );
}

function TopBar({ staff, title, onSearch }: { staff: StaffAccount; title: string; onSearch: () => void }) {
  const live = useLiveConnected();
  return (
    <header className="no-print sticky top-0 z-20 border-b border-line bg-bg/70 backdrop-blur-xl">
      <div className="flex h-16 items-center gap-3 px-4 sm:px-6 lg:px-8">
        <span className="md:hidden">
          <DineQrMark size={34} />
        </span>
        <div className="min-w-0 flex-1">
          <AnimatePresence mode="wait" initial={false}>
            <motion.p key={title} initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -4 }} transition={{ duration: 0.16 }} className="truncate text-[15px] font-semibold text-ink">
              {title}
            </motion.p>
          </AnimatePresence>
          <p className="truncate text-[11.5px] text-faint">{workspaceTitle(staff)} workspace</p>
        </div>
        <button
          type="button"
          onClick={onSearch}
          className="hidden h-10 items-center gap-2 rounded-xl border border-line bg-panel px-3 text-[12.5px] text-faint transition-colors hover:border-line-strong hover:text-muted lg:flex"
          aria-label="Go to a module"
        >
          <Search size={15} aria-hidden />
          <span>Go to…</span>
          <kbd className="ml-6 rounded-md border border-line px-1.5 py-0.5 text-[10.5px] font-semibold">Ctrl K</kbd>
        </button>
        <span
          className={cn('hidden items-center gap-2 rounded-full border px-3 py-1.5 text-[11.5px] font-semibold sm:inline-flex', live ? 'border-success/30 text-success' : 'border-warning/30 text-warning')}
          title={live ? 'Live updates are on: changes appear as they happen.' : 'Live updates are reconnecting; data refreshes every 30 seconds meanwhile.'}
        >
          <span className={cn('h-2 w-2 rounded-full', live ? 'live-dot bg-success' : 'bg-warning')} aria-hidden />
          {live ? 'Live' : 'Reconnecting'}
        </span>
        <ThemeMenu />
        <AccountMenu staff={staff} />
      </div>
    </header>
  );
}

function Popover({ trigger, label, children }: { trigger: ReactNode; label: string; children: (close: () => void) => ReactNode }) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === 'Escape' : !root.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', close);
    document.addEventListener('keydown', close);
    return () => {
      document.removeEventListener('mousedown', close);
      document.removeEventListener('keydown', close);
    };
  }, [open]);
  return (
    <div ref={root} className="relative">
      <button type="button" aria-label={label} title={label} aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((o) => !o)} className="grid h-10 min-w-10 place-items-center rounded-xl text-muted transition-colors hover:bg-panel-2 hover:text-ink">
        {trigger}
      </button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -6, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -4, scale: 0.98 }}
            transition={{ duration: 0.14 }}
            className="panel-solid absolute right-0 top-full z-40 mt-2 min-w-[220px] origin-top-right rounded-2xl p-1.5"
            role="menu"
          >
            {children(() => setOpen(false))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function ThemeMenu() {
  const { theme, preference, setPreference } = useTheme();
  const options: { value: ThemePreference; label: string; icon: LucideIcon }[] = [
    { value: 'system', label: 'Device setting', icon: Monitor },
    { value: 'light', label: 'Light', icon: Sun },
    { value: 'dark', label: 'Dark', icon: Moon },
  ];
  return (
    <Popover label="Appearance" trigger={theme === 'dark' ? <Moon size={19} aria-hidden /> : <Sun size={19} aria-hidden />}>
      {(close) => (
        <>
          <p className="px-3 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-faint">Appearance</p>
          {options.map((o) => (
            <button
              key={o.value}
              type="button"
              role="menuitemradio"
              aria-checked={preference === o.value}
              onClick={() => {
                setPreference(o.value);
                close();
              }}
              className={cn('flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-[13px] font-medium', preference === o.value ? 'bg-brand/12 text-brand-text' : 'text-ink hover:bg-panel-2')}
            >
              <o.icon size={16} aria-hidden />
              {o.label}
            </button>
          ))}
        </>
      )}
    </Popover>
  );
}

function AccountMenu({ staff }: { staff: StaffAccount }) {
  return (
    <Popover label="Account" trigger={<Avatar staff={staff} size={32} />}>
      {(close) => (
        <>
          <div className="px-3 py-2.5">
            <p className="text-[14px] font-semibold text-ink">{staff.name}</p>
            <p className="text-[12px] text-muted">
              {Staff.roleLabel(staff)} · {staff.email}
            </p>
            {staff.role !== 'custom' && <p className="mt-1 text-[11.5px] text-faint">{roleInfo[staff.role].description}</p>}
          </div>
          <div className="my-1 h-px bg-line" />
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              close();
              void signOut();
            }}
            className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-[13px] font-medium text-ink hover:bg-panel-2"
          >
            <LogOut size={16} aria-hidden /> Sign out
          </button>
        </>
      )}
    </Popover>
  );
}

/** Ctrl/⌘ K: jump to any module the role can open. */
function QuickSwitch({ open, onClose, modules: mods }: { open: boolean; onClose: () => void; modules: AdminModule[] }) {
  const navigate = useNavigate();
  const [query, setQuery] = useState('');
  const [index, setIndex] = useState(0);
  useEffect(() => {
    if (open) {
      setQuery('');
      setIndex(0);
    }
  }, [open]);
  const q = query.trim().toLowerCase();
  const shown = mods.filter((m) => !q || m.label.toLowerCase().includes(q) || m.hint.toLowerCase().includes(q));
  const go = (m: AdminModule | undefined) => {
    if (!m) return;
    onClose();
    navigate(m.path);
  };
  return (
    <Dialog open={open} onClose={onClose} title="Go to" size="sm">
      <input
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setIndex(0);
        }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') {
            e.preventDefault();
            setIndex((i) => Math.min(i + 1, shown.length - 1));
          } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            setIndex((i) => Math.max(i - 1, 0));
          } else if (e.key === 'Enter') {
            go(shown[index]);
          }
        }}
        placeholder="Type a module name"
        aria-label="Module name"
        className="field mb-3"
      />
      <ul className="flex max-h-[50vh] flex-col gap-1 overflow-y-auto pb-3">
        {shown.map((m, i) => (
          <li key={m.id}>
            <button
              type="button"
              onMouseEnter={() => setIndex(i)}
              onClick={() => go(m)}
              className={cn('flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left', i === index ? 'bg-brand/12' : 'hover:bg-panel-2')}
            >
              <span className={cn('grid h-9 w-9 place-items-center rounded-lg', i === index ? 'brand-fill' : 'bg-panel-2 text-brand-text')}>
                <m.icon size={17} aria-hidden />
              </span>
              <span className="min-w-0">
                <span className="block text-[13.5px] font-semibold text-ink">{m.label}</span>
                <span className="block truncate text-[12px] text-muted">{m.hint}</span>
              </span>
            </button>
          </li>
        ))}
        {shown.length === 0 && <li className="px-3 py-6 text-center text-[13px] text-muted">No module matches.</li>}
      </ul>
    </Dialog>
  );
}
