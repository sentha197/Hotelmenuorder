import { CircleAlert, Info, Lock, TriangleAlert, type LucideIcon } from 'lucide-react';
import { motion } from 'motion/react';
import type { ReactNode } from 'react';
import { permissionInfo, roleInfo, type Permission } from '@/core/access';
import { useAccess } from '@/state/session';
import { cn, toneStyle, type Tone } from './cn';

/** An empty or error state with an icon (AdminEmpty). */
export function Empty({ icon: Icon, title, message, action, compact }: { icon: LucideIcon; title: string; message?: ReactNode; action?: ReactNode; compact?: boolean }) {
  return (
    <motion.div initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} className={cn('flex flex-col items-center text-center', compact ? 'px-4 py-6' : 'px-6 py-12')}>
      <div className="relative mb-4">
        <div className="absolute inset-0 -z-10 scale-150 rounded-full bg-brand/10 blur-2xl" aria-hidden />
        <span className="grid h-14 w-14 place-items-center rounded-2xl border border-line bg-panel-2 text-brand-text">
          <Icon size={24} aria-hidden />
        </span>
      </div>
      <p className="text-[15px] font-semibold text-ink">{title}</p>
      {message && <p className="mt-1 max-w-sm text-[13px] leading-relaxed text-muted">{message}</p>}
      {action && <div className="mt-5">{action}</div>}
    </motion.div>
  );
}

/** Placeholder bars while data loads. */
export function Skeleton({ className }: { className?: string }) {
  return <div className={cn('skeleton', className)} aria-hidden />;
}

/** A page-shaped loading state. */
export function PageSkeleton({ rows = 4 }: { rows?: number }) {
  return (
    <div className="flex flex-col gap-4" aria-busy="true" aria-label="Loading">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {Array.from({ length: 4 }, (_, i) => (
          <Skeleton key={i} className="h-[104px]" />
        ))}
      </div>
      {Array.from({ length: rows }, (_, i) => (
        <Skeleton key={i} className="h-20" />
      ))}
    </div>
  );
}

/** A tinted message box (DemoDataBanner, _Notice, _Banner). */
export function Notice({ tone = 'info', icon, children, action, className }: { tone?: Tone; icon?: LucideIcon; children: ReactNode; action?: ReactNode; className?: string }) {
  const Icon = icon ?? (tone === 'danger' ? CircleAlert : tone === 'warning' ? TriangleAlert : Info);
  return (
    <div style={toneStyle(tone)} className={cn('tone flex items-start gap-3 rounded-2xl px-4 py-3', className)}>
      <Icon size={18} className="mt-0.5 shrink-0" aria-hidden />
      <div className="min-w-0 flex-1 text-[13px] leading-relaxed text-[var(--tone)]">{children}</div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

/** Shown instead of a screen the role cannot open (PermissionNotice). */
export function PermissionNotice({ permission }: { permission: Permission }) {
  const { actor } = useAccess();
  const role = actor ? roleInfo[actor.role].label : 'Your role';
  return (
    <Empty
      icon={Lock}
      title="Not available for your role"
      message={`${role} cannot ${permissionInfo[permission].label.toLowerCase()}. Ask the restaurant owner if you need access.`}
    />
  );
}

/** A spinner for inline waits. */
export function Spinner({ size = 18, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" className={cn('spin text-brand-text', className)} aria-hidden>
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeOpacity="0.2" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}
