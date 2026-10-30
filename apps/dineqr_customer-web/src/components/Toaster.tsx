import { CheckCircle2, CircleAlert, Info } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useLocation } from 'react-router';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize } from './sizes';

/** Snackbar messages, above the bottom bar of the screen they appear on. */
export function Toaster() {
  const { toasts } = useApp();
  const toast = useStore(toasts).current;
  const { pathname } = useLocation();
  const raised = /^\/(home|menu|cart|orders|more)$/.test(pathname) || /\/(pay|split|dish|summary)/.test(pathname) || pathname.startsWith('/bills');
  return (
    <div className="toast-region" style={{ '--toast-offset': raised ? '96px' : '16px' } as React.CSSProperties} role="status" aria-live="polite">
      <AnimatePresence>
        {toast && (
          <motion.div
            key={toast.id}
            className={`toast toast--${toast.tone}`}
            initial={{ opacity: 0, y: 24, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 12, transition: { duration: 0.15 } }}
            transition={{ type: 'spring', stiffness: 420, damping: 32 }}
          >
            {toast.tone === 'success' ? <CheckCircle2 size={iconSize.lg} /> : toast.tone === 'error' ? <CircleAlert size={iconSize.lg} /> : <Info size={iconSize.lg} />}
            <span className="toast__text">{toast.message}</span>
            {toast.actionLabel && (
              <button
                type="button"
                className="toast__action"
                onClick={() => {
                  toasts.dismiss(toast.id);
                  toast.onAction?.();
                }}
              >
                {toast.actionLabel}
              </button>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
