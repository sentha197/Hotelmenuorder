import { Check, Search, X } from 'lucide-react';
import { motion } from 'motion/react';
import { forwardRef, useId, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from 'react';
import { cn } from './cn';

/** Label, control, then a hint or an error under it. */
export function Field({
  label,
  hint,
  error,
  htmlFor,
  counter,
  children,
  className,
}: {
  label?: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  htmlFor?: string;
  counter?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex min-w-0 flex-col gap-1.5', className)}>
      {label && (
        <label htmlFor={htmlFor} className="text-[12.5px] font-medium text-muted">
          {label}
        </label>
      )}
      {children}
      {(error || hint || counter) && (
        <div className="flex items-start justify-between gap-3">
          {error ? (
            <p role="alert" className="text-[12px] leading-snug text-danger">
              {error}
            </p>
          ) : (
            <p className="text-[12px] leading-snug text-faint">{hint}</p>
          )}
          {counter && <span className="shrink-0 text-[11px] tabular text-faint">{counter}</span>}
        </div>
      )}
    </div>
  );
}

interface InputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'prefix'> {
  label?: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  prefix?: ReactNode;
  suffix?: ReactNode;
  /** Shows `used / max` under the field. */
  showCount?: boolean;
  wrapperClassName?: string;
}

/** A labelled text field with an optional prefix (₹) or suffix (%, min). */
export const TextField = forwardRef<HTMLInputElement, InputProps>(function TextField(
  { label, hint, error, prefix, suffix, showCount, wrapperClassName, id, className, maxLength, value, ...rest },
  ref,
) {
  const auto = useId();
  const inputId = id ?? auto;
  const count = showCount && maxLength ? `${String(value ?? '').length}/${maxLength}` : undefined;
  return (
    <Field label={label} hint={hint} error={error} htmlFor={inputId} counter={count} className={wrapperClassName}>
      <div className="relative flex items-center">
        {prefix && <span className="pointer-events-none absolute left-3.5 text-[13px] font-medium text-muted">{prefix}</span>}
        <input
          ref={ref}
          id={inputId}
          value={value}
          maxLength={maxLength}
          aria-invalid={error ? true : undefined}
          className={cn('field', prefix ? 'pl-8' : undefined, suffix ? 'pr-12' : undefined, className)}
          {...rest}
        />
        {suffix && <span className="pointer-events-none absolute right-3.5 text-[12.5px] font-medium text-muted">{suffix}</span>}
      </div>
    </Field>
  );
});

interface AreaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  showCount?: boolean;
}

export const TextArea = forwardRef<HTMLTextAreaElement, AreaProps>(function TextArea({ label, hint, error, showCount, id, className, maxLength, value, rows = 3, ...rest }, ref) {
  const auto = useId();
  const inputId = id ?? auto;
  const count = showCount && maxLength ? `${String(value ?? '').length}/${maxLength}` : undefined;
  return (
    <Field label={label} hint={hint} error={error} htmlFor={inputId} counter={count}>
      <textarea ref={ref} id={inputId} rows={rows} value={value} maxLength={maxLength} aria-invalid={error ? true : undefined} className={cn('field resize-y leading-relaxed', className)} {...rest} />
    </Field>
  );
});

interface SelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  children: ReactNode;
}

export const Select = forwardRef<HTMLSelectElement, SelectProps>(function Select({ label, hint, error, id, className, children, ...rest }, ref) {
  const auto = useId();
  const inputId = id ?? auto;
  return (
    <Field label={label} hint={hint} error={error} htmlFor={inputId}>
      <select ref={ref} id={inputId} aria-invalid={error ? true : undefined} className={cn('field', className)} {...rest}>
        {children}
      </select>
    </Field>
  );
});

/** An on/off switch with a title and description (SwitchListTile). */
export function SwitchRow({
  checked,
  onChange,
  title,
  description,
  disabled,
  tone = 'brand',
}: {
  checked: boolean;
  onChange: (on: boolean) => void;
  title: ReactNode;
  description?: ReactNode;
  disabled?: boolean;
  tone?: 'brand' | 'success';
}) {
  const id = useId();
  return (
    <div className={cn('flex items-start gap-4 py-2.5', disabled && 'opacity-55')}>
      <div className="min-w-0 flex-1">
        <label htmlFor={id} className="block cursor-pointer text-[13.5px] font-semibold text-ink">
          {title}
        </label>
        {description && <p className="mt-0.5 text-[12.5px] leading-snug text-muted">{description}</p>}
      </div>
      <Switch id={id} checked={checked} onChange={onChange} disabled={disabled} tone={tone} label={typeof title === 'string' ? title : undefined} />
    </div>
  );
}

