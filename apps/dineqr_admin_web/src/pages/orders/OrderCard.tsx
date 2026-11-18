import { StickyNote } from 'lucide-react';
import { motion } from 'motion/react';
import { useNavigate } from 'react-router';
import { OrderStatusBadge, PaymentStatusBadge, TableBadge } from '@/components/domain/Domain';
import { Tag } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { cn } from '@/components/ui/cn';
import { Currency } from '@/core/money';
import { Orders, type RestaurantOrder } from '@/core/orders';
import { AppFormat } from '@/core/time';
import { useOrderBusy } from '@/state/actions';
import { useBills } from '@/state/data';
import { useAccess } from '@/state/session';
import { actionIcon, advanceOrder, allowedAction } from './orderActions';

/** Order summary row used in lists and on the dashboard (AdminOrderCard). */
export function OrderCard({ order, compact = false, index = 0 }: { order: RestaurantOrder; compact?: boolean; index?: number }) {
  const navigate = useNavigate();
  const { can } = useAccess();
  const invoice = (useBills().data ?? []).find((i) => i.orderId === order.id);
  const busy = useOrderBusy(order.id);
  const action = allowedAction(order, can);
  const names = order.lines.map((l) => `${l.quantity}× ${l.name}`);
  const age = Orders.ageInMinutes(order, new Date());
  const takeaway = Orders.isTakeaway(order);
  const ActionIcon = action ? actionIcon[action.icon] : null;
  return (
    <motion.article
      layout="position"
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.28, delay: Math.min(index, 12) * 0.03 }}
      onClick={() => navigate(`/orders/${encodeURIComponent(order.id)}`)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' && e.target === e.currentTarget) navigate(`/orders/${encodeURIComponent(order.id)}`);
      }}
      tabIndex={0}
      role="link"
      aria-label={`Order ${order.id}, ${Orders.tableLabel(order)}, ${Orders.statusLabel(order)}`}
      className={cn(
        'panel group cursor-pointer p-4 outline-none transition-[border-color,transform] duration-200 hover:-translate-y-0.5 hover:border-line-strong focus-visible:border-brand-text/60',
        order.status === 'placed' && 'border-brand-text/40 shadow-[0_0_0_1px_color-mix(in_srgb,var(--brand)_25%,transparent),var(--shadow)]',
      )}
    >
      <div className="flex items-center gap-3">
        <TableBadge table={order.tableNumber} size={compact ? 42 : 46} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="truncate text-[14px] font-semibold text-ink">{AppFormat.orderNumber(order.id)}</span>
            {order.isDemoSample && <Tag>Sample</Tag>}
            {order.source === 'staff' && <Tag tone="info">Staff</Tag>}
          </div>
          <p className="text-[12px] text-faint">{Orders.isActive(order) ? `${AppFormat.time(order.createdAt)} · ${AppFormat.minutes(age)} ago` : AppFormat.dateTime(order.createdAt)}</p>
        </div>
        <OrderStatusBadge status={order.status} takeaway={takeaway} />
      </div>
      {!compact && (
        <>
          <p className="mt-3 line-clamp-2 text-[13px] leading-relaxed text-muted">
            {names.slice(0, 3).join(', ')}
            {names.length > 3 ? ` + ${names.length - 3} more` : ''}
          </p>
          {order.specialInstructions && (
            <p className="mt-1.5 flex items-center gap-1.5 truncate text-[12px] font-medium text-warning">
              <StickyNote size={13} className="shrink-0" aria-hidden />
              <span className="truncate">{order.specialInstructions}</span>
            </p>
          )}
        </>
      )}
      <div className="mt-3 flex items-center gap-3">
        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2">
          <span className="text-[15px] font-bold tabular text-ink">{Currency.format(order.bill.total)}</span>
          {invoice && <PaymentStatusBadge status={invoice.status} />}
        </div>
        {action && ActionIcon && (
          <Button
            size="sm"
            variant={action.target === 'served' ? 'success' : 'primary'}
            icon={ActionIcon}
            loading={busy}
            onClick={(e) => {
              e.stopPropagation();
              void advanceOrder(order);
            }}
          >
            {action.label}
          </Button>
        )}
      </div>
    </motion.article>
  );
}
