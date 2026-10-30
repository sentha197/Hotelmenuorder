import { ChefHat, ConciergeBell, Download, Lock, ReceiptText, ShoppingBag, Star, UtensilsCrossed, X, XCircle } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import type { Invoice } from '../core/billing';
import { Currency } from '../core/money';
import { MAX_FEEDBACK_COMMENT, OrderStatuses, validateFeedback, type OrderStatus, type RestaurantOrder } from '../core/orders';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useSelect } from '../state/store';
import { PaymentStatusBadge } from './badges';
import { FoodImage } from './food';
import { Sheet } from './Sheet';
import { Button, Card, StarRow, SuccessEmblem } from './ui';
import { emblemSize, iconSize } from './sizes';

/** Bill status with View Bill, and Pay Now while something is due. */
export function OrderBillCard({ invoice }: { invoice: Invoice }) {
  const navigate = useNavigate();
  const canPay = !invoice.isVoid && invoice.payableNow > 0;
  const upiPending = invoice.payments.some((p) => p.isUpiDirect && p.status === 'pending');
  return (
    <Card>
      <div className="row">
        <ReceiptText size={iconSize.lg} color="var(--accent-text)" />
        <span className="t-card-title grow">Bill {invoice.billNumber}</span>
        <PaymentStatusBadge status={invoice.status} />
      </div>
      <p className="t-secondary" style={{ marginTop: 8 }}>
        {invoice.outstanding === 0
          ? `Total ${Currency.format(invoice.total)} · ${invoice.isVoid ? 'nothing to pay' : 'nothing due'}`
          : `Balance due ${Currency.format(invoice.outstanding)} of ${Currency.format(invoice.total)}`}
      </p>
      {invoice.hasPendingPayment && (
        <p className="t-caption t-info" style={{ marginTop: 4 }}>
          {upiPending
            ? `Your UPI payment of ${Currency.format(invoice.pendingAmount)} is waiting for the restaurant to confirm.`
            : `A payment of ${Currency.format(invoice.pendingAmount)} is waiting for confirmation.`}
        </p>
      )}
      <div className="row" style={{ marginTop: 12, gap: 12 }}>
        <Button variant="secondary" compact className="grow" icon={<ReceiptText size={iconSize.md} />} onClick={() => navigate(paths.bill(invoice.id))}>
          View Bill
        </Button>
        {canPay ? (
          <Button compact className="grow" icon={<Lock size={iconSize.md} />} onClick={() => navigate(paths.pay(invoice.id))}>
            Pay Now
          </Button>
        ) : invoice.latestSuccessfulPayment ? (
          <Button variant="secondary" compact className="grow" icon={<Download size={iconSize.md} />} onClick={() => navigate(paths.receipt(invoice.id))}>
            Receipt
          </Button>
        ) : null}
      </div>
    </Card>
  );
}

const stageIcon: Record<OrderStatus, React.ReactNode> = {
  placed: <ReceiptText size={iconSize.lg} />,
  accepted: <ReceiptText size={iconSize.lg} />,
  preparing: <ChefHat size={iconSize.lg} />,
  readyToServe: <ConciergeBell size={iconSize.lg} />,
  served: <UtensilsCrossed size={iconSize.lg} />,
  cancelled: <XCircle size={iconSize.lg} />,
};

/** The four guest-facing stages; acceptance shows under "Order Placed". */
export function TrackingTimeline({ order }: { order: RestaurantOrder }) {
  const reduced = useReducedMotion();
  const steps = OrderStatuses.customerStages;
  const cancelled = order.isCancelled;
  const current = steps.indexOf(OrderStatuses.customerStage(order.status));
  const reached = (i: number) => (cancelled ? order.statusTimes[steps[i]!] != null : i <= current);

  const subtitle = (status: OrderStatus): string => {
    const time = order.statusTimes[status];
    if (status === 'placed') {
      const accepted = order.statusTimes.accepted;
      return [...(time ? [AppFormat.time(time)] : []), ...(accepted ? [`Accepted by the kitchen ${AppFormat.time(accepted)}`] : [])].join(' · ');
    }
    if (time) return AppFormat.time(time);
    if (cancelled) return '';
    if (status === 'readyToServe') return `Expected around ${AppFormat.time(order.estimatedReadyAt)}`;
    if (status === 'served') return order.isTakeaway ? 'Collect it at the counter with your order number' : 'Your server will bring it to your table';
    if (status === 'preparing') return 'The kitchen will start shortly';
    return '';
  };

  return (
    <ol className="timeline">
      {steps.map((status, i) => {
        const done = reached(i);
        const isCurrent = done && i === current && status !== 'served' && !cancelled;
        const state = !done ? 'upcoming' : isCurrent ? 'current' : 'done';
        const label = OrderStatuses.label(status, order.type);
        const text = subtitle(status);
        return (
          <li key={status} className={`timeline__step is-${state}`} aria-label={`${label}, ${state === 'done' ? 'completed' : state === 'current' ? 'in progress' : 'upcoming'}. ${text}`}>
            {i < steps.length - 1 && (
              <span className="timeline__line" aria-hidden>
                <motion.span
                  className="timeline__fill"
                  initial={false}
                  animate={{ scaleY: reached(i + 1) ? 1 : 0 }}
                  transition={reduced ? { duration: 0 } : { duration: 0.6, ease: [0.2, 0, 0, 1] }}
                />
              </span>
            )}
            <span className="timeline__dot" aria-hidden>
              {order.isTakeaway && status === 'readyToServe' ? <ShoppingBag size={iconSize.lg} /> : stageIcon[status]}
              {isCurrent && !reduced && <span className="timeline__pulse" />}
            </span>
            <div className="timeline__text">
              <span className="t-card-title">{label}</span>
              {text && <span className="t-caption">{text}</span>}
            </div>
          </li>
        );
      })}
    </ol>
  );
}

