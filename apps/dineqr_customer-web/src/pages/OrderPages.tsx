import { Bike, CalendarCheck, ChefHat, Clock, ConciergeBell, History, Layers, ReceiptText, ShoppingBag, Star, ThumbsUp, UtensilsCrossed, Wallet, X, XCircle } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router';
import { BillSummary } from '../components/bill';
import { orderAccent, OrderStatusBadge, PaymentStatusBadge } from '../components/badges';
import { Lockup } from '../components/brand';
import { FoodImage } from '../components/food';
import { FeedbackSheet, OrderBillCard, TrackingTimeline } from '../components/orders';
import { AppBar, BrandPanel, Button, Card, Confetti, DemoTag, EmptyState, FadeIn, IconButton, IconHalo, MaskedText, StarRow, SuccessEmblem, VegIndicator } from '../components/ui';
import { invoiceStatusLabel } from '../core/billing';
import { Currency } from '../core/money';
import { lineTotal, OrderStatuses, type RestaurantOrder } from '../core/orders';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { emblemSize, iconSize, lockupHeight } from '../components/sizes';

/** Opens a bill, fetching it first when the order's bill is not loaded yet. */
function useOpenBill() {
  const { billing, orders, toasts } = useApp();
  const navigate = useNavigate();
  return async (orderId: string) => {
    let invoice = billing.forOrder(orderId);
    if (!invoice) {
      const order = orders.byId(orderId);
      if (!order) return;
      try {
        invoice = await billing.createForOrder(order);
      } catch (error) {
        toasts.show(error instanceof Error ? error.message : 'The bill could not be loaded.', { tone: 'error' });
        return;
      }
    }
    navigate(paths.bill(invoice.id));
  };
}

export function OrderPlacedPage() {
  const { orders, billing } = useApp();
  useStore(orders);
  useStore(billing);
  const { orderId = '' } = useParams();
  const navigate = useNavigate();
  const openBill = useOpenBill();
  const order = orders.byId(orderId);
  const invoice = billing.forOrder(orderId);
  if (!order) {
    return (
      <div>
        <AppBar />
        <EmptyState icon={<ReceiptText size={iconSize.hero} />} title="Order not found" message="We could not find this order." action={<Button onClick={() => navigate(paths.orders)}>View Orders</Button>} />
      </div>
    );
  }
  return (
    <div className="placed">
      <div className="welcome__wash" aria-hidden />
      <Confetti seed={11} count={30} />
      <div className="placed__bar">
        <IconButton label="Close" onClick={() => navigate(paths.home, { replace: true })}>
          <X size={iconSize.lg} />
        </IconButton>
        <span className="grow center">
          <Lockup height={lockupHeight.sm} />
        </span>
        <span className="app-bar__spacer" />
      </div>
      <div className="placed__content page page--narrow">
        <SuccessEmblem size={emblemSize.lg} delay={0.15} label="Order placed" />
        <h1 className="placed__title">
          <MaskedText by="line" delay={0.45}>
            Order Placed
          </MaskedText>
          <br />
          <MaskedText by="line" delay={0.58}>
            Successfully!
          </MaskedText>
        </h1>
        <FadeIn index={4}>
          <p className="t-secondary t-center" style={{ marginTop: 12 }}>
            {order.isTakeaway
              ? 'Your order has been sent to the kitchen. Follow its progress and collect it at the counter when it’s ready.'
              : 'Your order has been sent to the kitchen. Follow its progress and we will serve it at your table.'}
          </p>
        </FadeIn>
        <FadeIn index={5}>
          <BrandPanel lifted className="placed__card">
            <span className="t-overline" style={{ color: 'rgb(255 255 255 / 75%)' }}>
              ORDER NUMBER
            </span>
            <motion.span
              className="layered-text placed__number"
              initial={{ clipPath: 'inset(0 100% 0 0)' }}
              animate={{ clipPath: 'inset(0 0% 0 0)' }}
              transition={{ duration: 0.7, delay: 0.65, ease: [0.22, 1, 0.36, 1] }}
            >
              {AppFormat.orderNumber(order.id)}
            </motion.span>
            <div className="placed__stats">
              <Stat icon={order.isTakeaway ? <ShoppingBag size={iconSize.md} /> : <UtensilsCrossed size={iconSize.md} />} label={order.isTakeaway ? 'At the counter' : 'Table'} value={order.isTakeaway ? 'Takeaway' : AppFormat.table(order.tableNumber)} />
              <Stat icon={<Layers size={iconSize.md} />} label="Items" value={`${order.itemCount}`} />
              <Stat icon={<Wallet size={iconSize.md} />} label="Total" value={Currency.format(order.bill.total)} />
            </div>
            <p className="placed__info">
              <CalendarCheck size={iconSize.sm} /> Placed {AppFormat.dateTime(order.createdAt)}
            </p>
            <p className="placed__info">
              <Clock size={iconSize.sm} /> Estimated ready by {AppFormat.time(order.estimatedReadyAt)}
            </p>
            {invoice && (
              <p className="placed__info">
                <ReceiptText size={iconSize.sm} /> Bill {invoice.billNumber} · {invoiceStatusLabel[invoice.status]}
              </p>
            )}
          </BrandPanel>
        </FadeIn>
      </div>
      <div className="placed__actions page page--narrow">
        <FadeIn index={6} className="stack-md">
          <Button block icon={<Bike size={iconSize.lg} />} onClick={() => navigate(paths.tracking(order.id), { replace: true })}>
            Track Order
          </Button>
          <div className="row" style={{ gap: 12 }}>
            <Button variant="secondary" className="grow" icon={<ReceiptText size={iconSize.md} />} onClick={() => void openBill(order.id)}>
              View Bill
            </Button>
            <Button variant="secondary" className="grow" icon={<ReceiptText size={iconSize.md} />} onClick={() => navigate(paths.orders, { replace: true })}>
              My Orders
            </Button>
          </div>
        </FadeIn>
      </div>
    </div>
  );
}

