import { CircleAlert, CircleCheck, Info, X } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useSyncExternalStore } from 'react';
import { createPortal } from 'react-dom';
import { cn } from './cn';

type ToastKind = 'success' | 'error' | 'info';

interface ToastItem {
  id: number;
  kind: ToastKind;
  message: string;
  action?: { label: string; onClick: () => void };
}

let items: ToastItem[] = [];
let nextId = 1;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

export function dismissToast(id: number) {
  items = items.filter((t) => t.id !== id);
  emit();
}

/** Shows a short message (showAppSnackBar), newest at the bottom; three at most. */
export function toast(message: string, kind: ToastKind = 'info', action?: ToastItem['action']) {
  const id = nextId++;
  items = [...items.slice(-2), { id, kind, message, action }];
  emit();
  setTimeout(() => dismissToast(id), action ? 7000 : kind === 'error' ? 6000 : 4000);
  return id;
}

const icons = { success: CircleCheck, error: CircleAlert, info: Info };
const tones = { success: 'text-success', error: 'text-danger', info: 'text-info' };

export function Toaster() {
  const shown = useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => items,
  );
  return createPortal(
    <div className="pointer-events-none fixed inset-x-0 bottom-[calc(76px+env(safe-area-inset-bottom))] z-[60] flex flex-col items-center gap-2 px-4 md:bottom-6 md:items-end md:px-6" aria-live="polite" role="status">
      <AnimatePresence initial={false}>
        {shown.map((t) => {
          const Icon = icons[t.kind];
          return (
            <motion.div
              key={t.id}
              layout
              initial={{ opacity: 0, y: 16, scale: 0.97 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.97 }}
              transition={{ type: 'spring', stiffness: 460, damping: 34 }}
              className="panel-solid pointer-events-auto flex w-full max-w-md items-center gap-3 rounded-2xl px-4 py-3"
            >
              <Icon size={19} className={cn('shrink-0', tones[t.kind])} aria-hidden />
              <p className="min-w-0 flex-1 text-[13px] leading-snug text-ink">{t.message}</p>
              {t.action && (
                <button
                  type="button"
                  className="shrink-0 rounded-lg px-2 py-1 text-[12px] font-bold uppercase tracking-wide text-brand-text hover:bg-panel-2"
                  onClick={() => {
                    t.action!.onClick();
                    dismissToast(t.id);
                  }}
                >
                  {t.action.label}
                </button>
              )}
              <button type="button" aria-label="Dismiss" onClick={() => dismissToast(t.id)} className="grid h-7 w-7 shrink-0 place-items-center rounded-lg text-faint hover:bg-panel-2 hover:text-ink">
                <X size={15} aria-hidden />
              </button>
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>,
    document.body,
  );
}
