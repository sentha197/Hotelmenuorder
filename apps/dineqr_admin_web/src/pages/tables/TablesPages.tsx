import { Armchair, Pencil, Plus, Power, Printer, QrCode as QrIcon, ShoppingBag, Trash2 } from 'lucide-react';
import { motion } from 'motion/react';
import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { Lockup } from '@/components/brand/Brand';
import { QrCode } from '@/components/domain/Domain';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn, toneStyle, type Tone } from '@/components/ui/cn';
import { Dialog, confirmDialog } from '@/components/ui/Dialog';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { SwitchRow, TextField } from '@/components/ui/Form';
import { Page } from '@/components/ui/Page';
import { webBase } from '@/config/env';
import { Orders, TAKEAWAY_TABLE, Tables } from '@/core/orders';
import { codeFor } from '@/core/qr';
import { validateTable, type RestaurantTable } from '@/core/settings';
import { AppFormat } from '@/core/time';
import { addTable, removeTable, setTableActive, tableInUse, updateSettings, updateTable } from '@/state/actions';
import { useBills, useOrders, useSettings, useTables } from '@/state/data';
import { runAction, useAction } from '@/state/run';
import { useAccess } from '@/state/session';

type TableState = 'available' | 'occupied' | 'billDue' | 'inactive';
const tableStates: Record<TableState, { label: string; tone: Tone }> = {
  available: { label: 'Available', tone: 'success' },
  occupied: { label: 'Occupied', tone: 'warning' },
  billDue: { label: 'Bill due', tone: 'brand' },
  inactive: { label: 'Inactive', tone: 'muted' },
};

/** Tables, their live status and QR codes (TablesScreen). */
export function TablesPage() {
  const navigate = useNavigate();
  const { can } = useAccess();
  const tablesQuery = useTables();
  const tables = tablesQuery.data ?? [];
  const orders = useOrders().data ?? [];
  const bills = useBills().data ?? [];
  const [selected, setSelected] = useState<number | null>(null);
  const [editing, setEditing] = useState<RestaurantTable | 'new' | null>(null);
  const canEdit = can('manageTables');

  const openOrders = (n: number) => orders.filter((o) => o.tableNumber === n && Orders.isActive(o)).length;
  const stateOf = (t: RestaurantTable): TableState => {
    if (!t.isActive) return 'inactive';
    if (openOrders(t.number) > 0) return 'occupied';
    return bills.some((i) => i.tableNumber === t.number && i.outstanding !== 0) ? 'billDue' : 'available';
  };
  const counts = Object.fromEntries((Object.keys(tableStates) as TableState[]).map((s) => [s, tables.filter((t) => stateOf(t) === s).length])) as Record<TableState, number>;

  const printAll = () => navigate('/tables/print');

  return (
    <Page
      title="Tables & QR codes"
      subtitle={`${tables.length} tables · ${counts.occupied} occupied`}
      actions={
        canEdit && (
          <>
            <Button icon={Printer} onClick={printAll} disabled={!tables.some((t) => t.isActive)}>
              Print all QR codes
            </Button>
            <Button variant="primary" icon={Plus} onClick={() => setEditing('new')}>
              Add table
            </Button>
          </>
        )
      }
    >
      <div className="flex flex-wrap gap-2">
        {(Object.keys(tableStates) as TableState[]).map((s) => (
          <span key={s} style={toneStyle(tableStates[s].tone)} className="tone inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-[12px] font-semibold">
            <span className="h-2 w-2 rounded-full bg-[var(--tone)]" aria-hidden />
            {tableStates[s].label} ({counts[s]})
          </span>
        ))}
      </div>
      {tablesQuery.isPending ? (
        <PageSkeleton />
      ) : tables.length === 0 ? (
        <Empty icon={Armchair} title="No tables yet" message={canEdit ? 'Add your first table to print its QR code.' : 'Ask a manager to add the tables.'} />
      ) : (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-3">
          {tables.map((t, i) => {
            const state = stateOf(t);
            const count = openOrders(t.number);
            return (
              <motion.button
                key={t.number}
                type="button"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: Math.min(i, 24) * 0.015 }}
                whileHover={{ y: -3 }}
                onClick={() => setSelected(t.number)}
                aria-label={`Table ${t.number}, ${tableStates[state].label}, ${t.seats} seats`}
                style={toneStyle(tableStates[state].tone)}
                className={cn('panel flex flex-col gap-2 p-4 text-left', state === 'inactive' && 'opacity-60')}
              >
                <div className="flex items-start justify-between">
                  <span className="text-[26px] font-bold leading-none tabular text-ink">{AppFormat.table(t.number)}</span>
                  <QrIcon size={18} className="text-faint" aria-hidden />
                </div>
                <span className="text-[12px] text-muted">
                  {t.seats} seats{t.area ? ` · ${t.area}` : ''}
                </span>
                <span className="tone w-fit rounded-full px-2.5 py-1 text-[11px] font-bold">{state === 'occupied' && count > 1 ? `${tableStates[state].label} · ${count} orders` : tableStates[state].label}</span>
              </motion.button>
            );
          })}
        </div>
      )}
      <TakeawayCard />
      <p className="text-[12.5px] text-faint">Guests scan a table's QR code to order for that table, and the takeaway code to order for collection. The codes identify where an order comes from and never give access to this dashboard.</p>
      <TableSheet number={selected} tables={tables} onClose={() => setSelected(null)} onEdit={(t) => setEditing(t)} hasOpenOrders={(n) => tableInUse(n, orders, bills)} />
      <TableDialog table={editing} tables={tables} onClose={() => setEditing(null)} />
    </Page>
  );
}