function Stat({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="placed__stat">
      <span style={{ color: 'var(--warm-orange)' }}>{icon}</span>
      <strong className="ellipsis">{value}</strong>
      <span>{label}</span>
    </div>
  );
}

/** Live order status: staff changes arrive through the live connection. */
export function TrackingPage() {
  const { orders, billing } = useApp();
  useStore(orders);
  useStore(billing);
  const { orderId = '' } = useParams();
  const order = orders.byId(orderId);
  const invoice = billing.forOrder(orderId);
  const [rating, setRating] = useState(false);
  const lastStatus = useRef(order?.status);

  // Offer the rating sheet once the order reaches "served", whoever moved it.
  useEffect(() => {
    const previous = lastStatus.current;
    lastStatus.current = order?.status;
    if (!order || previous == null || previous === order.status) return;
    if (order.status === 'served' && order.canRate) {
      const timer = setTimeout(() => setRating(true), 650);
      return () => clearTimeout(timer);
    }
  }, [order]);

  if (!order) {
    return (
      <div>
        <AppBar title="Order Tracking" />
        <EmptyState icon={<ReceiptText size={iconSize.hero} />} title="Order not found" message="This order is no longer available." />
      </div>
    );
  }
  const steps = OrderStatuses.customerStages;
  const reached = order.isCancelled ? steps.filter((s) => order.statusTimes[s] != null).length : steps.indexOf(OrderStatuses.customerStage(order.status)) + 1;
  return (
    <div>
      <AppBar title="Order Tracking" />
      <div className="page page--narrow stack-xl">
        <FadeIn>
          <BrandPanel lifted>
            <div className="row-top">
              <div className="grow col">
                <span className="t-section" style={{ fontWeight: 700 }}>
                  Order {AppFormat.orderNumber(order.id)}
                </span>
                <span className="t-caption" style={{ color: 'rgb(255 255 255 / 80%)' }}>
                  {order.tableLabel} · {AppFormat.itemCount(order.itemCount)} · {AppFormat.time(order.createdAt)}
                </span>
              </div>
              <OrderStatusBadge status={order.status} type={order.type} />
            </div>
            <div className="progress" role="progressbar" aria-valuemin={0} aria-valuemax={steps.length} aria-valuenow={order.isCancelled ? 0 : reached}>
              <motion.span className="progress__bar" initial={false} animate={{ scaleX: order.isCancelled ? 0 : reached / steps.length }} transition={{ duration: 0.6, ease: [0.2, 0, 0, 1] }} />
            </div>
            <div className="row" style={{ marginTop: 6 }}>
              <span className="t-caption t-strong grow" style={{ color: 'rgb(255 255 255 / 85%)' }}>
                {order.isCancelled ? 'Order cancelled' : `Step ${reached} of ${steps.length}`}
              </span>
              {order.isActive && (
                <span className="t-caption t-strong" style={{ color: 'var(--peach)' }}>
                  Ready by {AppFormat.time(order.estimatedReadyAt)}
                </span>
              )}
            </div>
          </BrandPanel>
        </FadeIn>
        {order.isCancelled && (
          <FadeIn index={1}>
            <div className="notice notice--plain">
              <XCircle size={iconSize.lg} />
              <div className="grow">
                <p className="t-card-title" style={{ color: 'var(--text)' }}>
                  This order was cancelled
                </p>
                <p className="t-caption">{[order.cancelReason, order.statusTimes.cancelled ? AppFormat.dateTime(order.statusTimes.cancelled) : ''].filter(Boolean).join(' · ')}</p>
                <p className="t-caption">Please speak to a staff member if you have questions.</p>
              </div>
            </div>
          </FadeIn>
        )}
        <FadeIn index={1}>
          <TrackingTimeline order={order} />
        </FadeIn>
        {!order.isCancelled && (
          <FadeIn index={2}>
            <KitchenCard order={order} />
          </FadeIn>
        )}
        {invoice && (
          <FadeIn index={3}>
            <OrderBillCard invoice={invoice} />
          </FadeIn>
        )}
        {order.canRate ? (
          <Button block icon={<Star size={iconSize.lg} />} onClick={() => setRating(true)}>
            Rate Your Experience
          </Button>
        ) : order.feedback ? (
          <p className="row center t-label" aria-label={`You rated this order ${order.feedback.rating} out of 5`}>
            You rated this order <StarRow rating={order.feedback.rating} size={iconSize.md} />
          </p>
        ) : null}
      </div>
      <FeedbackSheet orderId={order.id} open={rating} onClose={() => setRating(false)} />
    </div>
  );
}

