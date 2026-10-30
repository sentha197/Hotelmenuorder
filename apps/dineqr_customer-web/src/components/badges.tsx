import { CheckCircle2, CircleAlert, Hourglass } from 'lucide-react';
import { invoiceStatusLabel, type InvoiceStatus } from '../core/billing';
import { OrderStatuses, type OrderStatus, type OrderType } from '../core/orders';
import { iconSize } from './sizes';

const orderColors: Record<OrderStatus, [string, string]> = {
  placed: ['var(--info-soft)', 'var(--info)'],
  accepted: ['var(--orange-soft)', 'var(--orange-text)'],
  preparing: ['var(--warning-soft)', 'var(--warning)'],
  readyToServe: ['var(--primary-soft)', 'var(--accent-text)'],
  served: ['var(--success-soft)', 'var(--success)'],
  cancelled: ['var(--soft-white)', 'var(--text-secondary)'],
};

export const orderAccent = (status: OrderStatus) => orderColors[status][1];

export function OrderStatusBadge({ status, type = 'dineIn' }: { status: OrderStatus; type?: OrderType }) {
  const [background, color] = orderColors[status];
  return (
    <span className="pill" style={{ background, color }}>
      {OrderStatuses.shortLabel(status, type)}
    </span>
  );
}

const paymentColors: Record<InvoiceStatus, [string, string]> = {
  unpaid: ['var(--primary-soft)', 'var(--accent-text)'],
  pending: ['var(--info-soft)', 'var(--info)'],
  partiallyPaid: ['var(--orange-soft)', 'var(--orange-text)'],
  paid: ['var(--success-soft)', 'var(--success)'],
  failed: ['var(--primary-soft)', 'var(--error)'],
  partiallyRefunded: ['var(--warning-soft)', 'var(--warning)'],
  refunded: ['var(--warning-soft)', 'var(--warning)'],
  voided: ['var(--soft-white)', 'var(--text-secondary)'],
};

export function PaymentStatusBadge({ status }: { status: InvoiceStatus }) {
  const [background, color] = paymentColors[status];
  const icon =
    status === 'paid' ? <CheckCircle2 size={iconSize.xs} /> : status === 'pending' ? <Hourglass size={iconSize.xs} /> : status === 'failed' ? <CircleAlert size={iconSize.xs} /> : null;
  return (
    <span className="pill" style={{ background, color }}>
      {icon}
      {invoiceStatusLabel[status]}
    </span>
  );
}
