import { ArrowLeft } from 'lucide-react';
import { motion } from 'motion/react';
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router';
import { cn } from './cn';

/**
 * The standard page: title row with actions, then content limited to a
 * readable width (AdminPage). [back] shows a back button (detail pages).
 */
export function Page({
  title,
  subtitle,
  eyebrow,
  actions,
  children,
  width = 'wide',
  back,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  eyebrow?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  width?: 'narrow' | 'medium' | 'wide' | 'full';
  back?: string | true;
}) {
  const navigate = useNavigate();
  const max = { narrow: 'max-w-3xl', medium: 'max-w-4xl', wide: 'max-w-7xl', full: 'max-w-none' }[width];
  return (
    <div className={cn('mx-auto w-full px-4 pb-28 pt-5 sm:px-6 md:pb-12 lg:px-8 lg:pt-7', max)}>
      <motion.header
        initial={{ opacity: 0, y: -6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
        className="no-print mb-6 flex flex-wrap items-end gap-x-4 gap-y-3"
      >
        <div className="flex min-w-0 flex-1 items-start gap-3">
          {back && (
            <button
              type="button"
              aria-label="Back"
              onClick={() => (back === true ? navigate(-1) : navigate(back))}
              className="mt-0.5 grid h-10 w-10 shrink-0 place-items-center rounded-xl border border-line bg-panel text-muted transition-colors hover:border-line-strong hover:text-ink"
            >
              <ArrowLeft size={18} aria-hidden />
            </button>
          )}
          <div className="min-w-0">
            {eyebrow && <div className="mb-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-brand-text">{eyebrow}</div>}
            <h1 className="truncate text-[22px] font-bold leading-tight tracking-tight text-ink sm:text-[26px]">{title}</h1>
            {subtitle && <p className="mt-1 text-[13px] leading-snug text-muted">{subtitle}</p>}
          </div>
        </div>
        {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
      </motion.header>
      <div className="flex flex-col gap-5">{children}</div>
    </div>
  );
}

/** Two columns on wide screens, stacked on narrow ones (_TwoUp). */
export function TwoUp({ left, right }: { left: ReactNode; right: ReactNode }) {
  return (
    <div className="grid min-w-0 gap-5 lg:grid-cols-2">
      <div className="min-w-0">{left}</div>
      <div className="min-w-0">{right}</div>
    </div>
  );
}
