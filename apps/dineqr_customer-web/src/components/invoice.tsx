import { Ban, Banknote, CreditCard, FlaskConical, Landmark, RefreshCw, Smartphone, Store, Undo2, Wallet } from 'lucide-react';
import type { ReactNode } from 'react';
import { counterKindLabel, refundStatusLabel, type Invoice, type PaymentTransaction } from '../core/billing';
import { Currency } from '../core/money';
import type { PaymentMethodType } from '../core/settings';
import { AppFormat } from '../core/time';
import { PaymentStatusBadge } from './badges';
import { BillSummary } from './bill';
import { Lockup } from './brand';
import { DemoTag } from './ui';
import { iconSize, lockupHeight } from './sizes';

export const methodIcon = (method: PaymentMethodType, size = 19): ReactNode =>
  ({
    upi: <Smartphone size={size} />,
    card: <CreditCard size={size} />,
    netBanking: <Landmark size={size} />,
    wallet: <Wallet size={size} />,
    cash: <Banknote size={size} />,
  })[method];

/** A bill laid out like the printed invoice (also the receipt). */
export function InvoiceView({ invoice, onCheckPending }: { invoice: Invoice; onCheckPending?: () => void }) {
  const r = invoice.restaurant;
  const contact = [r.phone, r.email].filter(Boolean).join(' · ');
  const request = invoice.openCounterRequest;
  return (
    <article className="invoice">
      <div className="invoice__strip" aria-hidden />
      <div className="invoice__body">
        <div className="row-top">
          <div className="grow col">
            {/* A block wrapper, so the column's flex stretch cannot widen the logo. */}
            <div>
              <Lockup height={lockupHeight.bill} trim onLight />
            </div>
            <span className="t-card-title" style={{ marginTop: 10 }}>
              {r.name}
            </span>
            {r.address && <span className="t-caption">{r.address}</span>}
            {contact && <span className="t-caption">{contact}</span>}
            {r.taxRegistration && <span className="t-caption">Tax registration: {r.taxRegistration}</span>}
          </div>
          <div className="col" style={{ alignItems: 'flex-end', gap: 6 }}>
            <span className="t-overline t-overline--lg t-primary">
              {invoice.status === 'paid' ? (invoice.hasDemoPayments ? 'DEMO RECEIPT' : 'RECEIPT') : 'BILL'}
            </span>
            <PaymentStatusBadge status={invoice.status} />
            {invoice.hasDemoPayments && <DemoTag label="DEMO PAYMENT" />}
          </div>
        </div>
        <dl className="invoice__meta">
          <div>
            <dt>Bill no.</dt>
            <dd>{invoice.billNumber}</dd>
          </div>
          <div>
            <dt>Order</dt>
            <dd>{AppFormat.orderNumber(invoice.orderId)}</dd>
          </div>
          <div>
            <dt>{invoice.isTakeaway ? 'Type' : 'Table'}</dt>
            <dd>{invoice.isTakeaway ? 'Takeaway' : AppFormat.table(invoice.tableNumber)}</dd>
          </div>
          <div>
            <dt>Date</dt>
            <dd>{AppFormat.dateTime(invoice.createdAt)}</dd>
          </div>
        </dl>
        <hr className="dashed" style={{ margin: '16px 0' }} />
        {invoice.lines.map((line, i) => (
          <div key={`${line.itemId}-${i}`} className="row-top" style={{ marginBottom: 12 }}>
            <div className="grow col">
              <span className="t-label t-strong">{line.name}</span>
              <span className="t-caption">{[`${line.quantity} × ${Currency.format(line.unitPrice)}`, ...line.options].join(' · ')}</span>
            </div>
            <span className="t-label t-strong tabular">{Currency.format(line.unitPrice * line.quantity)}</span>
          </div>
        ))}
        <hr className="dashed" style={{ marginBottom: 12 }} />
        <BillSummary bill={invoice.amounts} paid={invoice.amountPaid} refunded={invoice.amountRefunded} outstanding={invoice.outstanding} />
        {invoice.payments.length > 0 && (
          <section style={{ marginTop: 20 }}>
            <h3 className="t-card-title" style={{ marginBottom: 8 }}>
              Payments
            </h3>
            {[...invoice.payments].reverse().map((payment) => (
              <PaymentRow key={payment.id} payment={payment} onCheckStatus={payment.status === 'pending' ? onCheckPending : undefined} />
            ))}
          </section>
        )}
        {invoice.refunds.length > 0 && (
          <section style={{ marginTop: 16 }}>
            <h3 className="t-card-title" style={{ marginBottom: 8 }}>
              Refunds
            </h3>
            {invoice.refunds.map((refund) => (
              <div key={refund.id} className="row-top" style={{ marginBottom: 8 }}>
                <Undo2 size={iconSize.md} color="var(--warning)" />
                <div className="grow col">
                  <span className="t-label t-strong">
                    {refundStatusLabel[refund.status]}
                    {refund.isSimulated ? ' (simulated)' : ''}
                  </span>
                  <span className="t-caption">{[AppFormat.dateTime(refund.createdAt), refund.reason, ...(refund.processedBy ? [`By ${refund.processedBy}`] : [])].join(' · ')}</span>
                </div>
                <span className="t-label t-strong t-warning">− {Currency.format(refund.amount)}</span>
              </div>
            ))}
          </section>
        )}
        {request && (
          <div className="notice notice--plain" style={{ marginTop: 16 }}>
            {request.kind === 'cash' ? <Banknote size={iconSize.md} /> : <Store size={iconSize.md} />}
            <span className="grow">
              {counterKindLabel[request.kind]}: {Currency.format(request.amount)} (chosen {AppFormat.time(request.requestedAt)}). The bill updates when staff record the payment.
            </span>
          </div>
        )}
        {invoice.isVoid && (
          <div className="notice notice--plain" style={{ marginTop: 16 }}>
            <Ban size={iconSize.md} />
            <span className="grow">
              Void: the order was cancelled{invoice.voidReason ? ` (${invoice.voidReason})` : ''}.{invoice.refundDue ? ' A refund is due.' : ''}
            </span>
          </div>
        )}
        {invoice.demoNotice && (
          <div className="notice tone-info" style={{ marginTop: 16 }}>
            <FlaskConical size={iconSize.md} />
            <span className="grow">{invoice.demoNotice}</span>
            <DemoTag />
          </div>
        )}
        {r.footer && (
          <p className="t-secondary t-center" style={{ marginTop: 16 }}>
            {r.footer}
          </p>
        )}
      </div>
    </article>
  );
}

