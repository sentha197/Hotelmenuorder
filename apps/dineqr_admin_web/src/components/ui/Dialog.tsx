import { X, type LucideIcon } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useId, useRef, useState, useSyncExternalStore, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Button } from './Button';
import { cn } from './cn';
import { TextField } from './Form';

/**
 * A modal dialog: centred on wide screens, a bottom sheet on phones. Escape
 * and the backdrop close it; focus moves into it and back when it closes.
 */
export function Dialog({
  open,
  onClose,
  title,
  description,
  icon: Icon,
  children,
  footer,
  size = 'md',
  dismissible = true,
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  description?: ReactNode;
  icon?: LucideIcon;
  children?: ReactNode;
  footer?: ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl';
  dismissible?: boolean;
}) {
  const titleId = useId();
  const panel = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const previous = document.activeElement as HTMLElement | null;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && dismissible) onClose();
      if (e.key === 'Tab' && panel.current) {
        const focusable = panel.current.querySelectorAll<HTMLElement>('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])');
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        if (!first || !last) return;
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener('keydown', onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const timer = setTimeout(() => {
      const target = panel.current?.querySelector<HTMLElement>('[data-autofocus], input:not([type=hidden]):not([disabled]), textarea, select') ?? panel.current;
      target?.focus();
    }, 40);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = overflow;
      previous?.focus?.();
    };
  }, [open, onClose, dismissible]);

  const width = { sm: 'sm:max-w-md', md: 'sm:max-w-lg', lg: 'sm:max-w-2xl', xl: 'sm:max-w-4xl' }[size];
  return createPortal(
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-6">
          <motion.div
            className="absolute inset-0 bg-[var(--overlay)] backdrop-blur-[6px]"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.18 }}
            onClick={dismissible ? onClose : undefined}
            aria-hidden
          />
          <motion.div
            ref={panel}
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            tabIndex={-1}
            initial={{ opacity: 0, y: 28, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 18, scale: 0.98 }}
            transition={{ type: 'spring', stiffness: 420, damping: 36 }}
            className={cn('panel-solid relative flex max-h-[92dvh] w-full flex-col overflow-hidden rounded-b-none outline-none sm:rounded-b-[var(--radius-card)]', width)}
          >
            <div className="mx-auto mt-2.5 h-1 w-10 rounded-full bg-line-strong sm:hidden" aria-hidden />
            <header className="flex items-start gap-3 px-5 pb-2 pt-4 sm:px-6 sm:pt-6">
              {Icon && (
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-brand/12 text-brand-text">
                  <Icon size={20} aria-hidden />
                </span>
              )}
              <div className="min-w-0 flex-1 pt-0.5">
                <h2 id={titleId} className="text-[16.5px] font-semibold leading-snug text-ink">
                  {title}
                </h2>
                {description && <div className="mt-1 text-[13px] leading-relaxed text-muted">{description}</div>}
              </div>
              {dismissible && (
                <button type="button" onClick={onClose} aria-label="Close" className="-mr-1.5 grid h-8 w-8 shrink-0 place-items-center rounded-lg text-muted hover:bg-panel-2 hover:text-ink">
                  <X size={18} aria-hidden />
                </button>
              )}
            </header>
            {children != null && <div className="min-h-0 flex-1 overflow-y-auto px-5 py-3 sm:px-6">{children}</div>}
            {footer && <footer className="flex flex-wrap items-center justify-end gap-2 border-t border-line px-5 py-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:px-6">{footer}</footer>}
          </motion.div>
        </div>
      )}
    </AnimatePresence>,
    document.body,
  );
}

// ------------------------------------------------- imperative confirm/prompt

interface ConfirmRequest {
  kind: 'confirm';
  title: string;
  message: ReactNode;
  confirmLabel: string;
  icon?: LucideIcon;
  danger?: boolean;
  resolve: (ok: boolean) => void;
}

interface PromptRequest {
  kind: 'prompt';
  title: string;
  label: string;
  message?: ReactNode;
  confirmLabel: string;
  minLength: number;
  maxLength: number;
  type?: 'text' | 'password';
  resolve: (value: string | null) => void;
}

type Request = ConfirmRequest | PromptRequest;

let current: Request | null = null;
const listeners = new Set<() => void>();
const publish = (next: Request | null) => {
  current = next;
  listeners.forEach((l) => l());
};

/** Asks a yes/no question (showConfirmDialog). */
export function confirmDialog(options: { title: string; message: ReactNode; confirmLabel: string; icon?: LucideIcon; danger?: boolean }): Promise<boolean> {
  return new Promise((resolve) => publish({ kind: 'confirm', ...options, resolve }));
}

/** Asks for a short text, e.g. a cancellation reason (askForText). */
export function promptDialog(options: { title: string; label: string; message?: ReactNode; confirmLabel?: string; minLength?: number; maxLength?: number; type?: 'text' | 'password' }): Promise<string | null> {
  return new Promise((resolve) =>
    publish({ kind: 'prompt', confirmLabel: 'Confirm', minLength: 3, maxLength: 120, ...options, resolve }),
  );
}

/** Renders the confirm/prompt dialogs; mounted once at the root. */
export function DialogHost() {
  const request = useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => current,
  );
  const [text, setText] = useState('');
  const [shown, setShown] = useState<Request | null>(null);

  useEffect(() => {
    if (request) {
      setShown(request);
      setText('');
    }
  }, [request]);

  const close = (result: boolean | string | null) => {
    if (!request) return;
    if (request.kind === 'confirm') request.resolve(result === true);
    else request.resolve(typeof result === 'string' ? result : null);
    publish(null);
  };

  const r = request ?? shown;
  if (!r) return null;
  if (r.kind === 'confirm') {
    return (
      <Dialog
        open={request != null}
        onClose={() => close(false)}
        title={r.title}
        icon={r.icon}
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => close(false)}>
              Back
            </Button>
            <Button variant={r.danger ? 'danger' : 'primary'} onClick={() => close(true)} data-autofocus>
              {r.confirmLabel}
            </Button>
          </>
        }
      >
        <div className="pb-2 text-[13.5px] leading-relaxed text-muted">{r.message}</div>
      </Dialog>
    );
  }
  const valid = text.trim().length >= r.minLength;
  return (
    <Dialog
      open={request != null}
      onClose={() => close(null)}
      title={r.title}
      size="sm"
      footer={
        <>
          <Button variant="ghost" onClick={() => close(null)}>
            Back
          </Button>
          <Button variant="primary" disabled={!valid} onClick={() => close(text.trim())}>
            {r.confirmLabel}
          </Button>
        </>
      }
    >
      <form
        className="flex flex-col gap-3 pb-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (valid) close(text.trim());
        }}
      >
        {r.message && <div className="text-[13px] leading-relaxed text-muted">{r.message}</div>}
        <TextField label={r.label} value={text} onChange={(e) => setText(e.target.value)} maxLength={r.maxLength} showCount type={r.type ?? 'text'} autoComplete={r.type === 'password' ? 'new-password' : 'off'} />
      </form>
    </Dialog>
  );
}
