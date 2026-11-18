import { LoaderCircle, type LucideIcon } from 'lucide-react';
import { motion } from 'motion/react';
import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react';
import { cn } from './cn';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'success' | 'subtle';
type Size = 'sm' | 'md' | 'lg';

const variants: Record<Variant, string> = {
  primary: 'brand-fill shadow-glow hover:brightness-110 border border-white/10',
  secondary: 'bg-panel-2 text-ink border border-line-strong hover:bg-panel-3 hover:border-brand-text/40',
  subtle: 'bg-panel-2 text-ink border border-transparent hover:bg-panel-3',
  ghost: 'text-muted hover:text-ink hover:bg-panel-2 border border-transparent',
  danger: 'text-danger border border-danger/35 bg-danger/8 hover:bg-danger/15',
  success: 'text-white border border-white/10 bg-[linear-gradient(135deg,#22c55e,#15803d)] hover:brightness-110',
};

const sizes: Record<Size, string> = {
  sm: 'h-8 px-3 text-[12.5px] gap-1.5 rounded-lg',
  md: 'h-10 px-4 text-[13.5px] gap-2 rounded-xl',
  lg: 'h-12 px-5 text-[14.5px] gap-2.5 rounded-2xl',
};

export interface ButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onDrag' | 'onDragStart' | 'onDragEnd' | 'onAnimationStart'> {
  variant?: Variant;
  size?: Size;
  icon?: LucideIcon;
  /** Shows a spinner and disables the button. */
  loading?: boolean;
  block?: boolean;
  children?: ReactNode;
}

/** The standard button: brand gradient for the main action, glass for the rest. */
export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'secondary', size = 'md', icon: Icon, loading, block, className, children, disabled, type = 'button', ...rest },
  ref,
) {
  const iconSize = size === 'sm' ? 15 : size === 'lg' ? 19 : 17;
  return (
    <motion.button
      ref={ref}
      type={type}
      whileTap={disabled || loading ? undefined : { scale: 0.97 }}
      className={cn(
        'relative inline-flex shrink-0 select-none items-center justify-center whitespace-nowrap font-semibold transition-[background,filter,border-color,color] duration-150 disabled:opacity-50',
        variants[variant],
        sizes[size],
        block && 'w-full',
        className,
      )}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <LoaderCircle size={iconSize} className="spin" aria-hidden /> : Icon ? <Icon size={iconSize} aria-hidden /> : null}
      {children != null && <span className="truncate">{children}</span>}
    </motion.button>
  );
});

export interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  icon: LucideIcon;
  /** Accessible name, also shown as a tooltip. */
  label: string;
  size?: 'sm' | 'md';
  variant?: 'ghost' | 'secondary' | 'primary';
  badge?: number;
}

export function IconButton({ icon: Icon, label, size = 'md', variant = 'ghost', badge, className, type = 'button', ...rest }: IconButtonProps) {
  const box = size === 'sm' ? 'h-8 w-8 rounded-lg' : 'h-10 w-10 rounded-xl';
  const style =
    variant === 'primary'
      ? 'brand-fill shadow-glow'
      : variant === 'secondary'
        ? 'bg-panel-2 border border-line-strong text-ink hover:bg-panel-3'
        : 'text-muted hover:text-ink hover:bg-panel-2';
  return (
    <button type={type} aria-label={label} title={label} className={cn('relative inline-flex shrink-0 items-center justify-center transition-colors duration-150 disabled:opacity-40', box, style, className)} {...rest}>
      <Icon size={size === 'sm' ? 16 : 19} aria-hidden />
      {badge != null && badge > 0 && (
        <span className="absolute -right-1 -top-1 grid h-[18px] min-w-[18px] place-items-center rounded-full bg-brand px-1 text-[10px] font-bold text-white ring-2 ring-bg">{badge > 99 ? '99+' : badge}</span>
      )}
    </button>
  );
}