export function Switch({ checked, onChange, disabled, id, label, tone = 'brand' }: { checked: boolean; onChange: (on: boolean) => void; disabled?: boolean; id?: string; label?: string; tone?: 'brand' | 'success' }) {
  return (
    <button
      id={id}
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        'relative inline-flex h-[26px] w-[46px] shrink-0 items-center rounded-full border p-[3px] transition-colors duration-200',
        checked ? (tone === 'success' ? 'border-success/40 bg-success' : 'border-transparent brand-fill') : 'border-line-strong bg-panel-3',
      )}
    >
      <motion.span layout transition={{ type: 'spring', stiffness: 600, damping: 34 }} className={cn('block h-[18px] w-[18px] rounded-full bg-white shadow-md', checked ? 'ml-auto' : 'ml-0')} />
    </button>
  );
}

export function Checkbox({ checked, onChange, label, description, disabled }: { checked: boolean; onChange: (on: boolean) => void; label: ReactNode; description?: ReactNode; disabled?: boolean }) {
  const id = useId();
  return (
    <div className={cn('flex items-start gap-3 py-2', disabled && 'opacity-55')}>
      <button
        id={id}
        type="button"
        role="checkbox"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cn('mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-md border transition-colors', checked ? 'border-transparent brand-fill' : 'border-line-strong bg-panel-2')}
      >
        {checked && <Check size={14} strokeWidth={3} className="text-white" aria-hidden />}
      </button>
      <label htmlFor={id} className="min-w-0 flex-1 cursor-pointer">
        <span className="block text-[13.5px] font-semibold text-ink">{label}</span>
        {description && <span className="mt-0.5 block text-[12.5px] leading-snug text-muted">{description}</span>}
      </label>
    </div>
  );
}

/** A segmented control with a sliding indicator. */
export function Segmented<T extends string | number | boolean>({
  options,
  value,
  onChange,
  name,
  className,
}: {
  options: { value: T; label: ReactNode; icon?: ReactNode; disabled?: boolean }[];
  value: T;
  onChange: (value: T) => void;
  name: string;
  className?: string;
}) {
  return (
    <div role="radiogroup" className={cn('inline-flex max-w-full rounded-2xl border border-line bg-panel-2 p-1', className)}>
      {options.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={String(o.value)}
            type="button"
            role="radio"
            aria-checked={active}
            disabled={o.disabled}
            onClick={() => onChange(o.value)}
            className={cn('relative flex min-w-0 flex-1 items-center justify-center gap-2 rounded-xl px-3.5 py-2 text-[13px] font-semibold transition-colors disabled:opacity-40', active ? 'text-white' : 'text-muted hover:text-ink')}
          >
            {active && <motion.span layoutId={`seg-${name}`} className="absolute inset-0 rounded-xl brand-fill shadow-glow" transition={{ type: 'spring', stiffness: 500, damping: 38 }} />}
            <span className="relative flex min-w-0 items-center gap-2">
              {o.icon}
              <span className="truncate">{o.label}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}

/** A search box with a clear button. */
export function SearchField({ value, onChange, placeholder, className }: { value: string; onChange: (value: string) => void; placeholder: string; className?: string }) {
  return (
    <div className={cn('relative', className)}>
      <Search size={17} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-faint" aria-hidden />
      <input type="search" value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} aria-label={placeholder} className="field h-11 pl-10 pr-10 [&::-webkit-search-cancel-button]:hidden" />
      {value && (
        <button type="button" aria-label="Clear" onClick={() => onChange('')} className="absolute right-2 top-1/2 grid h-7 w-7 -translate-y-1/2 place-items-center rounded-lg text-muted hover:bg-panel-3 hover:text-ink">
          <X size={15} aria-hidden />
        </button>
      )}
    </div>
  );
}

/** One row of filter chips with counts and a sliding highlight (FilterChipBar). */
export function FilterChips<T>({
  values,
  selected,
  labelOf,
  countOf,
  onSelect,
  name,
}: {
  values: readonly T[];
  selected: T;
  labelOf: (value: T) => string;
  countOf?: (value: T) => number;
  onSelect: (value: T) => void;
  name: string;
}) {
  return (
    <div className="no-scrollbar -mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0" role="tablist" aria-label={name}>
      <div className="flex w-max gap-1.5 sm:w-auto sm:flex-wrap">
        {values.map((value, i) => {
          const active = value === selected;
          const count = countOf?.(value);
          return (
            <button
              key={`${String(value)}-${i}`}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => onSelect(value)}
              className={cn(
                'relative inline-flex h-9 shrink-0 items-center gap-2 rounded-full border px-3.5 text-[12.5px] font-semibold transition-colors',
                active ? 'border-transparent text-white' : 'border-line bg-panel text-muted hover:border-line-strong hover:text-ink',
              )}
            >
              {active && <motion.span layoutId={`chip-${name}`} className="absolute inset-0 rounded-full brand-fill" transition={{ type: 'spring', stiffness: 520, damping: 40 }} />}
              <span className="relative">{labelOf(value)}</span>
              {count != null && (
                <span className={cn('relative min-w-5 rounded-full px-1.5 text-center text-[11px] tabular', active ? 'bg-white/20 text-white' : 'bg-panel-3 text-muted')}>{count}</span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
