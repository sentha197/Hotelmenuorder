import { Ban, CircleAlert, Hourglass, Undo2, Wallet, CreditCard } from 'lucide-react';
import { motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router';
import { methodIcon } from '@/components/domain/Domain';
import { Tag } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { FilterChips, SearchField } from '@/components/ui/Form';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { MetricCard, MetricGrid } from '@/components/ui/Metric';
import { Page } from '@/components/ui/Page';
import { buildLedger, Ledger, ledgerFilterLabel, ledgerFilters, paymentMethodLabel, paymentMethods, refundStatusLabel, type LedgerEntry, type LedgerFilter, type PaymentMethodType } from '@/core/billing';
import { Currency } from '@/core/money';
import { AppFormat, DateRanges, rangePresetLabel, type RangePreset } from '@/core/time';
import { useBills } from '@/state/data';
import { useAccess } from '@/state/session';

const PAGE_SIZE = 150;

/** Every payment attempt and refund recorded against bills (PaymentsScreen). */
export function PaymentsPage() {
  const query = useBills();
  const bills = query.data ?? [];
  const [preset, setPreset] = useState<RangePreset>('today');
  const [filter, setFilter] = useState<LedgerFilter>('all');
  const [method, setMethod] = useState<PaymentMethodType | null>(null);
  const [search, setSearch] = useState('');
  const [limit, setLimit] = useState(PAGE_SIZE);
  const ledger = useMemo(() => buildLedger(bills, DateRanges.preset(preset, new Date()), filter, method, search), [bills, preset, filter, method, search]);
  const shown = ledger.entries.slice(0, limit);

  return (
    <Page title="Payments" subtitle="Payments and refunds recorded against bills">
      {ledger.hasSimulated && (
        <Notice tone="info">
          Payments marked TEST are test payments (from before the payment simulator was removed, or a payment gateway's test environment). No money was charged or refunded for them.
        </Notice>
      )}
      <div className="flex flex-col gap-2.5">
        <FilterChips name="payments-period" values={['today', 'yesterday', 'last7', 'last30'] as RangePreset[]} selected={preset} labelOf={(p) => rangePresetLabel[p]} onSelect={setPreset} />
        <FilterChips name="payments-filter" values={ledgerFilters} selected={filter} labelOf={(f) => ledgerFilterLabel[f]} onSelect={setFilter} />
        <FilterChips name="payments-method" values={[null, ...paymentMethods] as (PaymentMethodType | null)[]} selected={method} labelOf={(m) => (m ? paymentMethodLabel[m] : 'All methods')} onSelect={setMethod} />
      </div>
      <SearchField value={search} onChange={setSearch} placeholder="Search reference, bill, order or table" />
      <MetricGrid>
        <MetricCard index={0} label="Collected" numeric={ledger.collected} format={Currency.format} detail="Successful payments" icon={Wallet} highlight />
        <MetricCard index={1} label="Refunded" numeric={ledger.refunded} format={Currency.format} detail={`Net ${Currency.format(ledger.netCollected)}`} icon={Undo2} tone="warning" />
        <MetricCard index={2} label="Pending" numeric={ledger.pendingAmount} format={Currency.format} detail="Awaiting confirmation" icon={Hourglass} tone="info" />
        <MetricCard index={3} label="Failed attempts" numeric={ledger.failedCount} format={String} detail="No money moved" icon={CircleAlert} tone="danger" />
      </MetricGrid>
      <SectionCard title={`${ledger.entries.length} ${ledger.entries.length === 1 ? 'entry' : 'entries'}`} subtitle={AppFormat.range(ledger.range)}>
        {query.isPending ? (
          <PageSkeleton rows={3} />
        ) : shown.length === 0 ? (
          <Empty compact icon={CreditCard} title="No payments" message="Nothing matches these filters." />
        ) : (
          <>
            <ul className="divide-y divide-line">
              {shown.map((entry, i) => (
                <LedgerRow key={`${entry.invoice.id}-${entry.payment?.id ?? entry.refund?.id}`} entry={entry} index={i} />
              ))}
            </ul>
            {ledger.entries.length > shown.length && (
              <div className="mt-4 flex flex-col items-center gap-2">
                <p className="text-[12px] text-faint">Showing the latest {shown.length}. Narrow the dates or filters to see older entries.</p>
                <Button size="sm" onClick={() => setLimit((l) => l + PAGE_SIZE)}>
                  Show more
                </Button>
              </div>
            )}
          </>
        )}
      </SectionCard>
    </Page>
  );
}

function LedgerRow({ entry, index }: { entry: LedgerEntry; index: number }) {
  const navigate = useNavigate();
  const { can } = useAccess();
  const { invoice, payment, refund } = entry;
  const [color, icon] = payment
    ? payment.status === 'succeeded'
      ? ['var(--success)', methodIcon(payment.method, 18)]
      : payment.status === 'pending'
        ? ['var(--info)', <Hourglass key="i" size={18} aria-hidden />]
        : payment.status === 'failed'
          ? ['var(--danger)', <CircleAlert key="i" size={18} aria-hidden />]
          : ['var(--faint)', <Ban key="i" size={18} aria-hidden />]
    : ['var(--warning)', <Undo2 key="i" size={18} aria-hidden />];
  const moved = refund?.status === 'processed' || payment?.status === 'succeeded';
  const title = refund ? `Refund · ${refundStatusLabel[refund.status]}` : `${payment!.methodLabel} · ${payment!.statusLabel}`;
  const reference = Ledger.reference(entry);
  return (
    <motion.li initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: Math.min(index, 20) * 0.015 }}>
      <button
        type="button"
        disabled={!can('viewBills')}
        onClick={() => navigate(`/bills/${encodeURIComponent(invoice.id)}`)}
        className="flex w-full items-center gap-3 rounded-xl px-1 py-3 text-left transition-colors enabled:hover:bg-panel-2/60"
      >
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl" style={{ color, background: `color-mix(in srgb, ${color} 13%, transparent)` }}>
          {icon}
        </span>
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-2 truncate text-[13.5px] font-semibold text-ink">
            <span className="truncate">{title}</span>
            {Ledger.isSimulated(entry) && <Tag tone="info">Test</Tag>}
          </p>
          <p className="truncate text-[12px] text-muted">
            {invoice.billNumber} · {invoice.tableLabel}
            {reference ? ` · Ref ${reference}` : ''}
          </p>
          <p className="text-[11px] text-faint">{AppFormat.dateTime(Ledger.at(entry))}</p>
        </div>
        <span className={cn('shrink-0 text-[14px] font-bold tabular', !moved && 'text-faint line-through')} style={moved ? { color } : undefined}>
          {refund ? `−${Currency.format(refund.amount)}` : Currency.format(payment!.amount)}
        </span>
      </button>
    </motion.li>
  );
}
