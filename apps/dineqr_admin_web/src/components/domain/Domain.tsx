import { Ban, Banknote, CircleCheck, Clock, CreditCard, FlaskConical, Hourglass, ImageOff, Landmark, Minus, Plus, RefreshCw, ShoppingBag, Smartphone, Store, Undo2, Wallet, CircleX, ChefHat, ThumbsUp, Bell } from 'lucide-react';
import QRCode from 'qrcode';
import { useEffect, useState, type ReactNode } from 'react';
import { imageUrl } from '@/config/env';
import { counterKindLabel, invoiceStatusLabel, refundStatusLabel, type Invoice, type InvoiceStatus, type PaymentMethodType, type PaymentTransaction } from '@/core/billing';
import { Currency } from '@/core/money';
import { offerStatusLabel, type OfferStatus } from '@/core/offers';
import { OrderStatuses, Tables, type OrderStatus } from '@/core/orders';
import { Bills, type BillBreakdown } from '@/core/pricing';
import { AppFormat } from '@/core/time';
import { Lockup } from '../brand/Brand';
import { Badge, Tag } from '../ui/Badge';
import { cn, type Tone } from '../ui/cn';

/** A dish or offer photo, with a placeholder when there is none or it fails to load. */
export function FoodImage({ src, size = 48, className, alt = '' }: { src: string; size?: number; className?: string; alt?: string }) {
  const [failed, setFailed] = useState(false);
  const url = imageUrl(src);
  useEffect(() => setFailed(false), [src]);
  return (
    <div className={cn('relative shrink-0 overflow-hidden rounded-xl border border-line bg-panel-2', className)} style={{ width: size, height: size }}>
      {url && !failed ? (
        <img src={url} alt={alt} loading="lazy" decoding="async" onError={() => setFailed(true)} className="h-full w-full object-cover" />
      ) : (
        <div className="grid h-full w-full place-items-center text-faint">
          <ImageOff size={Math.max(14, size * 0.32)} aria-hidden />
        </div>
      )}
    </div>
  );
}

/** The green (veg) or red (non-veg) square-and-dot mark. */
export function VegMark({ veg, size = 12 }: { veg: boolean; size?: number }) {
  const color = veg ? '#1f9d55' : '#c81e1e';
  return (
    <span role="img" aria-label={veg ? 'Vegetarian' : 'Non-vegetarian'} className="inline-grid shrink-0 place-items-center rounded-[3px] border-[1.5px] bg-white" style={{ width: size, height: size, borderColor: color }}>
      <span className="block rounded-full" style={{ width: size * 0.45, height: size * 0.45, background: color }} />
    </span>
  );
}

const orderTone: Record<OrderStatus, Tone> = {
  placed: 'brand',
  accepted: 'info',
  preparing: 'ember',
  readyToServe: 'success',
  served: 'muted',
  cancelled: 'danger',
};
const orderIcon = { placed: Bell, accepted: ThumbsUp, preparing: ChefHat, readyToServe: CircleCheck, served: CircleCheck, cancelled: CircleX };

export function OrderStatusBadge({ status, takeaway }: { status: OrderStatus; takeaway: boolean }) {
  return (
    <Badge tone={orderTone[status]} icon={orderIcon[status]}>
      {OrderStatuses.shortLabel(status, takeaway)}
    </Badge>
  );
}

const invoiceTone: Record<InvoiceStatus, Tone> = {
  unpaid: 'brand',
  pending: 'info',
  partiallyPaid: 'warning',
  paid: 'success',
  failed: 'danger',
  partiallyRefunded: 'ember',
  refunded: 'ember',
  voided: 'muted',
};
const invoiceIcon = { unpaid: Clock, pending: Hourglass, partiallyPaid: Clock, paid: CircleCheck, failed: CircleX, partiallyRefunded: Undo2, refunded: Undo2, voided: Ban };

export function PaymentStatusBadge({ status }: { status: InvoiceStatus }) {
  return (
    <Badge tone={invoiceTone[status]} icon={invoiceIcon[status]}>
      {invoiceStatusLabel[status]}
    </Badge>
  );
}

