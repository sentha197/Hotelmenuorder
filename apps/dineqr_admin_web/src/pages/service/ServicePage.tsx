import { CircleCheck, ConciergeBell, Plus, ShoppingBag } from 'lucide-react';
import { motion } from 'motion/react';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { TableBadge } from '@/components/domain/Domain';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn, toneStyle, type Tone } from '@/components/ui/cn';
import { Dialog } from '@/components/ui/Dialog';
import { Empty } from '@/components/ui/Feedback';
import { Page } from '@/components/ui/Page';
import type { Invoice } from '@/core/billing';
import { Currency } from '@/core/money';
import { Orders, Tables, type RestaurantOrder } from '@/core/orders';
import type { RestaurantTable } from '@/core/settings';
import { AppFormat } from '@/core/time';
import { useOrderBusy } from '@/state/actions';
import { useBills, useOrders, useTables } from '@/state/data';
import { useAccess } from '@/state/session';
import { advanceOrder } from '../orders/orderActions';

/**
 * The tables each staff member is covering, saved in this browser
 * (ServiceSectionController). A personal working filter, not a
 * restaurant-wide assignment: anyone may still serve any table.
 */
const SECTIONS_KEY = 'admin.serviceSections';

function readSections(): Record<string, number[]> {
  try {
    const raw = window.localStorage.getItem(SECTIONS_KEY);
    const json = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
    return Object.fromEntries(Object.entries(json).filter(([, v]) => Array.isArray(v)).map(([k, v]) => [k, (v as unknown[]).filter((n): n is number => typeof n === 'number')]));
  } catch {
    // A damaged preference is not worth an error; start over.
    return {};
  }
}

function writeSection(staffId: string, tables: number[]) {
  const all = readSections();
  if (tables.length === 0) delete all[staffId];
  else all[staffId] = [...tables].sort((a, b) => a - b);
  try {
    window.localStorage.setItem(SECTIONS_KEY, JSON.stringify(all));
  } catch {
    // Kept for this page only.
  }
}

type TableState = 'free' | 'ordering' | 'ready' | 'billDue';
const tableStates: Record<TableState, { label: string; tone: Tone }> = {
  free: { label: 'Free', tone: 'muted' },
  ordering: { label: 'Ordered', tone: 'info' },
  ready: { label: 'Ready', tone: 'success' },
  billDue: { label: 'Bill due', tone: 'ember' },
};

function stateOf(active: RestaurantOrder[], dueBills: Invoice[]): TableState {
  if (active.some((o) => o.status === 'readyToServe')) return 'ready';
  if (active.length) return 'ordering';
  if (dueBills.length) return 'billDue';
  return 'free';
}

/** Bills for [table] that still have money due, from today's service. */
const dueBills = (bills: Invoice[], table: number, now: Date) =>
  bills.filter((i) => i.tableNumber === table && !i.isVoid && i.outstanding > 0 && now.getTime() - i.createdAt.getTime() < 12 * 3_600_000);

const readyAt = (o: RestaurantOrder) => o.statusTimes.readyToServe ?? o.createdAt;

