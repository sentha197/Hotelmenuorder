import { ChartColumn, ChevronRight, FileDown, FileSpreadsheet, Printer, ReceiptText, Sigma, TrendingUp, Utensils, Wallet, Hourglass } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { DailyBarChart, RankedBars, ShareBar } from '@/components/charts/Charts';
import { Lockup } from '@/components/brand/Brand';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { Dialog } from '@/components/ui/Dialog';
import { FilterChips } from '@/components/ui/Form';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { MetricCard, MetricGrid } from '@/components/ui/Metric';
import { Page, TwoUp } from '@/components/ui/Page';
import { paymentMethodLabel, paymentMethods } from '@/core/billing';
import { Currency } from '@/core/money';
import { Tables } from '@/core/orders';
import { buildReport, reportCsv, reportDefinitions, type SalesReport } from '@/core/reports';
import { OfferRules } from '@/core/offers';
import { AppFormat, DateRanges, formatOffset, rangePresetLabel, type DateRange, type RangePreset } from '@/core/time';
import { useBills, useMenu, useOrders, useSettings } from '@/state/data';
import { runAction } from '@/state/run';
import { Session, useAccess } from '@/state/session';

const presets: RangePreset[] = ['today', 'yesterday', 'last7', 'last30', 'custom'];

/** Today in restaurant time as `yyyy-mm-dd`, and a day [n] days away. */
const OfferDay = {
  today: () => OfferRules.dayJson(OfferRules.today()),
  shift: (day: string, n: number) => OfferRules.dayJson(new Date(OfferRules.parseDay(day)!.getTime() + n * 86_400_000)),
};
const money = (n: number) => Currency.format(n);