const ratingWords = ['', 'Poor', 'Could be better', 'Good', 'Great', 'Loved it!'];

/** "Rate Your Experience" for a served order. */
export function FeedbackSheet({ orderId, open, onClose }: { orderId: string; open: boolean; onClose: () => void }) {
  const { orders } = useApp();
  const order = orders.byId(orderId);
  const busy = useSelect(orders, (o) => o.isBusy(orderId));
  const reduced = useReducedMotion();
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState('');
  const [error, setError] = useState<{ text: string; count: number } | null>(null);
  const [submitted, setSubmitted] = useState(false);

  useEffect(() => {
    if (open) {
      setSubmitted(false);
      setError(null);
    }
  }, [open]);

  const submit = async () => {
    const problem = validateFeedback(rating, comment);
    if (problem) return setError({ text: problem, count: (error?.count ?? 0) + 1 });
    try {
      await orders.submitFeedback(orderId, rating, comment);
      setSubmitted(true);
    } catch (e) {
      setError({ text: e instanceof Error && e.message ? e.message : 'This order has already been rated.', count: (error?.count ?? 0) + 1 });
    }
  };

  const done = submitted || order?.feedback != null;
  return (
    <Sheet open={open} onClose={onClose} title="Rate your experience" dismissible={!busy}>
      <AnimatePresence mode="wait" initial={false}>
        {done ? (
          <motion.div key="done" className="col" style={{ alignItems: 'center', textAlign: 'center' }} initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <SuccessEmblem size={emblemSize.md} label={submitted ? 'Feedback sent' : 'Already rated'} />
            <h2 className="t-headline">{submitted ? 'Thank you!' : 'Already rated'}</h2>
            <div style={{ margin: '8px 0' }}>
              <StarRow rating={submitted ? rating : (order?.feedback?.rating ?? 0)} size={24} />
            </div>
            <p className="t-secondary">Your rating is saved with this order.</p>
            <div style={{ width: '100%', marginTop: 20 }}>
              <Button block onClick={onClose}>
                Done
              </Button>
            </div>
          </motion.div>
        ) : order ? (
          <motion.div key="form" className="col" style={{ alignItems: 'center' }} initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
            <div className="row" style={{ width: '100%' }}>
              <span className="app-bar__spacer" />
              <h2 className="t-screen-title grow t-center">Rate Your Experience</h2>
              <button type="button" className="icon-btn" aria-label="Close" onClick={onClose}>
                <X size={iconSize.lg} />
              </button>
            </div>
            <div className="feedback__photo">
              <FoodImage src={order.previewImage} width={116} height={94} radius={14} />
            </div>
            <p className="t-section" style={{ marginTop: 16 }}>
              How was your food?
            </p>
            <p className="t-caption">
              Order {AppFormat.orderNumber(order.id)} · {order.tableLabel}
            </p>
            <motion.div
              key={error?.count ?? 0}
              className="stars"
              role="radiogroup"
              aria-label="Rating"
              animate={error && !reduced ? { x: [0, -10, 10, -6, 6, 0] } : { x: 0 }}
              transition={{ duration: 0.4 }}
            >
              {[1, 2, 3, 4, 5].map((n) => (
                <motion.button
                  key={n}
                  type="button"
                  role="radio"
                  aria-checked={rating === n}
                  aria-label={`${n} star${n === 1 ? '' : 's'}`}
                  className="stars__star"
                  whileTap={{ scale: 0.8 }}
                  animate={n <= rating && !reduced ? { scale: [1, 1.25, 1] } : { scale: 1 }}
                  transition={{ duration: 0.3, delay: n <= rating ? (n - 1) * 0.04 : 0 }}
                  onClick={() => {
                    setRating(n);
                    setError(null);
                  }}
                >
                  <Star size={iconSize.hero} color={n <= rating ? '#FFC83D' : 'var(--inactive)'} fill={n <= rating ? '#FFC83D' : 'transparent'} strokeWidth={1.6} />
                </motion.button>
              ))}
            </motion.div>
            <p className="t-label t-strong" style={{ minHeight: 20, color: error ? 'var(--error)' : 'var(--orange-text)' }} role={error ? 'alert' : undefined}>
              {error?.text ?? ratingWords[rating]}
            </p>
            <label className="field" style={{ width: '100%', marginTop: 12 }}>
              <span className="visually-hidden">Feedback</span>
              <textarea
                className="input"
                rows={3}
                maxLength={MAX_FEEDBACK_COMMENT}
                value={comment}
                onChange={(e) => setComment(e.target.value)}
                placeholder="Share your feedback (optional)"
              />
              <span className="field__hint" style={{ textAlign: 'right' }}>
                {comment.length}/{MAX_FEEDBACK_COMMENT}
              </span>
            </label>
            <div className="stack-sm" style={{ width: '100%', marginTop: 8 }}>
              <Button block loading={busy} onClick={submit}>
                Submit
              </Button>
              <Button variant="ghost" block disabled={busy} onClick={onClose}>
                Skip
              </Button>
            </div>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </Sheet>
  );
}
