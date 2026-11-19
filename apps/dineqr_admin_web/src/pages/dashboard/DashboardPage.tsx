import { CircleCheck, Coffee, CookingPot, Hourglass, ListChecks, Package, ReceiptText, Sigma, Undo2, Utensils, Wallet, BellRing, type LucideIcon } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router';
import { DailyBarChart, RankedBars } from '@/components/charts/Charts';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { toneStyle, type Tone } from '@/components/ui/cn';
import { FilterChips } from '@/components/ui/Form';
import { Empty, Notice } from '@/components/ui/Feedback';
import { MetricCard, MetricGrid } from '@/components/ui/Metric';
import { Page } from '@/components/ui/Page';
import { Stock } from '@/core/inventory';
import { Currency } from '@/core/money';
import { Orders } from '@/core/orders';
import { buildReport } from '@/core/reports';
import { AppFormat, DateRanges, formatOffset, rangePresetLabel, type RangePreset } from '@/core/time';
import { useAudit, useBills, useInventory, useMenu, useOrders, useSettings } from '@/state/data';
import { useAccess } from '@/state/session';
import { OrderCard } from '../orders/OrderCard';

const presets: RangePreset[] = ['today', 'yesterday', 'last7', 'last30'];
const periodLabel: Record<RangePreset, string> = { today: "Today's", yesterday: "Yesterday's", last7: '7-day', last30: '30-day', custom: 'Period' };

const change = (now: number, before: number) => (before === 0 ? null : (now - before) / before);

