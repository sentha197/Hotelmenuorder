import type { Paise } from '../core/money';
import type { BillBreakdown } from '../core/pricing';
import { AnimatedMoney } from './money';

export function BillRow({
  label,
  amount,
  strong = false,
  negative = false,
  color,
}: {
  label: string;
  amount: Paise;
  strong?: boolean;
  negative?: boolean;
  color?: string;
}) {
  return (
    <div className={`bill-row ${strong ? 'bill-row--strong' : ''}`} style={color ? { color } : undefined}>
      <span className="bill-row__label">{label}</span>
      <span className="bill-row__amount">
        {negative && '− '}
        <AnimatedMoney value={amount} />
      </span>
    </div>
  );
}

/** Subtotal, discount, charges, tax and total; optionally paid and due. */
export function BillSummary({
  bill,
  paid,
  refunded,
  outstanding,
}: {
  bill: BillBreakdown;
  paid?: Paise;
  refunded?: Paise;
  outstanding?: Paise;
}) {
  return (
    <div className="stack-sm">
      <BillRow label="Subtotal" amount={bill.subtotal} />
      {bill.hasDiscount && <BillRow label={bill.discountLabel ?? 'Discount'} amount={bill.discount} negative color="var(--success)" />}
      {bill.hasServiceCharge && <BillRow label={bill.serviceChargeLabel} amount={bill.serviceCharge} />}
      <BillRow label={bill.taxLabel} amount={bill.tax} />
      <hr className="dashed" style={{ margin: '12px 0' }} />
      <BillRow label="Total Amount" amount={bill.total} strong />
      {paid != null && <BillRow label="Paid" amount={paid} color="var(--success)" />}
      {refunded != null && refunded !== 0 && <BillRow label="Refunded" amount={refunded} negative color="var(--warning)" />}
      {outstanding != null && (
        <BillRow
          label="Balance due"
          amount={outstanding}
          strong={outstanding !== 0}
          color={outstanding === 0 ? 'var(--success)' : 'var(--accent-text)'}
        />
      )}
    </div>
  );
}