const offerTone: Record<OfferStatus, Tone> = { live: 'success', scheduled: 'info', paused: 'warning', usedUp: 'brand', ended: 'muted' };

export function OfferStatusChip({ status }: { status: OfferStatus }) {
  return <Badge tone={offerTone[status]}>{offerStatusLabel[status]}</Badge>;
}

/** The table number (or takeaway bag) on a brand tile. */
export function TableBadge({ table, size = 46 }: { table: number; size?: number }) {
  const takeaway = Tables.isTakeaway(table);
  return (
    <div className="brand-fill grid shrink-0 place-items-center rounded-xl text-center shadow-glow" style={{ width: size, height: size }} aria-label={Tables.label(table)}>
      <div className="leading-none">
        <div className="text-[7px] font-bold uppercase tracking-[0.12em] text-white/75">{takeaway ? 'Takeaway' : 'Table'}</div>
        {takeaway ? <ShoppingBag size={size * 0.38} className="mx-auto mt-0.5" aria-hidden /> : <div className="mt-0.5 text-[17px] font-extrabold tabular">{AppFormat.table(table)}</div>}
      </div>
    </div>
  );
}

export const methodIcon = (method: PaymentMethodType, size = 18): ReactNode =>
  ({
    upi: <Smartphone size={size} aria-hidden />,
    card: <CreditCard size={size} aria-hidden />,
    netBanking: <Landmark size={size} aria-hidden />,
    wallet: <Wallet size={size} aria-hidden />,
    cash: <Banknote size={size} aria-hidden />,
  })[method];

function Row({ label, value, strong, tone }: { label: ReactNode; value: ReactNode; strong?: boolean; tone?: string }) {
  return (
    <div className={cn('flex items-baseline justify-between gap-4 py-[3px]', strong && 'pt-1.5')}>
      <span className={cn('text-[13px]', strong ? 'font-semibold' : 'opacity-75')}>{label}</span>
      <span className={cn('text-[13px] tabular', strong ? 'text-[15px] font-bold' : 'font-semibold')} style={tone ? { color: tone } : undefined}>
        {value}
      </span>
    </div>
  );
}

/** Subtotal, savings, service charge, tax and total, then what was paid (BillSummary). */
export function BillSummary({ bill, paid, refunded, outstanding }: { bill: BillBreakdown; paid?: number; refunded?: number; outstanding?: number }) {
  return (
    <div>
      <Row label="Subtotal" value={Currency.format(bill.subtotal)} />
      {Bills.discountLines(bill).map((d, i) => (
        <Row key={`${d.label}-${i}`} label={d.label} value={`− ${Currency.format(d.amount)}`} tone="var(--success)" />
      ))}
      {bill.serviceCharge !== 0 && <Row label={Bills.serviceChargeLabel(bill)} value={Currency.format(bill.serviceCharge)} />}
      <Row label={Bills.taxLabel(bill)} value={Currency.format(bill.tax)} />
      <div className="my-1.5 border-t border-dashed border-current/20" />
      <Row label="Total" value={Currency.format(bill.total)} strong />
      {paid != null && paid !== 0 && <Row label="Paid" value={Currency.format(paid)} tone="var(--success)" />}
      {refunded != null && refunded !== 0 && <Row label="Refunded" value={`− ${Currency.format(refunded)}`} tone="var(--warning)" />}
      {outstanding != null && (paid != null || refunded != null) && <Row label="Balance due" value={Currency.format(outstanding)} strong />}
    </div>
  );
}