/** One payment attempt with status, method, time and reference. */
export function PaymentRow({ payment, onCheckStatus }: { payment: PaymentTransaction; onCheckStatus?: () => void }) {
  const [color, label] =
    payment.status === 'succeeded'
      ? ['var(--success)', 'Successful']
      : payment.status === 'pending'
        ? ['var(--info)', payment.isUpiDirect ? payment.statusLabel : 'Awaiting confirmation']
        : payment.status === 'failed'
          ? ['var(--error)', 'Failed']
          : ['var(--text-secondary)', 'Cancelled'];
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
    <div className="row-top payment-row">
      <span className="payment-row__icon" style={{ color, background: `color-mix(in srgb, ${color} 10%, transparent)` }}>
        {methodIcon(payment.method)}
      </span>
      <div className="grow col">
        <span className="t-label t-strong" style={{ color: payment.status === 'succeeded' ? 'var(--text)' : color }}>
          {payment.methodLabel} · {label}
        </span>
        <span className="t-caption">
          {[
            AppFormat.dateTime(payment.updatedAt),
            ...(payment.reference
              ? [payment.isUpiDirect && payment.status === 'pending' ? `Ref ${payment.reference} (from guest, unverified)` : `Ref ${payment.reference}`]
              : []),
            ...(handledBy ? [handledBy] : []),
            ...(payment.isSimulated ? ['Demo payment (no money moved)'] : []),
          ].join(' · ')}
        </span>
        {payment.failureReason && payment.status !== 'succeeded' && (
          <span className="t-caption" style={{ color }}>
            {payment.failureReason}
          </span>
        )}
        {onCheckStatus && (
          <button type="button" className="link-btn" onClick={onCheckStatus}>
            <RefreshCw size={iconSize.sm} /> Check status
          </button>
        )}
      </div>
      <span className="t-label tabular" style={{ fontWeight: 700, textDecoration: struck ? 'line-through' : undefined }}>
        {Currency.format(payment.amount)}
      </span>
    </div>
  );
}
