import { BellRing, CircleCheck, ConciergeBell, CookingPot, RefreshCw, ShoppingBag, StickyNote, type LucideIcon } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useMemo, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { cn, toneStyle, type Tone } from '@/components/ui/cn';
import { FilterChips, Segmented } from '@/components/ui/Form';
import { Empty, PageSkeleton } from '@/components/ui/Feedback';
import { Page } from '@/components/ui/Page';
import { VegMark } from '@/components/domain/Domain';
import { OrderStatuses, Orders, type RestaurantOrder } from '@/core/orders';
import { AppFormat } from '@/core/time';
import { useOrderBusy } from '@/state/actions';
import { keys, queryClient, useOrders } from '@/state/data';
import { runAction } from '@/state/run';
import { useAccess } from '@/state/session';
import { actionIcon, advanceOrder, allowedAction } from '../orders/orderActions';

type Lane = 'incoming' | 'cooking' | 'ready' | 'done';
const working: Lane[] = ['incoming', 'cooking', 'ready'];
const DONE_WINDOW = 4 * 3_600_000;

const lanes: Record<Lane, { label: string; hint: string; icon: LucideIcon; tone: Tone; empty: string }> = {
  incoming: { label: 'New', hint: 'Waiting to be accepted or started', icon: BellRing, tone: 'brand', empty: 'New orders will appear here as guests place them.' },
  cooking: { label: 'Preparing', hint: 'On the stove', icon: CookingPot, tone: 'ember', empty: 'Nothing is being prepared right now.' },
  ready: { label: 'Ready', hint: 'Waiting for service', icon: ConciergeBell, tone: 'success', empty: 'Nothing is waiting to be served.' },
  done: { label: 'Done', hint: 'Served in the last 4 hours', icon: CircleCheck, tone: 'muted', empty: 'Nothing has been served in the last 4 hours.' },
};

const inLane = (lane: Lane, o: RestaurantOrder) =>
  lane === 'incoming' ? o.status === 'placed' || o.status === 'accepted' : lane === 'cooking' ? o.status === 'preparing' : lane === 'ready' ? o.status === 'readyToServe' : o.status === 'served';

const servedAt = (o: RestaurantOrder) => o.statusTimes.served ?? o.createdAt;

/**
 * Kitchen display: orders grouped by stage, oldest first. Narrow screens get
 * one lane at a time behind chips; wide screens show the three working lanes
 * side by side (KitchenScreen). Ages refresh every 30 seconds.
 */
