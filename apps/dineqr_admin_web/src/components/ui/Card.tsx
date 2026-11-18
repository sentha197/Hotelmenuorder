import { motion } from 'motion/react';
import type { ReactNode } from 'react';
import { cn } from './cn';

/** A glass panel. */
export function Card({ className, children, as: Tag = 'div' }: { className?: string; children: ReactNode; as?: 'div' | 'section' | 'article' }) {
  return <Tag className={cn('panel', className)}>{children}</Tag>;
}

/** A titled section of a page (SectionCard). */
export function SectionCard({
  title,
  subtitle,
  trailing,
  children,
  className,
  bodyClassName,
  index = 0,
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  trailing?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
  /** Position in the page, for a staggered entrance. */
  index?: number;
}) {
  return (
    <motion.section
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.32, delay: Math.min(index, 8) * 0.04, ease: [0.22, 1, 0.36, 1] }}
      className={cn('panel min-w-0', className)}
    >
      {(title || trailing) && (
        <header className="flex items-start gap-3 px-5 pt-5">
          <div className="min-w-0 flex-1">
            {title && <h2 className="text-[15px] font-semibold leading-tight text-ink">{title}</h2>}
            {subtitle && <p className="mt-1 text-[12.5px] leading-snug text-muted">{subtitle}</p>}
          </div>
          {trailing && <div className="flex shrink-0 items-center gap-2">{trailing}</div>}
        </header>
      )}
      <div className={cn('px-5 pb-5', title || trailing ? 'pt-4' : 'pt-5', bodyClassName)}>{children}</div>
    </motion.section>
  );
}

/** A label and value on one line (InfoRow). */
export function InfoRow({ label, value, valueClassName, strong }: { label: ReactNode; value: ReactNode; valueClassName?: string; strong?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1.5">
      <span className={cn('min-w-0 text-[13px]', strong ? 'font-semibold text-ink' : 'text-muted')}>{label}</span>
      <span className={cn('max-w-[62%] text-right text-[13px] font-semibold tabular text-ink', strong && 'font-bold', valueClassName)}>{value}</span>
    </div>
  );
}