/** One payment attempt with status, method, time and reference (PaymentRow). */
export function PaymentRow({ payment, actions, onCheckStatus }: { payment: PaymentTransaction; actions?: ReactNode; onCheckStatus?: () => void }) {
  const [color, label] =
    payment.status === 'succeeded'
      ? ['#16803c', 'Successful']
      : payment.status === 'pending'
        ? ['#1f63d1', payment.isUpiDirect ? payment.statusLabel : 'Awaiting confirmation']
        : payment.status === 'failed'
          ? ['#c81e1e', 'Failed']
          : ['#6b5a5d', 'Cancelled'];
  const handledBy = !payment.recordedBy
    ? null
    : !payment.isUpiDirect
      ? `Recorded by ${payment.recordedBy}`
      : payment.status === 'succeeded'
        ? `Confirmed by ${payment.recordedBy}`
        : payment.status === 'failed'
          ? `Rejected by ${payment.recordedBy}`
          : payment.status === 'cancelled'
            ? `Cancelled by ${payment.recordedBy}`
            : null;
  const struck = payment.status === 'failed' || payment.status === 'cancelled';
  return (
    <div className="flex items-start gap-3 py-2.5">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl" style={{ color, background: `color-mix(in srgb, ${color} 11%, transparent)` }}>
        {methodIcon(payment.method)}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[13px] font-semibold" style={{ color: payment.status === 'succeeded' ? undefined : color }}>
          {payment.methodLabel} · {label}
        </p>
        <p className="text-[11.5px] leading-snug opacity-70">
          {[
            AppFormat.dateTime(payment.updatedAt),
            ...(payment.reference ? [payment.isUpiDirect && payment.status === 'pending' ? `Ref ${payment.reference} (from guest, unverified)` : `Ref ${payment.reference}`] : []),
            ...(handledBy ? [handledBy] : []),
            ...(payment.isSimulated ? ['Test payment (no money moved)'] : []),
          ].join(' · ')}
        </p>
        {payment.failureReason && payment.status !== 'succeeded' && (
          <p className="text-[11.5px]" style={{ color }}>
            {payment.failureReason}
          </p>
        )}
        {onCheckStatus && (
          <button type="button" onClick={onCheckStatus} className="mt-1 inline-flex items-center gap-1 text-[12px] font-semibold text-[#b5121b] hover:underline">
            <RefreshCw size={13} aria-hidden /> Check status
          </button>
        )}
      </div>
      <div className="flex shrink-0 flex-col items-end gap-1">
        <span className={cn('text-[13px] font-bold tabular', struck && 'line-through opacity-60')}>{Currency.format(payment.amount)}</span>
        {actions}
      </div>
    </div>
  );
}

/**
 * A bill laid out like the printed invoice (InvoiceView). It is paper in both
 * themes, so it prints and reads the same everywhere. [paymentActions] adds
 * staff actions (confirm, refund) next to a payment.
 */
