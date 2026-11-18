import { ArrowDownRight, ArrowUpRight, type LucideIcon } from 'lucide-react';
import { animate, motion, useMotionValue, useReducedMotion, useTransform } from 'motion/react';
import { useEffect, type ReactNode } from 'react';
import { cn, toneStyle, type Tone } from './cn';

/**
 * Counts up to a figure when it first appears or changes. [format] turns the
 * running number back into text (amounts stay exact at the end).
 */
export function AnimatedNumber({ value, format }: { value: number; format: (n: number) => string }) {
  const reduced = useReducedMotion();
  const mv = useMotionValue(reduced ? value : 0);
  const text = useTransform(mv, (n) => format(Math.round(n)));
  useEffect(() => {
    if (reduced) {
      mv.set(value);
      return;
    }
    const controls = animate(mv, value, { duration: 0.9, ease: [0.22, 1, 0.36, 1] });
    return () => controls.stop();
  }, [value, mv, reduced]);
  return <motion.span>{text}</motion.span>;
}

/** One figure on a dashboard (MetricCard). */
export function MetricCard({
  label,
  value,
  numeric,
  format,
  detail,
  icon: Icon,
  tone = 'brand',
  change,
  highlight,
  onClick,
  index = 0,
}: {
  label: string;
  /** Shown as is when [numeric] is not given. */
  value?: ReactNode;
  /** A number counted up with [format]. */
  numeric?: number;
  format?: (n: number) => string;
  detail?: ReactNode;
  icon: LucideIcon;
  tone?: Tone;
  /** Relative change versus the previous period (0.12 = +12%). */
  change?: number | null;
  highlight?: boolean;
  onClick?: () => void;
  index?: number;
}) {
  const Tag = onClick ? motion.button : motion.div;
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      onClick={onClick}
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, delay: Math.min(index, 10) * 0.035, ease: [0.22, 1, 0.36, 1] }}
      whileHover={onClick ? { y: -3 } : undefined}
      style={toneStyle(highlight ? 'ember' : tone)}
      className={cn(
        'group relative flex min-h-[112px] min-w-0 flex-col overflow-hidden rounded-[var(--radius-card)] border p-4 text-left',
        highlight ? 'border-white/10 text-white shadow-glow brand-fill' : 'panel',
        onClick && 'cursor-pointer',
      )}
    >
      {!highlight && <span className="pointer-events-none absolute -right-8 -top-10 h-28 w-28 rounded-full bg-[var(--tone)] opacity-[0.07] blur-2xl transition-opacity group-hover:opacity-[0.14]" aria-hidden />}
      <div className="flex items-start justify-between gap-2">
        <span className={cn('text-[12px] font-medium leading-snug', highlight ? 'text-white/85' : 'text-muted')}>{label}</span>
        <span className={cn('grid h-8 w-8 shrink-0 place-items-center rounded-xl', highlight ? 'bg-white/15 text-white' : 'tone')}>
          <Icon size={16} aria-hidden />
        </span>
      </div>
      <div className={cn('mt-auto pt-3 text-[22px] font-bold leading-none tracking-tight tabular sm:text-[24px]', highlight ? 'text-white' : 'text-ink')}>
        {numeric != null && format ? <AnimatedNumber value={numeric} format={format} /> : value}
      </div>
      <div className="mt-2 flex min-h-[18px] flex-wrap items-center gap-2">
        {detail && <span className={cn('text-[11.5px] leading-snug', highlight ? 'text-white/80' : 'text-faint')}>{detail}</span>}
        {change != null && <ChangeChip change={change} onDark={highlight} />}
      </div>
    </Tag>
  );
}

function ChangeChip({ change, onDark }: { change: number; onDark?: boolean }) {
  const up = change >= 0;
  const percent = Math.abs(change) * 100;
  const text = percent >= 999 ? '999%+' : `${percent.toFixed(percent < 10 ? 1 : 0)}%`;
  return (
    <span
      title={`${up ? 'Up' : 'Down'} ${text} versus the previous period`}
      className={cn(
        'inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-[10.5px] font-bold',
        onDark ? 'bg-white/15 text-white' : up ? 'bg-success/12 text-success' : 'bg-danger/12 text-danger',
      )}
    >
      {up ? <ArrowUpRight size={12} aria-hidden /> : <ArrowDownRight size={12} aria-hidden />}
      {text}
    </span>
  );
}

/** Responsive grid of metric cards (MetricGrid). */
export function MetricGrid({ children, min = 168 }: { children: ReactNode; min?: number }) {
  return (
    <div className="grid gap-3" style={{ gridTemplateColumns: `repeat(auto-fill, minmax(min(100%, ${min}px), 1fr))` }}>
      {children}
    </div>
  );
}
