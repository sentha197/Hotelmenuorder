import { Armchair, Ban, CircleCheck, CircleX, FileText, Plus, ReceiptText, SearchX, ShoppingBag, StickyNote, Star } from 'lucide-react';
import { motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router';
import { BillSummary, FoodImage, OrderStatusBadge, PaymentStatusBadge, QuantityStepper, VegMark } from '@/components/domain/Domain';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { InfoRow, SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { FilterChips, SearchField, Segmented, Select, TextArea } from '@/components/ui/Form';
import { Empty, PageSkeleton } from '@/components/ui/Feedback';
import { Page } from '@/components/ui/Page';
import { comboViewOf, Combos, OfferRules, Promotions, type ComboView } from '@/core/offers';
import { Currency } from '@/core/money';
import { isOrderable, type MenuItem } from '@/core/menu';
import { OrderStatuses, Orders, TAKEAWAY_TABLE, type OrderStatus, type RestaurantOrder } from '@/core/orders';
import { CartLines, quoteCart, type CartLine } from '@/core/pricing';
import { pricingOf } from '@/core/settings';
import { AppFormat, DateRanges } from '@/core/time';
import { placeStaffOrder, useOrderBusy } from '@/state/actions';
import { useBills, useMenu, useOrders, useSettings, useTables } from '@/state/data';
import { useAction } from '@/state/run';
import { useAccess } from '@/state/session';
import { OrderCard } from './OrderCard';
import { actionIcon, advanceOrder, allowedAction, cancelOrder } from './orderActions';

type StatusFilter = 'active' | 'all' | 'placed' | 'accepted' | 'preparing' | 'ready' | 'served' | 'cancelled';
const statusFilters: StatusFilter[] = ['active', 'all', 'placed', 'accepted', 'preparing', 'ready', 'served', 'cancelled'];
const statusFilterLabel: Record<StatusFilter, string> = {
  active: 'Active',
  all: 'All',
  placed: 'New',
  accepted: 'Accepted',
  preparing: 'Preparing',
  ready: 'Ready',
  served: 'Served',
  cancelled: 'Cancelled',
};
const statusOf: Partial<Record<StatusFilter, OrderStatus>> = { placed: 'placed', accepted: 'accepted', preparing: 'preparing', ready: 'readyToServe', served: 'served', cancelled: 'cancelled' };
const matchesStatus = (f: StatusFilter, o: RestaurantOrder) => (f === 'active' ? Orders.isActive(o) : f === 'all' ? true : o.status === statusOf[f]);

type Period = 'today' | 'week' | 'all';
const periodLabel: Record<Period, string> = { today: 'Today', week: 'Last 7 days', all: 'All time' };
type TypeFilter = 'all' | 'dineIn' | 'takeaway';
const typeLabel: Record<TypeFilter, string> = { all: 'Dine-in & takeaway', dineIn: 'Dine-in', takeaway: 'Takeaway' };
const matchesType = (t: TypeFilter, o: RestaurantOrder) => (t === 'all' ? true : t === 'takeaway' ? Orders.isTakeaway(o) : !Orders.isTakeaway(o));

const PAGE = 80;

/** Live order management for staff (AdminOrdersScreen). */
export function OrdersPage() {
  const navigate = useNavigate();
  const { can } = useAccess();
  const query = useOrders();
  const orders = query.data ?? [];
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<StatusFilter>('active');
  const [period, setPeriod] = useState<Period>('all');
  const [type, setType] = useState<TypeFilter>('all');
  const [limit, setLimit] = useState(PAGE);

  const { scoped, inScope, shown } = useMemo(() => {
    const now = new Date();
    const inPeriod = (o: RestaurantOrder) =>
      period === 'all' ? true : DateRanges.contains(DateRanges.preset(period === 'today' ? 'today' : 'last7', now), o.createdAt);
    const matchesQuery = (o: RestaurantOrder) => {
      const q = search.trim().toLowerCase().replaceAll('#', '');
      if (!q) return true;
      if (o.id.toLowerCase().includes(q)) return true;
      if ('takeaway'.startsWith(q.replaceAll(' ', '')) && q.length >= 3) return Orders.isTakeaway(o);
      const table = Number.parseInt(q.replace(/^t(able)?\s*/, ''), 10);
      // Table 0 is how takeaway is stored, not a table anyone searches for.
      return Number.isFinite(table) && table > 0 && o.tableNumber === table;
    };
    const inScope = orders.filter((o) => inPeriod(o) && matchesQuery(o));
    const scoped = inScope.filter((o) => matchesType(type, o));
    const shown = scoped
      .filter((o) => matchesStatus(status, o))
      // Active orders oldest first (queue), others newest first.
      .sort((a, b) => (status === 'active' ? a.createdAt.getTime() - b.createdAt.getTime() : b.createdAt.getTime() - a.createdAt.getTime()));
    return { inScope, scoped, shown };
  }, [orders, period, search, type, status]);

  return (
    <Page
      title="Orders"
      subtitle={`${orders.filter(Orders.isActive).length} in progress`}
      actions={
        can('createOrders') && (
          <Button variant="primary" icon={Plus} onClick={() => navigate('/orders/new')}>
            New order
          </Button>
        )
      }
    >
      <SearchField value={search} onChange={setSearch} placeholder='Search order id, table number or "takeaway"' />
      <div className="flex flex-col gap-2.5">
        <FilterChips name="orders-period" values={['today', 'week', 'all'] as Period[]} selected={period} labelOf={(p) => periodLabel[p]} onSelect={setPeriod} />
        <FilterChips name="orders-type" values={['all', 'dineIn', 'takeaway'] as TypeFilter[]} selected={type} labelOf={(t) => typeLabel[t]} countOf={(t) => inScope.filter((o) => matchesType(t, o)).length} onSelect={setType} />
        <FilterChips name="orders-status" values={statusFilters} selected={status} labelOf={(s) => statusFilterLabel[s]} countOf={(s) => scoped.filter((o) => matchesStatus(s, o)).length} onSelect={setStatus} />
      </div>
      {query.isPending ? (
        <PageSkeleton />
      ) : shown.length === 0 ? (
        <Empty icon={ReceiptText} title="No orders here" message="Try another filter or period." />
      ) : (
        <>
          <div className="grid gap-3 md:grid-cols-2 2xl:grid-cols-3">
            {shown.slice(0, limit).map((o, i) => (
              <OrderCard key={o.id} order={o} index={i} />
            ))}
          </div>
          {shown.length > limit && (
            <div className="flex flex-col items-center gap-2">
              <p className="text-[12px] text-faint">
                Showing {limit} of {shown.length}.
              </p>
              <Button onClick={() => setLimit((l) => l + PAGE)}>Show more</Button>
            </div>
          )}
        </>
      )}
    </Page>
  );
}

/** One order for staff: lines, status history, bill and the next step (AdminOrderDetailScreen). */
export function OrderDetailPage() {
  const { orderId = '' } = useParams();
  const navigate = useNavigate();
  const { can } = useAccess();
  const query = useOrders();
  const order = (query.data ?? []).find((o) => o.id === orderId);
  const invoice = (useBills().data ?? []).find((i) => i.orderId === orderId);
  const busy = useOrderBusy(orderId);
  if (query.isPending) return <Page title="Order" back="/orders"><PageSkeleton rows={3} /></Page>;
  if (!order) {
    return (
      <Page title="Order" back="/orders">
        <Empty icon={SearchX} title="Order not found" message="It may be older than 90 days, or it was removed." />
      </Page>
    );
  }
  const takeaway = Orders.isTakeaway(order);
  const action = allowedAction(order, can);
  const canCancel = OrderStatuses.canCancel(order.status) && can('cancelOrders');
  const now = new Date();
  const ActionIcon = action ? actionIcon[action.icon] : null;
  const history = (Object.entries(order.statusTimes) as [OrderStatus, Date][]).sort((a, b) => a[1].getTime() - b[1].getTime());
  return (
    <Page title={`Order ${AppFormat.orderNumber(order.id)}`} subtitle={`${Orders.tableLabel(order)} · ${AppFormat.dateTime(order.createdAt)}`} back="/orders" width="medium">
      <SectionCard index={0}>
        <div className="flex flex-wrap items-center gap-3">
          <h2 className="flex-1 text-[22px] font-bold text-ink">{Orders.tableLabel(order)}</h2>
          <OrderStatusBadge status={order.status} takeaway={takeaway} />
        </div>
        <div className="mt-3 divide-y divide-line">
          <InfoRow label="Placed" value={AppFormat.dateTime(order.createdAt)} />
          {Orders.isActive(order) && <InfoRow label="Age" value={`${AppFormat.minutes(Orders.ageInMinutes(order, now))}${Orders.isOverdue(order, now) ? ' · past the estimate' : ''}`} />}
          <InfoRow label="Ready estimate" value={AppFormat.time(order.estimatedReadyAt)} />
          <InfoRow label="Source" value={order.source === 'guest' ? 'Guest (QR ordering)' : order.source === 'staff' ? 'Entered by staff' : 'Sample data'} />
          {Orders.isCancelled(order) && <InfoRow label="Cancelled" value={order.cancelReason || '—'} />}
        </div>
        {(action || canCancel) && (
          <div className="mt-5 flex flex-wrap gap-2">
            {action && ActionIcon && (
              <Button variant={action.target === 'served' ? 'success' : 'primary'} size="lg" icon={ActionIcon} loading={busy} onClick={() => void advanceOrder(order)} className="min-w-[180px] flex-1">
                {action.label}
              </Button>
            )}
            {canCancel && (
              <Button variant="danger" size="lg" icon={Ban} disabled={busy} onClick={() => void cancelOrder(order)} className="min-w-[160px] flex-1">
                Cancel order
              </Button>
            )}
          </div>
        )}
      </SectionCard>

      <SectionCard title={`Items (${Orders.itemCount(order)})`} index={1}>
        <ul className="divide-y divide-line">
          {order.lines.map((line, i) => (
            <li key={`${line.itemId}-${i}`} className="flex items-start gap-3 py-3">
              <FoodImage src={line.image} size={48} />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-2 text-[14px] font-semibold text-ink">
                  <VegMark veg={line.isVeg} />
                  <span className="truncate">
                    {line.quantity} × {line.name}
                  </span>
                </p>
                {line.options.length > 0 && <p className="mt-0.5 text-[12.5px] text-muted">{line.options.join(' · ')}</p>}
              </div>
              <span className="text-[13.5px] font-semibold tabular text-ink">{Currency.format(line.unitPrice * line.quantity)}</span>
            </li>
          ))}
        </ul>
        {order.specialInstructions && (
          <div className="mt-3 flex items-start gap-2 rounded-xl bg-warning/10 px-3.5 py-3 text-[13px] text-warning">
            <StickyNote size={16} className="mt-0.5 shrink-0" aria-hidden />
            {order.specialInstructions}
          </div>
        )}
      </SectionCard>

      <SectionCard title="Status history" index={2}>
        <ol className="flex flex-col gap-3">
          {history.map(([status, at]) => (
            <li key={status} className="flex items-center gap-3">
              {status === 'cancelled' ? <CircleX size={18} className="text-danger" aria-hidden /> : <CircleCheck size={18} className="text-success" aria-hidden />}
              <span className="flex-1 text-[13.5px] font-medium text-ink">{OrderStatuses.label(status)}</span>
              <span className="text-[12px] tabular text-faint">{AppFormat.time(at)}</span>
            </li>
          ))}
        </ol>
      </SectionCard>

      <SectionCard title="Bill" trailing={invoice && <PaymentStatusBadge status={invoice.status} />} index={3}>
        <BillSummary bill={order.bill} paid={invoice?.amountPaid} refunded={invoice?.amountRefunded} outstanding={invoice?.outstanding} />
        {invoice && can('viewBills') && (
          <Button icon={FileText} block className="mt-4" onClick={() => navigate(`/bills/${encodeURIComponent(invoice.id)}`)}>
            Open bill {invoice.billNumber}
          </Button>
        )}
      </SectionCard>

      {order.feedback && (
        <SectionCard
          title="Guest feedback"
          index={4}
          trailing={
            <span className="flex gap-0.5" aria-label={`${order.feedback.rating} of 5 stars`}>
              {[1, 2, 3, 4, 5].map((n) => (
                <Star key={n} size={16} className={n <= order.feedback!.rating ? 'fill-[#ffc83d] text-[#ffc83d]' : 'text-line-strong'} aria-hidden />
              ))}
            </span>
          }
        >
          <p className="text-[13.5px] text-muted">{order.feedback.comment ? `"${order.feedback.comment}"` : 'No comment.'}</p>
        </SectionCard>
      )}
    </Page>
  );
}

/**
 * Staff order entry for a table, or a takeaway order collected at the counter
 * (NewOrderScreen). Dishes use their default options; special offers and
 * combos apply as they do for guests, and the server prices the order again.
 */
export function NewOrderPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { settings } = useSettings();
  const tables = (useTables().data ?? []).filter((t) => t.isActive);
  const menuQuery = useMenu();
  const menu = menuQuery.data;
  const initialTable = Number(params.get('table')) || null;
  const [type, setType] = useState<'dineIn' | 'takeaway'>('dineIn');
  const [table, setTable] = useState<number | null>(initialTable);
  const [search, setSearch] = useState('');
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [instructions, setInstructions] = useState('');
  const [lines, setLines] = useState<CartLine[]>([]);
  const { pending, run } = useAction();

  const takeawayOpen = settings.takeawayOrdersEnabled;
  // Takeaway may have been closed while this screen was open.
  const effectiveType = type === 'takeaway' && !takeawayOpen ? 'dineIn' : type;
  const today = OfferRules.today();
  const allItems = menu?.items ?? [];
  const promotions = menu?.promotions ?? [];
  const specials = Promotions.liveSpecials(promotions, today);
  const q = search.trim().toLowerCase();
  const dishes = allItems.filter((i) => isOrderable(i) && (categoryId == null || i.category.id === categoryId) && (!q || i.name.toLowerCase().includes(q)));
  const byId = new Map(allItems.map((i) => [i.id, i]));
  const combos: ComboView[] =
    categoryId != null
      ? []
      : [...promotions]
          .sort(Promotions.byOrder)
          .filter((p) => p.kind === 'combo' && Promotions.isLiveOn(p, today))
          .map((p) => comboViewOf(p, byId))
          .filter((v): v is ComboView => v != null && v.dishes.every((d) => !d.item.isArchived) && Combos.dishesOrderable(v) && (!q || v.combo.title.toLowerCase().includes(q)));
  const quote = quoteCart(lines, specials, pricingOf(settings));
  const activeCategories = (menu?.categories ?? []).filter((c) => c.isActive).sort((a, b) => a.sortOrder - b.sortOrder);

  const quantityOfItem = (id: string) => lines.filter((l) => !l.combo && l.item.id === id).reduce((s, l) => s + l.quantity, 0);
  const quantityOfCombo = (id: string) => lines.find((l) => l.combo?.combo.id === id)?.quantity ?? 0;
  const bump = (id: string, delta: number, make: () => CartLine) =>
    setLines((current) => {
      const existing = current.find((l) => l.id === id);
      if (!existing) return delta > 0 ? [...current, make()] : current;
      const next = Math.min(existing.quantity + delta, CartLines.maxQuantity);
      return next <= 0 ? current.filter((l) => l.id !== id) : current.map((l) => (l.id === id ? { ...l, quantity: next } : l));
    });
  const addDish = (item: MenuItem, delta: number) => bump(CartLines.dish(item).id, delta, () => CartLines.dish(item));
  const addCombo = (view: ComboView, delta: number) => bump(CartLines.combo(view, 1, true).id, delta, () => CartLines.combo(view, 1, true));

  const place = () =>
    run(async () => {
      const order = await placeStaffOrder({
        lines,
        quote,
        tableNumber: effectiveType === 'takeaway' ? TAKEAWAY_TABLE : table,
        instructions,
        isTableOrderable: (n) => (n === TAKEAWAY_TABLE ? settings.takeawayOrdersEnabled : tables.some((t) => t.number === n && t.isActive)),
      });
      navigate(`/orders/${encodeURIComponent(order.id)}`, { replace: true });
    });

  if (menuQuery.isPending) return <Page title="New order" back="/orders"><PageSkeleton /></Page>;

  return (
    <Page title="New order" subtitle="For a table, or a takeaway collected at the counter" back="/orders">
      <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="flex min-w-0 flex-col gap-5">
          <SectionCard title="Order type" index={0}>
            <Segmented
              name="order-type"
              className="w-full"
              value={effectiveType}
              onChange={setType}
              options={[
                { value: 'dineIn', label: 'Dine-in', icon: <Armchair size={16} aria-hidden /> },
                { value: 'takeaway', label: 'Takeaway', icon: <ShoppingBag size={16} aria-hidden />, disabled: !takeawayOpen },
              ]}
            />
            <div className="mt-4">
              {effectiveType === 'takeaway' ? (
                <p className="text-[12.5px] text-muted">Collected at the counter. No table is needed; the kitchen ticket and the bill say Takeaway.</p>
              ) : (
                <>
                  <Select aria-label="Table" value={table ?? ''} onChange={(e) => setTable(e.target.value ? Number(e.target.value) : null)}>
                    <option value="">Choose a table</option>
                    {tables.map((t) => (
                      <option key={t.number} value={t.number}>
                        Table {AppFormat.table(t.number)} · {t.seats} seats{t.area ? ` · ${t.area}` : ''}
                      </option>
                    ))}
                  </Select>
                  {!takeawayOpen && <p className="mt-2 text-[12px] text-faint">Takeaway is closed. It can be opened in Tables &amp; QR.</p>}
                </>
              )}
            </div>
          </SectionCard>

          <SearchField value={search} onChange={setSearch} placeholder="Search dishes" />
          <FilterChips
            name="new-order-category"
            values={[null, ...activeCategories.map((c) => c.id)]}
            selected={categoryId}
            labelOf={(id) => (id == null ? 'All' : (activeCategories.find((c) => c.id === id)?.label ?? id))}
            onSelect={setCategoryId}
          />

          {combos.length > 0 && (
            <SectionCard title="Combos" index={1}>
              <ul className="divide-y divide-line">
                {combos.map((view) => (
                  <PickRow
                    key={view.combo.id}
                    image={Combos.image(view)}
                    title={view.combo.title}
                    detail={Combos.partLabels(view).join(' + ')}
                    price={Combos.price(view)}
                    original={Combos.originalPrice(view)}
                    quantity={quantityOfCombo(view.combo.id)}
                    onAdd={() => addCombo(view, 1)}
                    onRemove={() => addCombo(view, -1)}
                  />
                ))}
              </ul>
            </SectionCard>
          )}

          <SectionCard index={2}>
            {dishes.length === 0 ? (
              <Empty compact icon={SearchX} title="No dishes match" message="Sold-out and archived dishes are not listed." />
            ) : (
              <ul className="divide-y divide-line">
                {dishes.map((item) => {
                  const special = Promotions.bestSpecial(item.id, item.price, specials);
                  return (
                    <PickRow
                      key={item.id}
                      image={item.image}
                      veg={item.isVeg}
                      title={item.name}
                      price={special ? item.price - Promotions.unitDiscount(special.offer, item.price) : item.price}
                      original={special ? item.price : undefined}
                      badge={special ? Promotions.badge(special.offer) : undefined}
                      quantity={quantityOfItem(item.id)}
                      onAdd={() => addDish(item, 1)}
                      onRemove={() => addDish(item, -1)}
                    />
                  );
                })}
              </ul>
            )}
          </SectionCard>
        </div>

        <aside className="flex min-w-0 flex-col gap-5 lg:sticky lg:top-24">
          <SectionCard title="Summary" subtitle={lines.length ? `${lines.reduce((s, l) => s + l.quantity, 0)} items` : 'Add dishes to start'} index={3}>
            {lines.length > 0 && (
              <ul className="mb-4 flex flex-col gap-2">
                {lines.map((l) => (
                  <li key={l.id} className="flex items-center gap-2 text-[13px]">
                    <span className="min-w-0 flex-1 truncate text-ink">
                      {l.quantity} × {l.item.name}
                    </span>
                    <span className="tabular text-muted">{Currency.format(CartLines.lineTotal(l))}</span>
                  </li>
                ))}
              </ul>
            )}
            {lines.length > 0 && <BillSummary bill={quote.bill} />}
            <div className="mt-4">
              <TextArea label="Special instructions" placeholder="Optional" rows={2} maxLength={CartLines.maxInstructionsLength} showCount value={instructions} onChange={(e) => setInstructions(e.target.value)} />
            </div>
            <Button variant="primary" size="lg" block className="mt-4" loading={pending} disabled={lines.length === 0} onClick={() => void place()}>
              {lines.length === 0 ? 'Add dishes to place an order' : `Place order · ${Currency.format(quote.bill.total)}`}
            </Button>
          </SectionCard>
        </aside>
      </div>
      {/* Phones and tablets: the order button stays in reach while choosing dishes. */}
      {lines.length > 0 && (
        <motion.div initial={{ y: 40, opacity: 0 }} animate={{ y: 0, opacity: 1 }} className="no-print fixed inset-x-0 bottom-[calc(70px+env(safe-area-inset-bottom))] z-20 px-4 md:bottom-4 lg:hidden">
          <div className="panel-solid mx-auto flex max-w-xl items-center gap-3 rounded-2xl p-2.5 pl-4">
            <span className="min-w-0 flex-1 text-[13px] text-muted">
              {lines.reduce((s, l) => s + l.quantity, 0)} items · <span className="font-bold tabular text-ink">{Currency.format(quote.bill.total)}</span>
            </span>
            <Button variant="primary" loading={pending} onClick={() => void place()}>
              Place order
            </Button>
          </div>
        </motion.div>
      )}
    </Page>
  );
}

function PickRow({
  image,
  veg,
  title,
  detail,
  price,
  original,
  badge,
  quantity,
  onAdd,
  onRemove,
}: {
  image: string;
  veg?: boolean;
  title: string;
  detail?: string;
  price: number;
  original?: number;
  badge?: string;
  quantity: number;
  onAdd: () => void;
  onRemove: () => void;
}) {
  return (
    <li className="flex items-center gap-3 py-3">
      <FoodImage src={image} size={48} />
      <div className="min-w-0 flex-1">
        <p className="flex items-center gap-2 text-[13.5px] font-semibold text-ink">
          {veg != null && <VegMark veg={veg} size={11} />}
          <span className="truncate">{title}</span>
        </p>
        {detail && <p className="line-clamp-2 text-[12px] text-faint">{detail}</p>}
        <p className="mt-0.5 flex flex-wrap items-center gap-2 text-[12.5px]">
          <span className={cn('font-semibold tabular', original != null && original !== price ? 'text-success' : 'text-muted')}>{Currency.format(price)}</span>
          {original != null && original !== price && <span className="tabular text-faint line-through">{Currency.format(original)}</span>}
          {badge && <Badge tone="success">{badge}</Badge>}
        </p>
      </div>
      {quantity === 0 ? (
        <motion.button whileTap={{ scale: 0.9 }} type="button" aria-label={`Add ${title}`} onClick={onAdd} className="grid h-9 w-9 shrink-0 place-items-center rounded-xl brand-fill shadow-glow">
          <Plus size={18} aria-hidden />
        </motion.button>
      ) : (
        <QuantityStepper quantity={quantity} onIncrement={onAdd} onDecrement={onRemove} max={CartLines.maxQuantity} label={title} />
      )}
    </li>
  );
}