function KitchenCard({ order }: { order: RestaurantOrder }) {
  const reduced = useReducedMotion();
  const table = AppFormat.table(order.tableNumber);
  const content: Record<string, [React.ReactNode, string, string]> = {
    placed: [<ReceiptText size={iconSize.hero} key="i" />, 'Order received', 'Waiting for the kitchen to accept your order.'],
    accepted: [<ThumbsUp size={iconSize.hero} key="i" />, 'Accepted by the kitchen', 'Your order is in the queue and will be cooked shortly.'],
    preparing: [<ChefHat size={iconSize.hero} key="i" />, 'Your delicious food is being prepared', 'Our chefs are cooking everything fresh for you.'],
    readyToServe: order.isTakeaway
      ? [<ShoppingBag size={iconSize.hero} key="i" />, 'Ready to collect!', `Your order ${AppFormat.orderNumber(order.id)} is ready. Collect it at the counter.`]
      : [<ConciergeBell size={iconSize.hero} key="i" />, 'Ready to serve!', `Your food is ready and on its way to Table ${table}.`],
    served: [
      <UtensilsCrossed size={iconSize.hero} key="i" />,
      'Enjoy your meal!',
      order.isTakeaway ? 'Collected at the counter. We hope you love it.' : `Served at Table ${table}. We hope you love it.`,
    ],
  };
  const [icon, title, message] = content[order.status] ?? content.placed!;
  return (
    <Card soft>
      <div className="row" style={{ gap: 16 }}>
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={order.status}
            initial={reduced ? false : { scale: 0.5, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.8, opacity: 0 }}
            transition={{ type: 'spring', stiffness: 300, damping: 18 }}
          >
            <IconHalo size={emblemSize.md}>{icon}</IconHalo>
          </motion.div>
        </AnimatePresence>
        <AnimatePresence mode="wait" initial={false}>
          <motion.div key={order.status} className="grow col" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
            <span className="t-card-title">{title}</span>
            <span className="t-caption" style={{ marginTop: 4 }}>
              {message}
            </span>
          </motion.div>
        </AnimatePresence>
      </div>
    </Card>
  );
}

