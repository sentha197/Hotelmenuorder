import { motion, useReducedMotion } from 'motion/react';
import { useState } from 'react';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { Currency, type Paise } from '@/core/money';
import { cn } from '../ui/cn';

/**
 * Charts follow the data-viz method: thin marks with 4px rounded data-ends,
 * hairline recessive grid, one axis, a legend for two or more series,
 * hover tooltips, and a table view for screen readers. Series colours are a
 * validated categorical order (--series-1…5), never the brand red, which
 * means "danger" elsewhere.
 */

export interface ChartDay {
  /** Short axis label, e.g. `Sat` or `17`. */
  label: string;
  /** Full label for the tooltip, e.g. `Sat 17 Oct · 12 orders`. */
  detail: string;
  billed: Paise;
  collected: Paise;
}

const compact = new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 });
const axisMoney = (paise: number) => (paise === 0 ? '0' : `${Currency.symbol}${compact.format(paise / 100)}`);

function DayTooltip({ active, payload }: { active?: boolean; payload?: readonly { payload?: unknown }[] }) {
  if (!active || !payload?.length) return null;
  const day = payload[0]!.payload as ChartDay;
  return (
    <div className="panel-solid rounded-xl px-3.5 py-2.5 text-[12px]">
      <p className="mb-1.5 font-semibold text-ink">{day.detail}</p>
      {[
        ['Billed', day.billed, 'var(--series-1)'],
        ['Collected', day.collected, 'var(--series-2)'],
      ].map(([label, value, color]) => (
        <p key={label as string} className="flex items-center gap-2 text-muted">
          <span className="h-2.5 w-2.5 rounded-[3px]" style={{ background: color as string }} aria-hidden />
          <span className="flex-1">{label}</span>
          <span className="font-semibold tabular text-ink">{Currency.format(value as number)}</span>
        </p>
      ))}
    </div>
  );
}

