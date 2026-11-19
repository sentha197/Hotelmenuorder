import { OrderStatuses, type OrderStatus, type OrderType } from '../core/orders';

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