/** Service board for waiters: what to take to the tables, what is cooking, and each table's state (ServiceScreen). */
export function ServicePage() {
  const navigate = useNavigate();
  const { actor, can } = useAccess();
  const orders = useOrders().data ?? [];
  const bills = useBills().data ?? [];
  const allTables = useTables().data ?? [];
  const [section, setSection] = useState<number[]>(() => (actor ? (readSections()[actor.id] ?? []) : []));
  const [picking, setPicking] = useState(false);
  const [openTable, setOpenTable] = useState<number | null>(null);
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    // Keep "ready for N min" current while the board is open.
    const timer = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(timer);
  }, []);
  if (!actor) return null;

  // Takeaway orders belong to no table, so no section leaves them out.
  const mine = (table: number) => section.length === 0 || section.includes(table) || Tables.isTakeaway(table);
  const active = orders.filter((o) => Orders.isActive(o) && mine(o.tableNumber)).sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  const ready = active.filter((o) => o.status === 'readyToServe').sort((a, b) => readyAt(a).getTime() - readyAt(b).getTime());
  const cooking = active.filter((o) => o.status !== 'readyToServe');
  const tables = allTables.filter((t) => t.isActive && mine(t.number));
  const canBills = can('viewBills');
  const canCreate = can('createOrders');

  const saveSection = (next: number[]) => {
    writeSection(actor.id, next);
    setSection([...next].sort((a, b) => a - b));
    setPicking(false);
  };

  return (
    <Page
      title="Service"
      subtitle={section.length === 0 ? 'All tables' : `Your section · ${section.length} ${section.length === 1 ? 'table' : 'tables'}`}
      actions={
        canCreate && (
          <Button variant="primary" icon={Plus} onClick={() => navigate('/orders/new')}>
            New order
          </Button>
        )
      }
    >
      <div className="panel flex flex-wrap items-center gap-3 px-4 py-3">
        <p className="min-w-0 flex-1 text-[13px] text-muted">
          {section.length === 0 ? 'Showing every table. Pick the tables you are covering to see only yours.' : `My tables: ${section.map(AppFormat.table).join(', ')}`}
        </p>
        <Button size="sm" onClick={() => setPicking(true)}>
          {section.length === 0 ? 'Choose' : 'Edit'}
        </Button>
      </div>

      <SectionCard title="Ready to serve" subtitle={ready.length === 0 ? 'Nothing waiting' : `${ready.length} waiting · oldest first`} index={0}>
        {ready.length === 0 ? (
          <Empty compact icon={ConciergeBell} title="All served" message="Dishes the kitchen marks ready appear here to take to the table." />
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {ready.map((o) => (
              <ReadyCard key={o.id} order={o} waitingMinutes={Math.floor((now.getTime() - readyAt(o).getTime()) / 60_000)} canServe={can('serveOrders')} />
            ))}
          </div>
        )}
      </SectionCard>

      <SectionCard title="In the kitchen" subtitle={cooking.length === 0 ? 'No open orders' : `${cooking.length} on the way`} index={1}>
        {cooking.length === 0 ? (
          <p className="text-[13px] text-muted">New orders for your tables show here until they are ready.</p>
        ) : (
          <ul className="divide-y divide-line">
            {cooking.map((o) => {
              const eta = Math.trunc((o.estimatedReadyAt.getTime() - now.getTime()) / 60_000);
              return (
                <li key={o.id}>
                  <button type="button" onClick={() => navigate(`/orders/${encodeURIComponent(o.id)}`)} className="flex w-full items-center gap-3 py-2.5 text-left hover:bg-panel-2/40">
                    <span className="grid h-9 w-12 shrink-0 place-items-center rounded-lg bg-panel-2 text-[12px] font-bold text-ink">
                      {Orders.isTakeaway(o) ? <ShoppingBag size={15} aria-label="Takeaway" /> : `T${AppFormat.table(o.tableNumber)}`}
                    </span>
                    <span className="min-w-0 flex-1 truncate text-[13px] text-ink">
                      {AppFormat.orderNumber(o.id)} · {AppFormat.itemCount(Orders.itemCount(o))}
                    </span>
                    <span className="text-[12px] text-faint">{eta > 0 ? `~${eta} min` : 'Due'}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </SectionCard>

      <SectionCard title="Tables" subtitle="Tap a table for its orders and bill" index={2}>
        {tables.length === 0 ? (
          <p className="text-[13px] text-muted">No active tables.</p>
        ) : (
          <div className="grid grid-cols-[repeat(auto-fill,minmax(96px,1fr))] gap-2.5">
            {tables.map((t, i) => {
              const state = stateOf(
                orders.filter((o) => o.tableNumber === t.number && Orders.isActive(o)),
                canBills ? dueBills(bills, t.number, now) : [],
              );
              return <TableTile key={t.number} table={t} state={state} index={i} onClick={() => setOpenTable(t.number)} />;
            })}
          </div>
        )}
      </SectionCard>

      <SectionPicker open={picking} tables={allTables.filter((t) => t.isActive).map((t) => t.number)} initial={section} onClose={() => setPicking(false)} onSave={saveSection} />
      <TableSheet number={openTable} onClose={() => setOpenTable(null)} orders={orders} bills={canBills ? bills : []} canCreate={canCreate} canBills={canBills} />
    </Page>
  );
}

function ReadyCard({ order, waitingMinutes, canServe }: { order: RestaurantOrder; waitingMinutes: number; canServe: boolean }) {
  const busy = useOrderBusy(order.id);
  const takeaway = Orders.isTakeaway(order);
  return (
    <motion.div layout initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} className="rounded-2xl border border-success/30 bg-success/6 p-4">
      <div className="flex items-center gap-3">
        <TableBadge table={order.tableNumber} size={44} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[14px] font-semibold text-ink">{AppFormat.orderNumber(order.id)}</p>
          <p className="text-[12px] font-semibold text-success">{waitingMinutes < 1 ? 'Ready now' : `Ready ${waitingMinutes} min`}</p>
        </div>
      </div>
      <ul className="mt-3 flex flex-col gap-0.5">
        {order.lines.map((l, i) => (
          <li key={`${l.itemId}-${i}`} className="text-[13px] text-ink">
            {l.quantity} × {l.name}
          </li>
        ))}
      </ul>
      {order.specialInstructions && <p className="mt-2 text-[12.5px] font-medium text-ember-text">Note: {order.specialInstructions}</p>}
      {canServe && (
        <Button variant="success" block className="mt-3" icon={CircleCheck} loading={busy} onClick={() => void advanceOrder(order)}>
          {takeaway ? 'Handed over at the counter' : `Served at table ${AppFormat.table(order.tableNumber)}`}
        </Button>
      )}
    </motion.div>
  );
}

function TableTile({ table, state, onClick, index }: { table: RestaurantTable; state: TableState; onClick: () => void; index: number }) {
  const info = tableStates[state];
  return (
    <motion.button
      type="button"
      initial={{ opacity: 0, scale: 0.94 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay: Math.min(index, 20) * 0.015 }}
      whileHover={{ y: -2 }}
      onClick={onClick}
      aria-label={`Table ${table.number}, ${info.label}`}
      style={toneStyle(info.tone)}
      className={cn('tone flex flex-col items-start rounded-2xl p-3 text-left', state === 'free' && 'border-line bg-panel')}
    >
      <span className="text-[22px] font-bold leading-none tabular text-ink">{AppFormat.table(table.number)}</span>
      <span className="mt-1.5 text-[12px] font-bold">{info.label}</span>
      <span className="text-[10.5px] text-faint">{table.seats} seats</span>
    </motion.button>
  );
}

function TableSheet({ number, onClose, orders, bills, canCreate, canBills }: { number: number | null; onClose: () => void; orders: RestaurantOrder[]; bills: Invoice[]; canCreate: boolean; canBills: boolean }) {
  const navigate = useNavigate();
  const { can } = useAccess();
  const now = new Date();
  const open = number == null ? [] : orders.filter((o) => o.tableNumber === number && Orders.isActive(o));
  const due = number == null || !canBills ? [] : dueBills(bills, number, now);
  const go = (path: string) => {
    onClose();
    navigate(path);
  };
  return (
    <Dialog open={number != null} onClose={onClose} title={number == null ? '' : `Table ${AppFormat.table(number)}`} size="sm">
      <div className="flex flex-col gap-1 pb-4">
        {open.length === 0 && due.length === 0 && <p className="py-2 text-[13px] text-muted">No open orders or bills.</p>}
        {open.map((o) => (
          <button key={o.id} type="button" disabled={!can('viewOrders')} onClick={() => go(`/orders/${encodeURIComponent(o.id)}`)} className="flex items-center justify-between rounded-xl px-3 py-2.5 text-left hover:bg-panel-2">
            <span>
              <span className="block text-[13.5px] font-semibold text-ink">{AppFormat.orderNumber(o.id)}</span>
              <span className="block text-[12px] text-muted">{AppFormat.itemCount(Orders.itemCount(o))}</span>
            </span>
            <span className="text-[12px] text-faint">{Orders.statusLabel(o)}</span>
          </button>
        ))}
        {due.map((b) => (
          <button key={b.id} type="button" onClick={() => go(`/bills/${encodeURIComponent(b.id)}`)} className="flex items-center justify-between rounded-xl px-3 py-2.5 text-left hover:bg-panel-2">
            <span>
              <span className="block text-[13.5px] font-semibold text-ink">{b.billNumber}</span>
              <span className="block text-[12px] text-ember-text">{Currency.format(b.outstanding)} due</span>
            </span>
          </button>
        ))}
        {canCreate && number != null && (
          <Button variant="primary" icon={Plus} block className="mt-3" onClick={() => go(`/orders/new?table=${number}`)}>
            New order for this table
          </Button>
        )}
      </div>
    </Dialog>
  );
}

function SectionPicker({ open, tables, initial, onClose, onSave }: { open: boolean; tables: number[]; initial: number[]; onClose: () => void; onSave: (tables: number[]) => void }) {
  const [picked, setPicked] = useState<Set<number>>(new Set(initial));
  useEffect(() => {
    if (open) setPicked(new Set(initial));
  }, [open, initial]);
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="My tables"
      description="Saved in this browser for you. Leave all unselected to see every table."
      footer={
        <>
          <Button variant="ghost" onClick={() => onSave([])}>
            All tables
          </Button>
          <Button variant="primary" onClick={() => onSave([...picked])}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-wrap gap-2 pb-3">
        {tables.map((t) => {
          const on = picked.has(t);
          return (
            <button
              key={t}
              type="button"
              aria-pressed={on}
              onClick={() =>
                setPicked((p) => {
                  const next = new Set(p);
                  if (on) next.delete(t);
                  else next.add(t);
                  return next;
                })
              }
              className={cn('h-10 min-w-12 rounded-xl border px-3 text-[13px] font-bold tabular', on ? 'border-transparent brand-fill' : 'border-line bg-panel-2 text-ink')}
            >
              {AppFormat.table(t)}
            </button>
          );
        })}
      </div>
    </Dialog>
  );
}
