import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { cn, toneStyle, type Tone } from './cn';

/** A small tinted label. */
export function Badge({ tone = 'muted', icon: Icon, children, className, solid }: { tone?: Tone; icon?: LucideIcon; children: ReactNode; className?: string; solid?: boolean }) {
  return (
    <span
      style={toneStyle(tone)}
      className={cn(
        'inline-flex shrink-0 items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-[3px] text-[11px] font-semibold leading-none tracking-wide',
        solid ? 'tone-solid' : 'tone',
        className,
      )}
    >
      {Icon && <Icon size={12} aria-hidden />}
      {children}
    </span>
  );
}

/** A tiny uppercase tag (SAMPLE, STAFF, TEST). */
export function Tag({ children, tone = 'ember' }: { children: ReactNode; tone?: Tone }) {
  return (
    <span style={toneStyle(tone)} className="tone inline-flex shrink-0 items-center rounded-md px-1.5 py-[2px] text-[9.5px] font-bold uppercase leading-none tracking-[0.08em]">
      {children}
    </span>
  );
}

/** A status dot with a label. */
export function Dot({ tone, label, pulse }: { tone: Tone; label?: ReactNode; pulse?: boolean }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-[12px] text-muted" style={toneStyle(tone)}>
      <span className={cn('h-2 w-2 rounded-full bg-[var(--tone)]', pulse && 'live-dot')} aria-hidden />
      {label}
    </span>
  );
}
