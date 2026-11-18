import { History, Minus, Package, Pencil, Plus, SlidersHorizontal } from 'lucide-react';
import { motion } from 'motion/react';
import { useState } from 'react';
import { Badge, Tag } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { cn } from '@/components/ui/cn';
import { Dialog } from '@/components/ui/Dialog';
import { Empty, PageSkeleton } from '@/components/ui/Feedback';
import { FilterChips, Segmented, Select, TextField } from '@/components/ui/Form';
import { Page } from '@/components/ui/Page';
import { Stock, type InventoryItem } from '@/core/inventory';
import { AppFormat } from '@/core/time';
import { adjustStock, newInventoryItemId, saveInventoryItem } from '@/state/actions';
import { useInventory, useMenu, useSettings } from '@/state/data';
import { useAction } from '@/state/run';

type StockFilter = 'all' | 'low' | 'out';
const filterLabel: Record<StockFilter, string> = { all: 'All', low: 'Low', out: 'Out of stock' };
const matches = (f: StockFilter, i: InventoryItem) => (f === 'all' ? true : f === 'low' ? Stock.isLow(i) : Stock.isOut(i));

/** Ingredients and supplies; stock changes only through recorded adjustments (InventoryScreen). */
export function InventoryPage() {
  const query = useInventory();
  const items = query.data?.items ?? [];
  const movements = query.data?.movements ?? [];
  const dishes = useMenu().data?.items ?? [];
  const { settings } = useSettings();
  const [filter, setFilter] = useState<StockFilter>('all');
  const [editing, setEditing] = useState<InventoryItem | 'new' | null>(null);
  const [adjusting, setAdjusting] = useState<InventoryItem | null>(null);
  const [history, setHistory] = useState<InventoryItem | null>(null);
  const shown = items.filter((i) => matches(filter, i));
  const low = items.filter((i) => Stock.isLow(i) || Stock.isOut(i)).length;
  return (
    <Page
      title="Inventory"
      subtitle={`${items.length} items · ${low} need attention`}
      actions={
        <Button variant="primary" icon={Plus} onClick={() => setEditing('new')}>
          Add item
        </Button>
      }
    >
      <p className="max-w-3xl text-[12.5px] leading-relaxed text-muted">
        Stock changes only through the adjustments you record; nothing is deducted automatically from orders.
        {settings.autoUnavailableWhenOutOfStock ? ' Dishes linked to an item are marked sold out when it runs out and available again when restocked.' : ''}
      </p>
      <FilterChips name="stock-filter" values={['all', 'low', 'out'] as StockFilter[]} selected={filter} labelOf={(f) => filterLabel[f]} countOf={(f) => items.filter((i) => matches(f, i)).length} onSelect={setFilter} />
      {query.isPending ? (
        <PageSkeleton />
      ) : shown.length === 0 ? (
        <Empty icon={Package} title="Nothing here" message="Add items to track their stock." />
      ) : (
        <div className="grid gap-3 md:grid-cols-2 2xl:grid-cols-3">
          {shown.map((item, i) => {
            const [label, tone] = Stock.isOut(item) ? (['Out of stock', 'danger'] as const) : Stock.isLow(item) ? (['Low', 'warning'] as const) : (['In stock', 'success'] as const);
            const fraction = item.reorderLevel <= 0 ? 1 : Math.min(1, Math.max(0, item.quantity / (item.reorderLevel * 2)));
            const linked = item.linkedDishIds.map((id) => dishes.find((d) => d.id === id)?.name ?? id);
            return (
              <motion.div key={item.id} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: Math.min(i, 16) * 0.025 }} className="panel flex flex-col p-4">
                <div className="flex items-start gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="flex items-center gap-1.5 text-[14.5px] font-semibold text-ink">
                      <span className="truncate">{item.name}</span>
                      {item.isDemoSample && <Tag>Sample</Tag>}
                    </p>
                    <p className="text-[12px] text-faint">
                      {[...(item.supplier ? [item.supplier] : []), `Reorder at ${Stock.format(item.reorderLevel)} ${item.unit}`, `Updated ${AppFormat.dateTime(item.updatedAt)}`].join(' · ')}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-[20px] font-bold leading-none tabular text-ink">
                      {Stock.format(item.quantity)} <span className="text-[12px] font-medium text-muted">{item.unit}</span>
                    </p>
                    <Badge tone={tone} className="mt-1.5">
                      {label}
                    </Badge>
                  </div>
                </div>
                <div className="mt-3 h-1.5 overflow-hidden rounded-full bg-panel-3" aria-hidden>
                  <motion.div className={cn('h-full rounded-full', tone === 'danger' ? 'bg-danger' : tone === 'warning' ? 'bg-warning' : 'bg-success')} initial={{ width: 0 }} animate={{ width: `${fraction * 100}%` }} transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }} />
                </div>
                {linked.length > 0 && <p className="mt-2 text-[12px] text-muted">Used in: {linked.join(', ')}</p>}
                <div className="mt-auto flex flex-wrap gap-1.5 pt-3">
                  <Button size="sm" variant="primary" icon={SlidersHorizontal} onClick={() => setAdjusting(item)}>
                    Adjust stock
                  </Button>
                  <Button size="sm" variant="ghost" icon={Pencil} onClick={() => setEditing(item)}>
                    Edit
                  </Button>
                  <Button size="sm" variant="ghost" icon={History} onClick={() => setHistory(item)}>
                    History
                  </Button>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
      <ItemDialog item={editing} dishes={dishes.filter((d) => !d.isArchived)} onClose={() => setEditing(null)} />
      <AdjustDialog item={adjusting} onClose={() => setAdjusting(null)} />
      <Dialog open={history != null} onClose={() => setHistory(null)} title={`${history?.name ?? 'Item'} history`}>
        {history &&
          (() => {
            const moves = movements.filter((m) => m.itemId === history.id);
            return moves.length === 0 ? (
              <Empty compact icon={History} title="No adjustments yet" message="Stock changes you record appear here." />
            ) : (
              <ul className="divide-y divide-line pb-3">
                {moves.map((m) => (
                  <li key={m.id} className="flex items-start gap-3 py-2.5">
                    <span className={cn('grid h-8 w-8 shrink-0 place-items-center rounded-lg', m.change > 0 ? 'bg-success/12 text-success' : 'bg-danger/12 text-danger')}>{m.change > 0 ? <Plus size={15} aria-hidden /> : <Minus size={15} aria-hidden />}</span>
                    <div className="min-w-0 flex-1">
                      <p className="text-[13px] font-semibold text-ink">
                        {m.change > 0 ? '+' : ''}
                        {Stock.format(m.change)} {history.unit} · {m.reason}
                      </p>
                      <p className="text-[12px] text-faint">
                        {AppFormat.dateTime(m.at)}
                        {m.by ? ` · ${m.by}` : ''} · balance {Stock.format(m.balance)}
                      </p>
                    </div>
                  </li>
                ))}
              </ul>
            );
          })()}
      </Dialog>
    </Page>
  );
}

const number = (text: string) => {
  const v = Number.parseFloat(text.trim().replace(',', '.'));
  return Number.isFinite(v) && /^-?\d*[.,]?\d*$/.test(text.trim()) ? v : null;
};

function AdjustDialog({ item, onClose }: { item: InventoryItem | null; onClose: () => void }) {
  const [shown, setShown] = useState<InventoryItem | null>(null);
  const [adding, setAdding] = useState(true);
  const [quantity, setQuantity] = useState('');
  const [reason, setReason] = useState<string>(Stock.addReasons[0]);
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  if (item && item !== shown) {
    setShown(item);
    setAdding(true);
    setQuantity('');
    setReason(Stock.addReasons[0]);
    setNote('');
    setError(null);
  }
  const it = item ?? shown;
  if (!it) return null;
  const reasons = adding ? Stock.addReasons : Stock.removeReasons;
  const submit = async () => {
    const value = number(quantity);
    if (value == null || value <= 0) return setError('Enter a quantity above zero.');
    if (!adding && value > it.quantity) return setError(`Only ${Stock.format(it.quantity)} ${it.unit} in stock.`);
    const why = note.trim() ? `${reason}: ${note.trim()}` : reason;
    const ok = await run(() => adjustStock(it, adding ? value : -value, why), { success: `${it.name} updated` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={item != null}
      onClose={onClose}
      title={`Adjust ${it.name}`}
      description={`In stock: ${Stock.format(it.quantity)} ${it.unit}`}
      icon={SlidersHorizontal}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 pb-2">
        <Segmented
          name="adjust-direction"
          value={adding}
          onChange={(v) => {
            setAdding(v);
            setReason((v ? Stock.addReasons : Stock.removeReasons)[0]);
            setError(null);
          }}
          options={[
            { value: true, label: 'Add', icon: <Plus size={15} aria-hidden /> },
            { value: false, label: 'Remove', icon: <Minus size={15} aria-hidden /> },
          ]}
        />
        <TextField label="Quantity" inputMode="decimal" suffix={it.unit} value={quantity} error={error} onChange={(e) => (setQuantity(e.target.value), setError(null))} />
        <Select label="Reason" value={reason} onChange={(e) => setReason(e.target.value)}>
          {reasons.map((r) => (
            <option key={r} value={r}>
              {r}
            </option>
          ))}
        </Select>
        <TextField label="Note (optional)" maxLength={80} value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Dialog>
  );
}

function ItemDialog({ item, dishes, onClose }: { item: InventoryItem | 'new' | null; dishes: { id: string; name: string }[]; onClose: () => void }) {
  const [shown, setShown] = useState<InventoryItem | 'new' | null>(null);
  const [name, setName] = useState('');
  const [quantity, setQuantity] = useState('');
  const [unit, setUnit] = useState<string>('kg');
  const [reorder, setReorder] = useState('');
  const [supplier, setSupplier] = useState('');
  const [linked, setLinked] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  if (item && item !== shown) {
    const it = item === 'new' ? null : item;
    setShown(item);
    setName(it?.name ?? '');
    setQuantity(it ? Stock.format(it.quantity) : '');
    setUnit(it?.unit ?? 'kg');
    setReorder(it ? Stock.format(it.reorderLevel) : '');
    setSupplier(it?.supplier ?? '');
    setLinked(new Set(it?.linkedDishIds ?? []));
    setError(null);
  }
  const existing = item === 'new' || item == null ? null : item;
  const submit = async () => {
    const qty = existing ? existing.quantity : number(quantity);
    const level = number(reorder);
    if (qty == null || level == null) return setError('Enter numbers for quantity and reorder level.');
    setError(null);
    const base = { name, unit, quantity: qty, reorderLevel: level, updatedAt: new Date(), supplier: supplier.trim(), linkedDishIds: [...linked], isDemoSample: existing?.isDemoSample ?? false };
    const toSave: InventoryItem = existing ? { ...existing, ...base } : { id: newInventoryItemId(name), ...base };
    const ok = await run(() => saveInventoryItem(toSave), { success: `Saved ${name.trim()}` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={item != null}
      onClose={onClose}
      title={existing ? `Edit ${existing.name}` : 'Add item'}
      icon={Package}
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 pb-2">
        <TextField label="Name" maxLength={40} value={name} onChange={(e) => setName(e.target.value)} />
        <div className="grid grid-cols-2 gap-3">
          <TextField label={existing ? 'Stock (use Adjust)' : 'Opening stock'} inputMode="decimal" disabled={existing != null} value={quantity} onChange={(e) => setQuantity(e.target.value)} />
          <Select label="Unit" value={unit} onChange={(e) => setUnit(e.target.value)}>
            {Stock.units.map((u) => (
              <option key={u} value={u}>
                {u}
              </option>
            ))}
          </Select>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <TextField label="Reorder level" inputMode="decimal" value={reorder} onChange={(e) => setReorder(e.target.value)} />
          <TextField label="Supplier (optional)" maxLength={40} value={supplier} onChange={(e) => setSupplier(e.target.value)} />
        </div>
        <div>
          <p className="mb-2 text-[12.5px] font-medium text-muted">Linked dishes (optional)</p>
          <div className="flex flex-wrap gap-1.5">
            {dishes.map((d) => {
              const on = linked.has(d.id);
              return (
                <button
                  key={d.id}
                  type="button"
                  aria-pressed={on}
                  onClick={() =>
                    setLinked((s) => {
                      const next = new Set(s);
                      if (on) next.delete(d.id);
                      else next.add(d.id);
                      return next;
                    })
                  }
                  className={cn('rounded-full border px-3 py-1.5 text-[12.5px] font-medium transition-colors', on ? 'border-transparent brand-fill' : 'border-line bg-panel-2 text-muted hover:text-ink')}
                >
                  {d.name}
                </button>
              );
            })}
          </div>
          <p className="mt-2 text-[12px] text-faint">Linked dishes are marked sold out when this item runs out (if that rule is on in Settings).</p>
        </div>
        {error && (
          <p role="alert" className="text-[12.5px] text-danger">
            {error}
          </p>
        )}
      </div>
    </Dialog>
  );
}