/** Daily overview: live operations, money in and out, and alerts (DashboardScreen). */
export function DashboardPage() {
  const navigate = useNavigate();
  const { actor, can } = useAccess();
  const [preset, setPreset] = useState<RangePreset>('today');
  const { settings } = useSettings();
  const orders = useOrders().data ?? [];
  const bills = useBills().data ?? [];
  const menu = useMenu().data;
  const inventory = useInventory().data;
  const audit = useAudit().data ?? [];
  const now = new Date();

  const { report, previous, week } = useMemo(() => {
    const categoryOf = (id: string) => menu?.items.find((i) => i.id === id)?.category.label ?? 'Other';
    const range = DateRanges.preset(preset, now);
    return {
      report: buildReport({ orders, invoices: bills, range, now, categoryOf }),
      previous: buildReport({ orders, invoices: bills, range: DateRanges.previous(range), now, categoryOf }),
      week: buildReport({ orders, invoices: bills, range: DateRanges.preset('last7', now), now }),
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orders, bills, menu, preset, settings.utcOffsetMinutes]);

  const financials = can('viewFinancials');
  const seesMoney = financials || can('collectPayments');
  const active = orders.filter(Orders.isActive).sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  const pending = active.filter((o) => o.status === 'placed' || o.status === 'accepted').length;
  const preparing = active.filter((o) => o.status === 'preparing').length;
  const refundsDue = bills.filter((i) => i.refundDue).length;
  const lowStock = can('manageInventory') ? (inventory?.items ?? []).filter((i) => Stock.isLow(i) || Stock.isOut(i)).length : 0;
  const activity = can('viewAuditLog') ? [...audit].sort((a, b) => b.at.getTime() - a.at.getTime()) : [];
  const money = (n: number) => Currency.format(n);
  const first = actor?.name.split(' ')[0] ?? '';
  let index = 0;

  return (
    <Page eyebrow={`${settings.name} · ${AppFormat.date(now)} · ${formatOffset(settings.utcOffsetMinutes)}`} title={<span className="text-gradient">Hello, {first}</span>} subtitle="Live operations, money in and out, and what needs attention.">
      <FilterChips name="dashboard-period" values={presets} selected={preset} labelOf={(p) => rangePresetLabel[p]} onSelect={setPreset} />
      <MetricGrid>
        {financials && (
          <MetricCard
            index={index++}
            label={`${periodLabel[preset]} revenue (collected)`}
            numeric={report.netCollected}
            format={money}
            detail={`Billed ${money(report.billed)}`}
            icon={Wallet}
            change={change(report.netCollected, previous.netCollected)}
            highlight
            onClick={can('viewReports') ? () => navigate('/reports') : undefined}
          />
        )}
        <MetricCard index={index++} label="Total orders" numeric={report.orderCount} format={String} detail={`${report.cancelledCount} cancelled`} icon={ReceiptText} change={change(report.orderCount, previous.orderCount)} onClick={() => navigate('/orders')} />
        <MetricCard index={index++} label="Completed orders" numeric={report.completedCount} format={String} icon={CircleCheck} tone="success" />
        <MetricCard
          index={index++}
          label="Pending orders"
          numeric={pending}
          format={String}
          detail="Live, not yet cooking"
          icon={BellRing}
          tone="info"
          onClick={() => navigate(can('manageKitchen') ? '/kitchen' : '/orders')}
        />
        <MetricCard index={index++} label="Preparing orders" numeric={preparing} format={String} detail="Live" icon={CookingPot} tone="warning" />
        {financials && (
          <MetricCard index={index++} label="Average order value" numeric={report.averageOrderValue} format={money} icon={Sigma} change={change(report.averageOrderValue, previous.averageOrderValue)} />
        )}
        <MetricCard index={index++} label="Paid bills" numeric={report.paidBills} format={String} icon={ListChecks} tone="success" onClick={can('viewBills') ? () => navigate('/bills') : undefined} />
        <MetricCard
          index={index++}
          label="Unpaid bills"
          numeric={report.unpaidBills + report.partiallyPaidBills}
          format={String}
          detail={`${report.partiallyPaidBills} partly paid`}
          icon={Hourglass}
          tone="brand"
          onClick={can('viewBills') ? () => navigate('/bills') : undefined}
        />
        {seesMoney && <MetricCard index={index++} label="Outstanding amount" numeric={report.outstanding} format={money} icon={Hourglass} tone="brand" />}
      </MetricGrid>

      {report.demoOrders > 0 && <Notice tone="info">Includes clearly labelled sample orders and bills. Nothing here represents real money.</Notice>}

      {refundsDue + lowStock > 0 && (
        <div className="flex flex-wrap gap-2" role="list" aria-label="Alerts">
          {refundsDue > 0 && <Alert icon={Undo2} tone="warning" text={`${refundsDue} refund${refundsDue === 1 ? '' : 's'} due`} onClick={can('viewBills') ? () => navigate('/bills') : undefined} />}
          {lowStock > 0 && <Alert icon={Package} tone="brand" text={`${lowStock} item${lowStock === 1 ? '' : 's'} low on stock`} onClick={() => navigate('/inventory')} />}
        </div>
      )}

      {financials && (
        <SectionCard title="Last 7 days" subtitle="Billed vs collected per day" index={1}>
          <DailyBarChart
            days={week.daily.map((d) => ({
              label: AppFormat.weekday(d.dayStart),
              detail: `${AppFormat.weekday(d.dayStart)} ${AppFormat.shortDate(d.dayStart)} · ${d.orders} orders`,
              billed: d.billed,
              collected: d.collected,
            }))}
          />
        </SectionCard>
      )}

      <div className="grid min-w-0 gap-5 lg:grid-cols-2">
        <SectionCard
          title="Live orders"
          subtitle={`${active.length} in progress`}
          index={2}
          trailing={
            active.length > 5 ? (
              <Button size="sm" variant="ghost" onClick={() => navigate('/orders')}>
                View all {active.length}
              </Button>
            ) : undefined
          }
        >
          {active.length === 0 ? (
            <Empty compact icon={Coffee} title="All quiet" message="New orders appear here as guests place them." />
          ) : (
            <div className="flex flex-col gap-2.5">
              {active.slice(0, 5).map((o, i) => (
                <OrderCard key={o.id} order={o} compact index={i} />
              ))}
            </div>
          )}
        </SectionCard>
        <SectionCard title="Top dishes" subtitle={rangePresetLabel[preset]} index={3}>
          {report.items.length === 0 ? (
            <Empty compact icon={Utensils} title="No sales yet" message="Best sellers show up once orders come in." />
          ) : (
            <RankedBars
              maxRows={5}
              values={report.items.map((item) => ({
                label: item.name,
                detail: `${item.quantity} sold`,
                value: financials ? item.revenue : item.quantity,
                amountLabel: financials ? money(item.revenue) : String(item.quantity),
              }))}
            />
          )}
        </SectionCard>
      </div>

      {activity.length > 0 && (
        <div className="grid min-w-0 gap-5">
          {activity.length > 0 && (
            <SectionCard
              title="Recent activity"
              subtitle="From the activity log"
              index={5}
              trailing={
                <Button size="sm" variant="ghost" onClick={() => navigate('/activity')}>
                  View log
                </Button>
              }
            >
              <ol className="relative flex flex-col gap-4 before:absolute before:bottom-2 before:left-[4px] before:top-2 before:w-px before:bg-line">
                {activity.slice(0, 6).map((event) => (
                  <li key={event.id} className="relative flex gap-3.5 pl-0">
                    <span className="relative mt-1.5 h-[9px] w-[9px] shrink-0 rounded-full bg-brand ring-4 ring-bg" aria-hidden />
                    <div className="min-w-0">
                      <p className="text-[13px] leading-snug text-ink">{event.summary}</p>
                      <p className="mt-0.5 text-[11.5px] text-faint">
                        {event.actorName} · {event.actorRole} · {AppFormat.dateTime(event.at)}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            </SectionCard>
          )}
        </div>
      )}
      <p className="text-center text-[12px] text-faint">Revenue counts payments recorded at the billing counter, minus refunds.</p>
    </Page>
  );
}

function Alert({ icon: Icon, tone, text, onClick }: { icon: LucideIcon; tone: Tone; text: string; onClick?: () => void }) {
  return (
    <button type="button" role="listitem" onClick={onClick} disabled={!onClick} style={toneStyle(tone)} className="tone inline-flex items-center gap-2 rounded-full px-3.5 py-2 text-[12.5px] font-semibold transition-transform enabled:hover:-translate-y-0.5 disabled:cursor-default">
      <Icon size={15} aria-hidden />
      {text}
    </button>
  );
}