/** The Orders tab: current and past orders of this guest session. */
export function OrdersPage() {
  const { orders } = useApp();
  useStore(orders);
  const navigate = useNavigate();
  const reduced = useReducedMotion();
  const [params, setParams] = useSearchParams();
  const tab = params.get('tab') === 'past' ? 'past' : 'current';
  const current = orders.currentOrders;
  const past = orders.pastOrders;
  const list = tab === 'current' ? current : past;
  const [rateId, setRateId] = useState<string | null>(null);
  return (
    <div>
      <AppBar title="My Orders" onBack={() => navigate(paths.home)} />
      <div className="segmented" role="tablist" aria-label="Orders">
        {(['current', 'past'] as const).map((key) => (
          <button
            key={key}
            type="button"
            role="tab"
            aria-selected={tab === key}
            className={`segmented__tab ${tab === key ? 'is-selected' : ''}`}
            onClick={() => setParams(key === 'past' ? { tab: 'past' } : {}, { replace: true })}
          >
            {tab === key && <motion.span layoutId="orders-tab" className="segmented__pill" transition={reduced ? { duration: 0 } : { type: 'spring', stiffness: 500, damping: 38 }} />}
            <span className="segmented__label">
              {key === 'current' ? (current.length ? `Current (${current.length})` : 'Current Orders') : past.length ? `Past (${past.length})` : 'Past Orders'}
            </span>
          </button>
        ))}
      </div>
      <div className="page page--narrow">
        {list.length === 0 ? (
          tab === 'current' ? (
            <EmptyState
              icon={<ConciergeBell size={iconSize.hero} />}
              title="No active orders"
              message="Orders you place will appear here so you can track them."
              action={<Button onClick={() => navigate(paths.menu)}>Browse Menu</Button>}
            />
          ) : (
            <EmptyState icon={<History size={iconSize.hero} />} title="No past orders yet" message="Served orders move here once they reach your table." />
          )
        ) : (
          <div className="stack-lg" key={tab}>
            {list.map((order, index) => (
              <FadeIn key={order.id} index={index}>
                <OrderCard order={order} onRate={() => setRateId(order.id)} />
              </FadeIn>
            ))}
          </div>
        )}
      </div>
      {rateId && <FeedbackSheet orderId={rateId} open onClose={() => setRateId(null)} />}
    </div>
  );
}

function OrderCard({ order, onRate }: { order: RestaurantOrder; onRate: () => void }) {
  const { billing } = useApp();
  const navigate = useNavigate();
  const openBill = useOpenBill();
  const invoice = billing.forOrder(order.id);
  const hidden = order.lines.length - 3;
  return (
    <motion.article
      className="order-card"
      style={{ '--accent': orderAccent(order.status) } as React.CSSProperties}
      whileTap={{ scale: 0.985 }}
      onClick={() => navigate(paths.orderDetails(order.id))}
    >
      <div className="row-top">
        <div className="thumbs" aria-hidden>
          {order.lines.slice(0, 3).map((line, i) => (
            <span key={`${line.itemId}-${i}`} className="thumbs__item" style={{ left: i * 18 }}>
              <FoodImage src={line.image} width={30} height={30} radius="50%" />
            </span>
          ))}
        </div>
        <div className="grow col">
          <span className="t-card-title">
            Order {AppFormat.orderNumber(order.id)}
          </span>
          <span className="t-label t-primary t-strong">{order.tableLabel}</span>
          <span className="t-caption">{AppFormat.dateTime(order.createdAt)}</span>
        </div>
        <div className="col" style={{ alignItems: 'flex-end', gap: 6 }}>
          <OrderStatusBadge status={order.status} type={order.type} />
          {order.isDemoSample && <DemoTag label="SAMPLE" />}
        </div>
      </div>
      <hr className="dashed" style={{ margin: '12px 0' }} />
      {order.lines.slice(0, 3).map((line, i) => (
        <div key={`${line.itemId}-${i}`} className="row" style={{ padding: '3px 0' }}>
          <VegIndicator veg={line.isVeg} size={10} />
          <span className="t-label grow ellipsis">{line.name}</span>
          <span className="t-caption" style={{ width: 34 }}>
            x{line.quantity}
          </span>
          <span className="t-label tabular" style={{ minWidth: 64, textAlign: 'right' }}>
            {Currency.format(lineTotal(line))}
          </span>
        </div>
      ))}
      {hidden > 0 && <p className="t-caption">+ {hidden} more {hidden === 1 ? 'dish' : 'dishes'}</p>}
      <hr className="divider" style={{ margin: '12px 0' }} />
      <div className="row">
        <span className="t-card-title grow">Total Amount</span>
        <span className="t-price t-price--lg">
          {Currency.format(order.bill.total)}
        </span>
      </div>
      {invoice && (
        <div className="row" style={{ marginTop: 8 }}>
          <PaymentStatusBadge status={invoice.status} />
          <span className="t-caption t-strong grow ellipsis" style={{ textAlign: 'right', color: invoice.outstanding ? 'var(--accent-text)' : undefined }}>
            {invoice.outstanding === 0 ? `Bill ${invoice.billNumber}` : `Due ${Currency.format(invoice.outstanding)}`}
          </span>
        </div>
      )}
      {order.feedback && (
        <div className="row" style={{ marginTop: 8 }}>
          <span className="t-caption grow">Your rating</span>
          <StarRow rating={order.feedback.rating} />
        </div>
      )}
      <div className="row" style={{ marginTop: 12, gap: 12 }} onClick={(e) => e.stopPropagation()}>
        {order.isActive ? (
          <Button variant="secondary" compact className="grow" icon={<Bike size={iconSize.md} />} onClick={() => navigate(paths.tracking(order.id))}>
            Track
          </Button>
        ) : order.canRate ? (
          <Button variant="secondary" compact className="grow" icon={<Star size={iconSize.md} />} onClick={onRate}>
            Rate
          </Button>
        ) : (
          <Button variant="secondary" compact className="grow" icon={<ReceiptText size={iconSize.md} />} onClick={() => navigate(paths.orderDetails(order.id))}>
            Details
          </Button>
        )}
        <Button compact className="grow" icon={<ReceiptText size={iconSize.md} />} onClick={() => void openBill(order.id)}>
          View Bill
        </Button>
      </div>
    </motion.article>
  );
}