/** One code for orders collected at the counter (_TakeawaySection). */
function TakeawayCard() {
  const navigate = useNavigate();
  const { can } = useAccess();
  const { settings } = useSettings();
  const enabled = settings.takeawayOrdersEnabled;
  const canConfigure = can('manageSettings');
  return (
    <SectionCard title="Takeaway QR code" subtitle="One code for orders collected at the counter. Guests who scan it order without choosing a table; while takeaway is open the DineQR app also offers it on its scanner.">
      <SwitchRow
        title="Take takeaway orders"
        description={canConfigure ? 'While this is off, guests and staff cannot place takeaway orders, and the code says so.' : 'Only a role that can manage settings may change this.'}
        checked={enabled}
        disabled={!canConfigure}
        onChange={(on) => void runAction(() => updateSettings({ ...settings, takeawayOrdersEnabled: on }), { success: on ? 'Takeaway orders are now open' : 'Takeaway orders are now closed' })}
      />
      <div className="mt-3 flex flex-wrap items-center gap-5">
        <div className={cn(!enabled && 'opacity-50')}>
          <QrCode payload={codeFor(TAKEAWAY_TABLE, webBase)} size={150} label="Takeaway order QR code" logo />
        </div>
        <div className="flex flex-col gap-2">
          <p className="flex items-center gap-2 text-[14px] font-semibold text-ink">
            <ShoppingBag size={16} className="text-ember-text" aria-hidden /> Takeaway
          </p>
          <Button icon={Printer} onClick={() => navigate(`/tables/print?table=${TAKEAWAY_TABLE}`)}>
            Print QR / save PDF
          </Button>
        </div>
      </div>
    </SectionCard>
  );
}

function TableSheet({ number, tables, onClose, onEdit, hasOpenOrders }: { number: number | null; tables: RestaurantTable[]; onClose: () => void; onEdit: (t: RestaurantTable) => void; hasOpenOrders: (n: number) => boolean }) {
  const navigate = useNavigate();
  const { can } = useAccess();
  const [shown, setShown] = useState<number | null>(null);
  if (number != null && number !== shown) setShown(number);
  const table = tables.find((t) => t.number === (number ?? shown));
  const canEdit = can('manageTables');
  const remove = async (t: RestaurantTable) => {
    const ok = await confirmDialog({ title: `Remove table ${t.number}?`, message: 'Its QR code will stop working. Past orders and bills are kept.', confirmLabel: 'Remove', icon: Trash2, danger: true });
    if (!ok) return;
    const done = await runAction(() => removeTable(t.number, hasOpenOrders(t.number)), { success: `Table ${t.number} removed` });
    if (done) onClose();
  };
  return (
    <Dialog open={number != null && table != null} onClose={onClose} title={table ? `Table ${AppFormat.table(table.number)}` : ''} description={table ? `${table.seats} seats${table.area ? ` · ${table.area}` : ''}${table.isActive ? '' : ' · inactive'}` : undefined}>
      {table && (
        <div className="flex flex-col items-center gap-4 pb-4">
          <QrCode payload={codeFor(table.number, webBase)} size={210} label={`QR code for table ${table.number}`} logo />
          {!table.isActive && <Notice tone="warning">Guests scanning this code are told the table is not taking orders.</Notice>}
          <div className="flex w-full flex-wrap justify-center gap-2">
            <Button icon={Printer} onClick={() => navigate(`/tables/print?table=${table.number}`)}>
              Print QR / save PDF
            </Button>
            {canEdit && (
              <>
                <Button icon={Pencil} onClick={() => (onClose(), onEdit(table))}>
                  Edit
                </Button>
                <Button icon={Power} onClick={() => void runAction(() => setTableActive(table.number, !table.isActive))}>
                  {table.isActive ? 'Deactivate' : 'Activate'}
                </Button>
                <Button variant="danger" icon={Trash2} onClick={() => void remove(table)}>
                  Remove
                </Button>
              </>
            )}
          </div>
        </div>
      )}
    </Dialog>
  );
}