export function KitchenPage() {
  const query = useOrders();
  const orders = query.data ?? [];
  const [lane, setLane] = useState<Lane>('incoming');
  const [showDone, setShowDone] = useState(false);
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(timer);
  }, []);

  const { active, done } = useMemo(() => {
    const active = orders.filter(Orders.isActive).sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
    const done = orders.filter((o) => o.status === 'served' && now.getTime() - servedAt(o).getTime() < DONE_WINDOW).sort((a, b) => servedAt(b).getTime() - servedAt(a).getTime());
    return { active, done };
  }, [orders, now]);
  const laneOrders = (l: Lane) => (l === 'done' ? done.slice(0, 30) : active.filter((o) => inLane(l, o)));
  const overdue = active.filter((o) => Orders.isOverdue(o, now)).length;
  const subtitle = [`${active.length} active`, ...(overdue > 0 ? [`${overdue} past the estimate`] : []), `${done.length} served recently`].join(' · ');

  return (
    <Page
      title="Kitchen"
      subtitle={subtitle}
      width="full"
      actions={
        <Button icon={RefreshCw} onClick={() => void runAction(() => queryClient.refetchQueries({ queryKey: keys.orders }))}>
          Refresh
        </Button>
      }
    >
      {query.isPending ? (
        <PageSkeleton />
      ) : (
        <>
          {/* Phones and tablets: one lane at a time. */}
          <div className="flex flex-col gap-4 xl:hidden">
            <FilterChips name="kitchen-lane" values={['incoming', 'cooking', 'ready', 'done'] as Lane[]} selected={lane} labelOf={(l) => lanes[l].label} countOf={(l) => laneOrders(l).length} onSelect={setLane} />
            <p className="text-[12.5px] text-muted">{lanes[lane].hint}</p>
            <LaneList lane={lane} orders={laneOrders(lane)} now={now} />
          </div>
          {/* A kitchen display: the working lanes side by side. */}
          <div className="hidden flex-col gap-4 xl:flex">
            <Segmented
              name="kitchen-view"
              value={showDone}
              onChange={setShowDone}
              options={[
                { value: false, label: `Active (${active.length})` },
                { value: true, label: `Completed (${done.length})` },
              ]}
            />
            {showDone ? (
              <LaneList lane="done" orders={laneOrders('done')} now={now} grid />
            ) : (
              <div className="grid grid-cols-3 items-start gap-4">
                {working.map((l) => (
                  <section key={l} className="panel flex min-h-[60vh] flex-col p-3" style={toneStyle(lanes[l].tone)}>
                    <header className="flex items-center gap-2.5 px-2 pb-3 pt-1">
                      <span className="tone grid h-8 w-8 place-items-center rounded-lg">
                        {(() => {
                          const Icon = lanes[l].icon;
                          return <Icon size={16} aria-hidden />;
                        })()}
                      </span>
                      <div className="min-w-0 flex-1">
                        <h2 className="text-[14px] font-semibold text-ink">{lanes[l].label}</h2>
                        <p className="text-[11.5px] text-faint">{lanes[l].hint}</p>
                      </div>
                      <span className="tone min-w-8 rounded-full px-2 py-0.5 text-center text-[12px] font-bold tabular">{laneOrders(l).length}</span>
                    </header>
                    <LaneList lane={l} orders={laneOrders(l)} now={now} />
                  </section>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </Page>
  );
}

function LaneList({ lane, orders, now, grid }: { lane: Lane; orders: RestaurantOrder[]; now: Date; grid?: boolean }) {
  if (orders.length === 0) return <Empty compact icon={lanes[lane].icon} title={lane === 'done' ? 'Nothing done yet' : `Nothing in ${lanes[lane].label.toLowerCase()}`} message={lanes[lane].empty} />;
  return (
    <div className={cn('grid gap-3', grid ? 'sm:grid-cols-2 2xl:grid-cols-3' : 'sm:grid-cols-2 xl:grid-cols-1')}>
      <AnimatePresence initial={false}>
        {orders.map((o) => (
          <Ticket key={o.id} order={o} lane={lane} now={now} />
        ))}
      </AnimatePresence>
    </div>
  );
}

/** One order: where it came from, what to cook, and the next step (_TicketCard). */
function Ticket({ order, lane, now }: { order: RestaurantOrder; lane: Lane; now: Date }) {
  const { can } = useAccess();
  const busy = useOrderBusy(order.id);
  const takeaway = Orders.isTakeaway(order);
  const overdue = Orders.isOverdue(order, now);
  const age = Orders.ageInMinutes(order, now);
  const overBy = Math.floor((now.getTime() - order.estimatedReadyAt.getTime()) / 60_000);
  const action = allowedAction(order, can);
  const ActionIcon = action ? actionIcon[action.icon] : null;
  // An overdue ticket is called out in red whichever lane it sits in.
  const tone: Tone = overdue ? 'danger' : lanes[lane].tone;
  return (
    <motion.article
      layout
      initial={{ opacity: 0, scale: 0.97, y: 8 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.96 }}
      transition={{ type: 'spring', stiffness: 420, damping: 34 }}
      style={toneStyle(tone)}
      className={cn('relative overflow-hidden rounded-2xl border bg-panel-solid p-4 pl-5', overdue ? 'border-danger/60' : 'border-line')}
    >
      <span className="absolute inset-y-0 left-0 w-1.5 bg-[var(--tone)]" aria-hidden />
      <header className="flex items-center gap-3">
        <div className="tone grid h-12 w-12 shrink-0 place-items-center rounded-xl text-center leading-none">
          <div>
            <div className="text-[7px] font-bold uppercase tracking-[0.12em] opacity-80">{takeaway ? 'Takeaway' : 'Table'}</div>
            {takeaway ? <ShoppingBag size={18} className="mx-auto mt-0.5" aria-label="Takeaway" /> : <div className="mt-0.5 text-[17px] font-extrabold tabular">{AppFormat.table(order.tableNumber)}</div>}
          </div>
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[14px] font-semibold text-ink">{AppFormat.orderNumber(order.id)}</p>
          <p className="text-[12px] text-faint">
            {order.status === 'accepted'
              ? `Accepted · ${AppFormat.minutes(age)}`
              : order.status === 'served'
                ? `${OrderStatuses.shortLabel('served', takeaway)} ${AppFormat.time(order.statusTimes.served ?? now)}`
                : AppFormat.minutes(age)}
          </p>
        </div>
        {overdue && (
          <span className="rounded-full bg-danger px-2 py-1 text-[11px] font-bold text-white" title={overBy < 1 ? 'Due now' : `Past the preparation estimate by ${overBy} minutes`}>
            {overBy < 1 ? 'Due now' : `+${overBy} min`}
          </span>
        )}
      </header>
      <ul className="mt-3 flex flex-col gap-2">
        {order.lines.map((line, i) => (
          <li key={`${line.itemId}-${i}`} className="flex items-start gap-2.5">
            <span className="min-w-8 rounded-lg bg-panel-3 px-1.5 py-0.5 text-center text-[13px] font-bold tabular text-ink">{line.quantity}×</span>
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-1.5 text-[14px] font-semibold text-ink">
                <VegMark veg={line.isVeg} size={10} />
                {line.name}
              </p>
              {line.options.length > 0 && <p className="text-[12px] text-muted">{line.options.join(' · ')}</p>}
            </div>
          </li>
        ))}
      </ul>
      {order.specialInstructions && (
        <p className="mt-3 flex items-start gap-2 rounded-xl bg-warning/12 px-3 py-2 text-[12.5px] font-medium text-warning">
          <StickyNote size={14} className="mt-0.5 shrink-0" aria-hidden />
          {order.specialInstructions}
        </p>
      )}
      {action && ActionIcon && (
        <Button
          block
          className="mt-3"
          // Finishing a dish is the green step, as elsewhere.
          variant={action.target === 'readyToServe' || action.target === 'served' ? 'success' : 'primary'}
          icon={ActionIcon}
          loading={busy}
          onClick={() => void advanceOrder(order)}
        >
          {action.label}
        </Button>
      )}
    </motion.article>
  );
}