export function OrderDetailsPage() {
  const { orders, billing } = useApp();
  useStore(orders);
  useStore(billing);
  const { orderId = '' } = useParams();
  const navigate = useNavigate();
  const order = orders.byId(orderId);
  const invoice = billing.forOrder(orderId);
  const [rating, setRating] = useState(false);
  if (!order) {
    return (
      <div>
        <AppBar title="Order Details" />
        <EmptyState icon={<ReceiptText size={iconSize.hero} />} title="Order not found" message="This order is no longer available." />
      </div>
    );
  }
  const action = order.isActive || order.canRate;
  return (
    <div className={action ? 'with-bottom-bar' : undefined}>
      <AppBar title="Order Details" />
      <div className="page page--narrow stack-lg">
        <FadeIn>
          <BrandPanel lifted>
            <div className="row">
              <span className="t-headline grow">
                {AppFormat.orderNumber(order.id)}
              </span>
              <OrderStatusBadge status={order.status} type={order.type} />
            </div>
            <div className="row wrap" style={{ gap: 16, marginTop: 6, color: 'rgb(255 255 255 / 85%)' }}>
              <span className="row t-caption" style={{ color: 'inherit' }}>
                <UtensilsCrossed size={iconSize.sm} /> {order.tableLabel}
              </span>
              <span className="row t-caption" style={{ color: 'inherit' }}>
                <Clock size={iconSize.sm} /> {AppFormat.dateTime(order.createdAt)}
              </span>
            </div>
          </BrandPanel>
        </FadeIn>
        <h2 className="t-section">Items</h2>
        <FadeIn index={1}>
          <Card tight>
            {order.lines.map((line, index) => (
              <div key={`${line.itemId}-${index}`}>
                {index > 0 && <hr className="divider" />}
                <div className="summary-line">
                  <FoodImage src={line.image} width={38} height={38} radius={10} />
                  <div className="grow col">
                    <div className="row" style={{ gap: 6 }}>
                      <VegIndicator veg={line.isVeg} size={10} />
                      <span className="t-label t-strong">{line.name}</span>
                    </div>
                    {line.options.length > 0 && <span className="t-caption">{line.options.join(' · ')}</span>}
                    <span className="t-caption">
                      {line.quantity} × {Currency.format(line.unitPrice)}
                    </span>
                  </div>
                  <span className="t-label t-strong tabular">{Currency.format(lineTotal(line))}</span>
                </div>
              </div>
            ))}
          </Card>
        </FadeIn>
        {order.specialInstructions && (
          <Card>
            <p className="t-card-title">Special Instructions</p>
            <p className="t-secondary" style={{ marginTop: 6 }}>
              {order.specialInstructions}
            </p>
          </Card>
        )}
        <FadeIn index={2}>
          <Card>
            <BillSummary bill={order.bill} />
          </Card>
        </FadeIn>
        {invoice && (
          <FadeIn index={3}>
            <OrderBillCard invoice={invoice} />
          </FadeIn>
        )}
        <h2 className="t-section">Status</h2>
        <TrackingTimeline order={order} />
        {order.feedback && (
          <Card>
            <div className="row">
              <span className="t-card-title grow">Your rating</span>
              <StarRow rating={order.feedback.rating} />
            </div>
            {order.feedback.comment && (
              <p className="t-secondary" style={{ marginTop: 6 }}>
                {order.feedback.comment}
              </p>
            )}
          </Card>
        )}
      </div>
      {action && (
        <div className="bottom-bar">
          <div className="bottom-bar__inner">
            {order.isActive ? (
              <Button block icon={<Bike size={iconSize.lg} />} onClick={() => navigate(paths.tracking(order.id))}>
                Track Order
              </Button>
            ) : (
              <Button block icon={<Star size={iconSize.lg} />} onClick={() => setRating(true)}>
                Rate Your Experience
              </Button>
            )}
          </div>
        </div>
      )}
      <FeedbackSheet orderId={order.id} open={rating} onClose={() => setRating(false)} />
    </div>
  );
}