function TableDialog({ table, tables, onClose }: { table: RestaurantTable | 'new' | null; tables: RestaurantTable[]; onClose: () => void }) {
  const [shown, setShown] = useState<RestaurantTable | 'new' | null>(null);
  const [number, setNumber] = useState('');
  const [seats, setSeats] = useState('');
  const [area, setArea] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  if (table && table !== shown) {
    setShown(table);
    const next = tables.length === 0 ? 1 : Math.max(...tables.map((t) => t.number)) + 1;
    setNumber(String(table === 'new' ? next : table.number));
    setSeats(String(table === 'new' ? 4 : table.seats));
    setArea(table === 'new' ? '' : table.area);
    setError(null);
  }
  const editing = table !== 'new' && table != null ? table : null;
  const submit = async () => {
    const n = /^\d+$/.test(number.trim()) ? Number(number.trim()) : NaN;
    const s = /^\d+$/.test(seats.trim()) ? Number(seats.trim()) : NaN;
    if (!Number.isFinite(n) || !Number.isFinite(s)) return setError('Enter numbers for the table and seats.');
    const problem = validateTable(n, s);
    if (problem) return setError(problem);
    const ok = await run(() => (editing ? updateTable({ number: n, seats: s, area: area.trim(), isActive: editing.isActive }) : addTable(n, s, area)), { success: editing ? `Table ${n} saved` : `Table ${n} added` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={table != null}
      onClose={onClose}
      title={editing ? `Edit table ${AppFormat.table(editing.number)}` : 'Add table'}
      size="sm"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            {editing ? 'Save' : 'Add'}
          </Button>
        </>
      }
    >
      <form className="flex flex-col gap-4 pb-2" onSubmit={(e) => (e.preventDefault(), void submit())}>
        <div className="grid grid-cols-2 gap-3">
          <TextField label="Table number" inputMode="numeric" disabled={editing != null} value={number} onChange={(e) => setNumber(e.target.value)} />
          <TextField label="Seats" inputMode="numeric" value={seats} onChange={(e) => setSeats(e.target.value)} />
        </div>
        <TextField label="Area (optional)" placeholder="e.g. Terrace" value={area} onChange={(e) => setArea(e.target.value)} />
        {error && (
          <p role="alert" className="text-[12.5px] text-danger">
            {error}
          </p>
        )}
      </form>
    </Dialog>
  );
}

/**
 * Printable QR cards: every active table (plus takeaway while it is open),
 * or one code with `?table=N` (TableQrPdf). Print it, or save it as a PDF
 * from the print dialog.
 */
export function QrSheetPage() {
  const [params] = useSearchParams();
  const { settings } = useSettings();
  const tables = useTables().data ?? [];
  const single = params.get('table');
  const rows: number[] =
    single != null && /^\d+$/.test(single)
      ? [Number(single)]
      : [...tables.filter((t) => t.isActive).map((t) => t.number), ...(settings.takeawayOrdersEnabled ? [TAKEAWAY_TABLE] : [])];
  return (
    <Page
      title={single != null ? `${Tables.label(Number(single))} QR` : 'DineQR table QR codes'}
      subtitle='Print it, or choose "Save as PDF" in the print dialog.'
      back="/tables"
      width="medium"
      actions={
        <Button variant="primary" icon={Printer} onClick={() => window.print()}>
          Print / save PDF
        </Button>
      }
    >
      {rows.length === 0 ? (
        <Empty icon={QrIcon} title="There are no active tables." />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 print:grid-cols-2">
          {rows.map((n) => (
            <div key={n} className="print-avoid flex flex-col items-center rounded-2xl border-[1.5px] border-[#b5121b] bg-white p-5 text-center text-[#1d1416]">
              <Lockup height={30} trim onLight />
              <p className="mt-1 text-[11px] text-[#6b5a5d]">{settings.name}</p>
              <div className="mt-3">
                <QrCode payload={codeFor(n, webBase)} size={170} label={`QR code for ${Tables.label(n)}`} logo />
              </div>
              <p className="mt-3 text-[20px] font-bold">{Tables.label(n)}</p>
              <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-[#b5121b]">Scan • Order • Enjoy</p>
              <p className="mt-1.5 max-w-[240px] text-[11px] leading-snug text-[#6b5a5d]">
                {n === TAKEAWAY_TABLE ? 'Point your phone camera at the code to see the menu and order takeaway to collect at the counter.' : 'Point your phone camera at the code to see the menu and order from your table.'}
              </p>
            </div>
          ))}
        </div>
      )}
    </Page>
  );
}