export function InvoiceView({ invoice, paymentActions, onCheckPending }: { invoice: Invoice; paymentActions?: (payment: PaymentTransaction) => ReactNode; onCheckPending?: () => void }) {
  const r = invoice.restaurant;
  const contact = [r.phone, r.email].filter(Boolean).join(' · ');
  const request = invoice.openCounterRequest;
  return (
    <article
      className="print-area relative overflow-hidden rounded-[var(--radius-card)] bg-paper text-paper-ink shadow-lift"
      // Paper keeps its own ink colours in the dark theme too.
      style={{ colorScheme: 'light', '--success': '#16803c', '--warning': '#b26b00' } as React.CSSProperties}
    >
      <div className="h-1.5 w-full bg-[linear-gradient(90deg,#8e0f17,#d62828,#ff8a00)]" aria-hidden />
      <div className="p-5 sm:p-7">
        <div className="flex flex-wrap items-start gap-4">
          <div className="min-w-0 flex-1">
            <Lockup height={34} trim onLight />
            <p className="mt-3 text-[15px] font-semibold">{r.name}</p>
            {r.address && <p className="text-[12px] opacity-70">{r.address}</p>}
            {contact && <p className="text-[12px] opacity-70">{contact}</p>}
            {r.taxRegistration && <p className="text-[12px] opacity-70">Tax registration: {r.taxRegistration}</p>}
          </div>
          <div className="flex flex-col items-end gap-1.5">
            <span className="text-[12px] font-bold uppercase tracking-[0.18em] text-[#b5121b]">
              {invoice.status === 'paid' ? (invoice.hasDemoPayments ? 'Test receipt' : 'Receipt') : 'Bill'}
            </span>
            <PaperStatus status={invoice.status} />
            {invoice.hasDemoPayments && <Tag tone="info">Test payment</Tag>}
          </div>
        </div>
        <dl className="mt-5 grid grid-cols-2 gap-x-6 gap-y-2 rounded-xl bg-[#f7f2f1] p-3.5 text-[12px] sm:grid-cols-4">
          {[
            ['Bill no.', invoice.billNumber],
            ['Order', AppFormat.orderNumber(invoice.orderId)],
            [invoice.isTakeaway ? 'Type' : 'Table', invoice.isTakeaway ? 'Takeaway' : AppFormat.table(invoice.tableNumber)],
            ['Date', AppFormat.dateTime(invoice.createdAt)],
          ].map(([k, v]) => (
            <div key={k} className="min-w-0">
              <dt className="opacity-60">{k}</dt>
              <dd className="truncate font-semibold">{v}</dd>
            </div>
          ))}
        </dl>
        <div className="mt-4 border-t border-dashed border-black/15 pt-4">
          {invoice.lines.map((line, i) => (
            <div key={`${line.itemId}-${i}`} className="mb-3 flex items-start gap-4">
              <div className="min-w-0 flex-1">
                <p className="text-[13px] font-semibold">{line.name}</p>
                <p className="text-[11.5px] opacity-65">{[`${line.quantity} × ${Currency.format(line.unitPrice)}`, ...line.options].join(' · ')}</p>
              </div>
              <span className="text-[13px] font-semibold tabular">{Currency.format(line.unitPrice * line.quantity)}</span>
            </div>
          ))}
        </div>
        <div className="border-t border-dashed border-black/15 pt-3">
          <BillSummary bill={invoice.amounts} paid={invoice.amountPaid} refunded={invoice.amountRefunded} outstanding={invoice.outstanding} />
        </div>
        {invoice.payments.length > 0 && (
          <section className="mt-5">
            <h3 className="text-[13px] font-bold uppercase tracking-[0.1em] opacity-70">Payments</h3>
            <div className="divide-y divide-black/5">
              {[...invoice.payments].reverse().map((p) => (
                <PaymentRow key={p.id} payment={p} actions={paymentActions?.(p)} onCheckStatus={p.status === 'pending' ? onCheckPending : undefined} />
              ))}
            </div>
          </section>
        )}
        {invoice.refunds.length > 0 && (
          <section className="mt-4">
            <h3 className="text-[13px] font-bold uppercase tracking-[0.1em] opacity-70">Refunds</h3>
            {invoice.refunds.map((refund) => (
              <div key={refund.id} className="flex items-start gap-3 py-2">
                <Undo2 size={17} className="mt-0.5 text-[#b26b00]" aria-hidden />
                <div className="min-w-0 flex-1">
                  <p className="text-[13px] font-semibold">
                    {refundStatusLabel[refund.status]}
                    {refund.isSimulated ? ' (test)' : ''}
                  </p>
                  <p className="text-[11.5px] opacity-65">{[AppFormat.dateTime(refund.createdAt), refund.reason, ...(refund.processedBy ? [`By ${refund.processedBy}`] : [])].join(' · ')}</p>
                </div>
                <span className="text-[13px] font-bold text-[#b26b00] tabular">− {Currency.format(refund.amount)}</span>
              </div>
            ))}
          </section>
        )}
        {request && (
          <PaperNote icon={request.kind === 'cash' ? <Banknote size={16} aria-hidden /> : <Store size={16} aria-hidden />}>
            {counterKindLabel[request.kind]}: {Currency.format(request.amount)} (chosen {AppFormat.time(request.requestedAt)}). The bill updates when staff record the payment.
          </PaperNote>
        )}
        {invoice.isVoid && (
          <PaperNote icon={<Ban size={16} aria-hidden />}>
            Void: the order was cancelled{invoice.voidReason ? ` (${invoice.voidReason})` : ''}.{invoice.refundDue ? ' A refund is due.' : ''}
          </PaperNote>
        )}
        {invoice.demoNotice && <PaperNote icon={<FlaskConical size={16} aria-hidden />}>{invoice.demoNotice}</PaperNote>}
        {r.footer && <p className="mt-5 text-center text-[13px] opacity-70">{r.footer}</p>}
      </div>
    </article>
  );
}