/** The report for a range, from the same orders and bills the other screens use. */
function useReport(range: DateRange) {
  const orders = useOrders();
  const bills = useBills();
  const menu = useMenu().data;
  const { settings } = useSettings();
  const report = useMemo(
    () =>
      buildReport({
        orders: orders.data ?? [],
        invoices: bills.data ?? [],
        range,
        now: new Date(),
        categoryOf: (id) => menu?.items.find((i) => i.id === id)?.category.label ?? 'Other',
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [orders.data, bills.data, menu, range.start.getTime(), range.end.getTime(), settings.utcOffsetMinutes],
  );
  return { report, loading: orders.isPending || bills.isPending, settings };
}

function rangeFromParams(params: URLSearchParams): DateRange {
  const from = params.get('from');
  const to = params.get('to');
  if (from && to && /^\d{4}-\d{2}-\d{2}$/.test(from) && /^\d{4}-\d{2}-\d{2}$/.test(to)) return DateRanges.days(from, to);
  const preset = params.get('range') as RangePreset | null;
  return DateRanges.preset(preset && presets.includes(preset) && preset !== 'custom' ? preset : 'last7', new Date());
}

/** Sales, collections, taxes, best sellers and exports (ReportsScreen). */
export function ReportsPage() {
  const navigate = useNavigate();
  const { can } = useAccess();
  const [preset, setPreset] = useState<RangePreset>('last7');
  const [custom, setCustom] = useState<{ from: string; to: string } | null>(null);
  const [picking, setPicking] = useState(false);
  const [definitions, setDefinitions] = useState(false);
  const range = preset === 'custom' && custom ? DateRanges.days(custom.from, custom.to) : DateRanges.preset(preset === 'custom' ? 'last7' : preset, new Date());
  const { report, loading, settings } = useReport(range);
  const financials = can('viewFinancials');
  const canExport = financials && can('exportReports');

  const exportCsv = () =>
    runAction(async () => {
      Session.require('exportReports');
      const blob = new Blob([`﻿${reportCsv(report, settings)}`], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `DineQR-report-${AppFormat.fileStamp(new Date())}.csv`;
      document.body.append(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
    });

  const exportPdf = () =>
    navigate(`/reports/print?${custom && preset === 'custom' ? `from=${custom.from}&to=${custom.to}` : `range=${preset === 'custom' ? 'last7' : preset}`}`);

  return (
    <Page
      title="Reports"
      subtitle={`${AppFormat.range(range)} · ${formatOffset(settings.utcOffsetMinutes)}`}
      actions={
        canExport && (
          <>
            <Button icon={FileSpreadsheet} onClick={() => void exportCsv()}>
              Export CSV
            </Button>
            <Button variant="primary" icon={FileDown} onClick={exportPdf}>
              Export PDF
            </Button>
          </>
        )
      }
    >
      <FilterChips
        name="report-range"
        values={presets}
        selected={preset}
        labelOf={(p) => (p === 'custom' && custom ? AppFormat.range(DateRanges.days(custom.from, custom.to)) : rangePresetLabel[p])}
        onSelect={(p) => (p === 'custom' ? setPicking(true) : setPreset(p))}
      />
      {!financials && <Notice tone="info">Your role sees operational figures. Revenue, taxes and exports are available to owners and accountants.</Notice>}
      {report.demoOrders > 0 && <Notice tone="info">{report.demoOrders} demo sample orders in this period are included and labelled.</Notice>}
      {loading ? (
        <PageSkeleton />
      ) : report.isEmpty ? (
        <Empty icon={ChartColumn} title="No activity in this period" message="Pick another period to see figures." />
      ) : (
        <>
          <MetricGrid>
            {financials && (
              <>
                <MetricCard index={0} label="Net sales" numeric={report.netSales} format={money} detail={`Gross ${money(report.grossSales)}`} icon={TrendingUp} highlight />
                <MetricCard index={1} label="Collected" numeric={report.collected} format={money} detail={`Net ${money(report.netCollected)}`} icon={Wallet} tone="success" />
                <MetricCard index={2} label="Outstanding" numeric={report.outstanding} format={money} icon={Hourglass} />
                <MetricCard index={3} label="Average order value" numeric={report.averageOrderValue} format={money} icon={Sigma} />
              </>
            )}
            <MetricCard index={4} label="Orders" numeric={report.orderCount} format={String} detail={`${report.cancelledCount} cancelled`} icon={ReceiptText} />
            <MetricCard index={5} label="Dishes sold" numeric={report.items.reduce((s, i) => s + i.quantity, 0)} format={String} icon={Utensils} />
          </MetricGrid>

          {financials && (
            <SectionCard title="Daily sales" subtitle="Billed vs collected" index={1}>
              <DailyBarChart
                days={report.daily.map((d) => ({
                  label: report.daily.length <= 7 ? AppFormat.weekday(d.dayStart) : AppFormat.dayOfMonth(d.dayStart),
                  detail: `${AppFormat.weekday(d.dayStart)} ${AppFormat.shortDate(d.dayStart)} · ${d.orders} orders`,
                  billed: d.billed,
                  collected: d.collected,
                }))}
              />
            </SectionCard>
          )}

          {financials && (
            <SectionCard
              title="Breakdown"
              index={2}
              trailing={
                <Button size="sm" variant="ghost" onClick={() => setDefinitions((d) => !d)}>
                  {definitions ? 'Hide definitions' : 'How it is calculated'}
                </Button>
              }
            >
              <Breakdown report={report} />
              <AnimatePresence initial={false}>
                {definitions && (
                  <motion.dl initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="mt-4 overflow-hidden rounded-xl bg-panel-2 p-4">
                    {reportDefinitions.map(([term, meaning]) => (
                      <div key={term} className="mb-1.5 text-[12.5px] last:mb-0">
                        <dt className="inline font-semibold text-ink">{term}: </dt>
                        <dd className="inline text-muted">{meaning}</dd>
                      </div>
                    ))}
                  </motion.dl>
                )}
              </AnimatePresence>
            </SectionCard>
          )}

          <TwoUp
            left={
              <SectionCard title="Best-selling dishes" index={3}>
                <RankedBars
                  values={report.items.map((i) => ({ label: i.name, detail: `${i.quantity} sold`, value: financials ? i.revenue : i.quantity, amountLabel: financials ? money(i.revenue) : String(i.quantity) }))}
                />
              </SectionCard>
            }
            right={
              <SectionCard title="Categories" index={4}>
                <RankedBars values={report.categories.map((c) => ({ label: c.name, detail: `${c.quantity} sold`, value: financials ? c.revenue : c.quantity, amountLabel: financials ? money(c.revenue) : String(c.quantity) }))} />
              </SectionCard>
            }
          />

          {financials && (
            <TwoUp
              left={
                <SectionCard title="Counter collections" subtitle="Payments taken at the billing counter, by method" index={5}>
                  {report.byMethod.size === 0 ? (
                    <Empty compact icon={Wallet} title="No payments" message="Nothing was collected in this period." />
                  ) : (
                    <ShareBar parts={[...report.byMethod.entries()].map(([m, v]) => ({ key: m, label: paymentMethodLabel[m], value: v }))} slotOf={(key) => paymentMethods.indexOf(key as never)} />
                  )}
                </SectionCard>
              }
              right={
                <SectionCard title="Tax summary" subtitle="As recorded on bills" index={6}>
                  {report.taxLines.length === 0 ? (
                    <Empty compact icon={Sigma} title="No taxes recorded" message="No bills in this period." />
                  ) : (
                    report.taxLines.map((t) => (
                      <div key={t.label} className="mb-2">
                        <Line label={t.label} value={money(t.tax)} strong />
                        <Line label={`Taxable amount (${t.bills} bills)`} value={money(t.taxable)} />
                      </div>
                    ))
                  )}
                </SectionCard>
              }
            />
          )}

          {financials && report.outstandingBills.length > 0 && (
            <SectionCard title="Outstanding bills" subtitle={`${report.outstandingBills.length} with a balance due`} index={7}>
              <ul className="divide-y divide-line">
                {report.outstandingBills.slice(0, 10).map((i) => (
                  <li key={i.id}>
                    <button type="button" disabled={!can('viewBills')} onClick={() => navigate(`/bills/${encodeURIComponent(i.id)}`)} className="flex w-full items-center gap-3 py-2.5 text-left enabled:hover:bg-panel-2/50">
                      <span className="min-w-0 flex-1 truncate text-[13px] text-ink">
                        {i.billNumber} · {i.tableLabel}
                      </span>
                      <span className="text-[13px] font-bold text-brand-text tabular">Due {money(i.outstanding)}</span>
                      <ChevronRight size={16} className="text-faint" aria-hidden />
                    </button>
                  </li>
                ))}
              </ul>
            </SectionCard>
          )}

          {financials && report.refundRecords.length > 0 && (
            <SectionCard title="Refunds" index={8}>
              {report.refundRecords.map((r) => (
                <Line key={r.id} label={`${AppFormat.date(r.createdAt)} · ${r.reason}${r.isSimulated ? ' (test)' : ''}`} value={`− ${money(r.amount)}`} />
              ))}
            </SectionCard>
          )}

          {report.tables.length >= 2 && (
            <SectionCard title="Table utilisation" subtitle="Orders per table" index={9}>
              <RankedBars maxRows={6} values={report.tables.map((t) => ({ label: Tables.label(t.table), detail: financials ? money(t.billed) : '', value: t.orders, amountLabel: `${t.orders} orders` }))} />
            </SectionCard>
          )}
        </>
      )}
      <CustomRange
        open={picking}
        initial={custom}
        onClose={() => setPicking(false)}
        onPick={(r) => {
          setCustom(r);
          setPreset('custom');
          setPicking(false);
        }}
      />
    </Page>
  );
}

function Breakdown({ report }: { report: SalesReport }) {
  return (
    <div>
      <Line label="Gross sales" value={money(report.grossSales)} />
      <Line label="Discounts" value={`− ${money(report.discounts)}`} />
      <Line label="Service charges" value={money(report.serviceCharges)} />
      <Line label="Taxes" value={money(report.taxes)} />
      <Line label="Billed" value={money(report.billed)} strong />
      <div className="my-2 h-px bg-line" />
      <Line label="Collected" value={money(report.collected)} />
      <Line label="Refunds" value={`− ${money(report.refunds)}`} />
      <Line label="Net collected" value={money(report.netCollected)} strong />
      <Line label="Net sales" value={money(report.netSales)} strong />
      <Line label="Outstanding" value={money(report.outstanding)} />
      <Line label="Bills" value={`${report.paidBills} paid · ${report.partiallyPaidBills} partly paid · ${report.unpaidBills} unpaid`} />
    </div>
  );
}

function Line({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1">
      <span className={cn('min-w-0 text-[13px]', strong ? 'font-semibold text-ink' : 'text-muted')}>{label}</span>
      <span className={cn('max-w-[60%] text-right text-[13px] tabular text-ink', strong ? 'font-bold' : 'font-semibold')}>{value}</span>
    </div>
  );
}

function CustomRange({ open, initial, onClose, onPick }: { open: boolean; initial: { from: string; to: string } | null; onClose: () => void; onPick: (r: { from: string; to: string }) => void }) {
  const today = OfferDay.today();
  const weekAgo = OfferDay.shift(today, -6);
  const [from, setFrom] = useState(initial?.from ?? weekAgo);
  const [to, setTo] = useState(initial?.to ?? today);
  const valid = /^\d{4}-\d{2}-\d{2}$/.test(from) && /^\d{4}-\d{2}-\d{2}$/.test(to);
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Custom period"
      description="Whole restaurant days, both included."
      size="sm"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" disabled={!valid} onClick={() => onPick(from <= to ? { from, to } : { from: to, to: from })}>
            Show
          </Button>
        </>
      }
    >
      <div className="grid grid-cols-2 gap-3 pb-2">
        <label className="flex flex-col gap-1.5 text-[12.5px] font-medium text-muted">
          From
          <input type="date" className="field" min="2020-01-01" max={today} value={from} onChange={(e) => setFrom(e.target.value)} />
        </label>
        <label className="flex flex-col gap-1.5 text-[12.5px] font-medium text-muted">
          To
          <input type="date" className="field" min="2020-01-01" max={today} value={to} onChange={(e) => setTo(e.target.value)} />
        </label>
      </div>
    </Dialog>
  );
}

/**
 * The report laid out for paper: print it, or save it as a PDF from the
 * print dialog (ReportPdf). Needs the export permission, like the export.
 */
export function ReportPrintPage() {
  const [params] = useSearchParams();
  const range = rangeFromParams(params);
  const { report, loading, settings } = useReport(range);
  const { actor } = useAccess();
  if (loading) return <Page title="Report" back="/reports"><PageSkeleton /></Page>;
  return (
    <Page
      title="Sales report"
      subtitle={`${AppFormat.range(range)} · print it, or choose "Save as PDF" in the print dialog`}
      back="/reports"
      width="medium"
      actions={
        <Button variant="primary" icon={Printer} onClick={() => window.print()}>
          Print / save PDF
        </Button>
      }
    >
      <article className="print-area rounded-[var(--radius-card)] bg-white p-6 text-[#1d1416] shadow-lift sm:p-9" style={{ colorScheme: 'light' }}>
        <header className="flex flex-wrap items-start justify-between gap-4 border-b border-black/10 pb-5">
          <div>
            <Lockup height={34} trim onLight />
            <p className="mt-2 text-[15px] font-semibold">{settings.name}</p>
          </div>
          <div className="text-right text-[12px] text-[#6b5a5d]">
            <p className="text-[13px] font-bold uppercase tracking-[0.16em] text-[#b5121b]">Sales report</p>
            <p>{AppFormat.range(range)}</p>
            <p>Time zone {formatOffset(settings.utcOffsetMinutes)} · {settings.currencyCode}</p>
            <p>
              Generated {AppFormat.dateTime(report.generatedAt)}
              {actor ? ` by ${actor.name}` : ''}
            </p>
          </div>
        </header>
        <section className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {[
            ['Net sales', money(report.netSales)],
            ['Collected', money(report.collected)],
            ['Outstanding', money(report.outstanding)],
            ['Orders', String(report.orderCount)],
          ].map(([k, v]) => (
            <div key={k} className="rounded-xl bg-[#f7f2f1] p-3">
              <p className="text-[11px] text-[#6b5a5d]">{k}</p>
              <p className="text-[17px] font-bold tabular">{v}</p>
            </div>
          ))}
        </section>
        <PrintTable title="Summary" head={['Metric', 'Value']} rows={[
          ['Gross sales', money(report.grossSales)],
          ['Discounts', `− ${money(report.discounts)}`],
          ['Service charges', money(report.serviceCharges)],
          ['Taxes', money(report.taxes)],
          ['Billed', money(report.billed)],
          ['Collected', money(report.collected)],
          ['Refunds', `− ${money(report.refunds)}`],
          ['Net collected', money(report.netCollected)],
          ['Net sales', money(report.netSales)],
          ['Average order value', money(report.averageOrderValue)],
          ['Completed / cancelled orders', `${report.completedCount} / ${report.cancelledCount}`],
          ['Bills paid · partly paid · unpaid', `${report.paidBills} · ${report.partiallyPaidBills} · ${report.unpaidBills}`],
        ]} />
        <PrintTable title="Daily sales" head={['Date', 'Orders', 'Billed', 'Collected']} rows={report.daily.map((d) => [AppFormat.date(d.dayStart), String(d.orders), money(d.billed), money(d.collected)])} />
        <PrintTable title="Dishes" head={['Dish', 'Category', 'Quantity', 'Revenue']} rows={report.items.map((i) => [i.name, i.category, String(i.quantity), money(i.revenue)])} />
        <PrintTable title="Counter collections by method" head={['Method', 'Collected']} rows={[...report.byMethod.entries()].map(([m, v]) => [paymentMethodLabel[m], money(v)])} />
        <PrintTable title="Taxes" head={['Tax', 'Bills', 'Taxable amount', 'Tax']} rows={report.taxLines.map((t) => [t.label, String(t.bills), money(t.taxable), money(t.tax)])} />
        <PrintTable title="Refunds" head={['Date', 'Bill', 'Amount', 'Reason']} rows={report.refundRecords.map((r) => [AppFormat.dateTime(r.createdAt), r.invoiceId, money(r.amount), r.reason])} />
        <PrintTable title="Outstanding bills" head={['Bill', 'Table', 'Total', 'Paid', 'Outstanding']} rows={report.outstandingBills.map((i) => [i.billNumber, Tables.shortLabel(i.tableNumber), money(i.total), money(i.amountPaid), money(i.outstanding)])} />
        <section className="print-avoid mt-6 text-[11px] text-[#6b5a5d]">
          {reportDefinitions.map(([term, meaning]) => (
            <p key={term}>
              <b>{term}:</b> {meaning}
            </p>
          ))}
        </section>
      </article>
    </Page>
  );
}

function PrintTable({ title, head, rows }: { title: string; head: string[]; rows: string[][] }) {
  if (rows.length === 0) return null;
  return (
    <section className="print-avoid mt-6">
      <h2 className="mb-2 text-[12px] font-bold uppercase tracking-[0.12em] text-[#b5121b]">{title}</h2>
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-[12px]">
          <thead>
            <tr className="border-b border-black/15 text-left text-[#6b5a5d]">
              {head.map((h, i) => (
                <th key={h} className={cn('py-1.5 pr-3 font-semibold', i > 0 && 'text-right')}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, r) => (
              <tr key={r} className="border-b border-black/5">
                {row.map((cell, i) => (
                  <td key={i} className={cn('py-1.5 pr-3', i > 0 && 'text-right tabular')}>
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