/** Billed vs collected per day (DailyBarChart). Hover a day to read its exact values. */
export function DailyBarChart({ days, height = 240 }: { days: ChartDay[]; height?: number }) {
  const reduced = useReducedMotion();
  const barSize = Math.max(4, Math.min(22, Math.floor(560 / Math.max(days.length, 1) / 2.6)));
  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center gap-4 text-[12px] text-muted" aria-hidden>
        <span className="inline-flex items-center gap-2">
          <span className="h-2.5 w-2.5 rounded-[3px] bg-[var(--series-1)]" /> Billed
        </span>
        <span className="inline-flex items-center gap-2">
          <span className="h-2.5 w-2.5 rounded-[3px] bg-[var(--series-2)]" /> Collected
        </span>
      </div>
      <div style={{ height }} aria-hidden>
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={days} barGap={2} barCategoryGap="22%" margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
            <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
            <XAxis dataKey="label" tickLine={false} axisLine={{ stroke: 'var(--chart-axis)' }} tick={{ fill: 'var(--faint)', fontSize: 11 }} interval="preserveStartEnd" minTickGap={6} />
            <YAxis tickFormatter={axisMoney} tickLine={false} axisLine={false} tick={{ fill: 'var(--faint)', fontSize: 11 }} width={52} allowDecimals={false} />
            <Tooltip content={(p) => <DayTooltip active={p.active} payload={p.payload} />} cursor={{ fill: 'var(--panel-2)', radius: 8 }} />
            <Bar dataKey="billed" name="Billed" fill="var(--series-1)" radius={[4, 4, 0, 0]} barSize={barSize} isAnimationActive={!reduced} animationDuration={700} />
            <Bar dataKey="collected" name="Collected" fill="var(--series-2)" radius={[4, 4, 0, 0]} barSize={barSize} isAnimationActive={!reduced} animationDuration={700} animationBegin={120} />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <table className="sr-only">
        <caption>Billed and collected per day</caption>
        <thead>
          <tr>
            <th>Day</th>
            <th>Billed</th>
            <th>Collected</th>
          </tr>
        </thead>
        <tbody>
          {days.map((d) => (
            <tr key={d.detail}>
              <td>{d.detail}</td>
              <td>{Currency.format(d.billed)}</td>
              <td>{Currency.format(d.collected)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export interface RankedValue {
  label: string;
  detail?: string;
  /** Used for the bar length. */
  value: number;
  amountLabel: string;
}

/** Labelled horizontal bars, best first (RankedBars): best sellers, categories, tables, methods. */
export function RankedBars({ values, maxRows = 8 }: { values: RankedValue[]; maxRows?: number }) {
  const reduced = useReducedMotion();
  const [expanded, setExpanded] = useState(false);
  const shown = expanded ? values : values.slice(0, maxRows);
  const max = Math.max(1, ...values.map((v) => v.value));
  return (
    <div>
      <ol className="flex flex-col gap-3">
        {shown.map((v, i) => (
          <li key={`${v.label}-${i}`} className="min-w-0">
            <div className="mb-1.5 flex items-baseline gap-3">
              <span className="w-5 shrink-0 text-[11px] font-semibold tabular text-faint">{i + 1}</span>
              <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-ink">{v.label}</span>
              {v.detail && <span className="hidden shrink-0 text-[11.5px] text-faint sm:inline">{v.detail}</span>}
              <span className="shrink-0 text-[13px] font-semibold tabular text-ink">{v.amountLabel}</span>
            </div>
            <div className="ml-8 h-2 overflow-hidden rounded-full bg-panel-3">
              <motion.div
                className="h-full rounded-full bg-[var(--series-2)]"
                initial={{ width: reduced ? `${(v.value / max) * 100}%` : 0 }}
                animate={{ width: `${Math.max(2, (v.value / max) * 100)}%` }}
                transition={{ duration: reduced ? 0 : 0.7, delay: reduced ? 0 : i * 0.05, ease: [0.22, 1, 0.36, 1] }}
              />
            </div>
          </li>
        ))}
      </ol>
      {values.length > maxRows && (
        <button type="button" onClick={() => setExpanded((e) => !e)} className="mt-3 text-[12.5px] font-semibold text-brand-text hover:underline">
          {expanded ? 'Show fewer' : `Show all ${values.length}`}
        </button>
      )}
    </div>
  );
}

export interface SharePart {
  key: string;
  label: string;
  value: Paise;
}

const seriesVar = (slot: number) => `var(--series-${(slot % 5) + 1})`;

/**
 * One whole split into parts (successful payments by method): a segmented
 * bar with a 2px surface gap and a legend list with each part's amount and
 * share. [slotOf] keeps each part's colour fixed whatever its rank.
 */
export function ShareBar({ parts, slotOf }: { parts: SharePart[]; slotOf: (key: string) => number }) {
  const reduced = useReducedMotion();
  const total = parts.reduce((s, p) => s + p.value, 0);
  if (total <= 0) return null;
  const ordered = [...parts].sort((a, b) => slotOf(a.key) - slotOf(b.key));
  return (
    <div>
      <div className="flex h-4 w-full gap-[2px] overflow-hidden rounded-md" role="img" aria-label={ordered.map((p) => `${p.label} ${Math.round((p.value / total) * 100)}%`).join(', ')}>
        {ordered.map((p, i) => (
          <motion.div
            key={p.key}
            title={`${p.label}: ${Currency.format(p.value)}`}
            className={cn('h-full', i === 0 && 'rounded-l-md', i === ordered.length - 1 && 'rounded-r-md')}
            style={{ background: seriesVar(slotOf(p.key)) }}
            initial={{ flexGrow: reduced ? p.value : 0 }}
            animate={{ flexGrow: p.value }}
            transition={{ duration: reduced ? 0 : 0.8, ease: [0.22, 1, 0.36, 1] }}
          />
        ))}
      </div>
      <ul className="mt-4 flex flex-col divide-y divide-line">
        {[...parts]
          .sort((a, b) => b.value - a.value)
          .map((p) => (
            <li key={p.key} className="flex items-center gap-3 py-2">
              <span className="h-3 w-3 shrink-0 rounded-[4px]" style={{ background: seriesVar(slotOf(p.key)) }} aria-hidden />
              <span className="min-w-0 flex-1 text-[13px] text-ink">{p.label}</span>
              <span className="text-[12px] tabular text-faint">{Math.round((p.value / total) * 100)}%</span>
              <span className="w-24 text-right text-[13px] font-semibold tabular text-ink">{Currency.format(p.value)}</span>
            </li>
          ))}
      </ul>
    </div>
  );
}