function PaperNote({ icon, children }: { icon: ReactNode; children: ReactNode }) {
  return (
    <div className="mt-4 flex items-start gap-2.5 rounded-xl bg-[#f7f2f1] px-3.5 py-3 text-[12.5px] leading-relaxed">
      <span className="mt-0.5 shrink-0 opacity-70">{icon}</span>
      <span className="min-w-0">{children}</span>
    </div>
  );
}

const paperColor: Record<InvoiceStatus, string> = {
  unpaid: '#b5121b',
  pending: '#1f63d1',
  partiallyPaid: '#b26b00',
  paid: '#16803c',
  failed: '#c81e1e',
  partiallyRefunded: '#b65300',
  refunded: '#b65300',
  voided: '#6b5a5d',
};

function PaperStatus({ status }: { status: InvoiceStatus }) {
  const color = paperColor[status];
  return (
    <span className="rounded-full px-2.5 py-1 text-[11px] font-bold" style={{ color, background: `color-mix(in srgb, ${color} 12%, transparent)` }}>
      {invoiceStatusLabel[status]}
    </span>
  );
}

/** A QR code drawn locally from [payload] (never fetched from anywhere). */
export function QrCode({ payload, size = 168, label, logo = false }: { payload: string; size?: number; label: string; logo?: boolean }) {
  const [svg, setSvg] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    // Printed table codes carry the logo in the middle, so they use the
    // highest error correction (as the Flutter QR sheet does).
    QRCode.toString(payload, { type: 'svg', margin: 1, errorCorrectionLevel: logo ? 'H' : 'M', color: { dark: '#1d1416', light: '#ffffff' } })
      .then((s) => alive && setSvg(s))
      .catch(() => alive && setSvg(null));
    return () => {
      alive = false;
    };
  }, [payload, logo]);
  return (
    <div role="img" aria-label={label} className="relative overflow-hidden rounded-xl bg-white p-1.5" style={{ width: size, height: size }}>
      {svg ? <div className="h-full w-full [&>svg]:h-full [&>svg]:w-full" dangerouslySetInnerHTML={{ __html: svg }} /> : <div className="skeleton h-full w-full" />}
      {logo && svg && (
        <span className="absolute left-1/2 top-1/2 grid -translate-x-1/2 -translate-y-1/2 place-items-center bg-white p-[3px]" style={{ width: size * 0.22, height: size * 0.22 }}>
          <img src={`${import.meta.env.BASE_URL}brand/dineqr_symbol_color.png`} alt="" className="h-full w-full object-contain" />
        </span>
      )}
    </div>
  );
}

/** − quantity + (QuantitySelector). */
export function QuantityStepper({ quantity, onIncrement, onDecrement, max = 20, label }: { quantity: number; onIncrement: () => void; onDecrement: () => void; max?: number; label: string }) {
  return (
    <div className="inline-flex h-9 items-center rounded-xl border border-line-strong bg-panel-2" role="group" aria-label={`Quantity of ${label}`}>
      <button type="button" aria-label={`One fewer ${label}`} onClick={onDecrement} className="grid h-9 w-9 place-items-center rounded-l-xl text-muted hover:bg-panel-3 hover:text-ink">
        <Minus size={15} aria-hidden />
      </button>
      <span className="min-w-7 text-center text-[13px] font-bold tabular" aria-live="polite">
        {quantity}
      </span>
      <button type="button" aria-label={`One more ${label}`} onClick={onIncrement} disabled={quantity >= max} className="grid h-9 w-9 place-items-center rounded-r-xl text-brand-text hover:bg-panel-3 disabled:opacity-40">
        <Plus size={15} aria-hidden />
      </button>
    </div>
  );
}
