import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useEffect, useId, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { dialog as dialogVariants, fade, sheet as sheetVariants } from '../animations/variants';
import { Button } from './ui';

/**
 * Keeps keyboard focus inside an open sheet or dialog, closes on Escape and
 * gives focus back to what opened it.
 */
function useModal(open: boolean, onClose: () => void) {
  const ref = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    if (!open) return;
    const opener = document.activeElement as HTMLElement | null;
    const node = ref.current;
    const focusables = () =>
      node ? [...node.querySelectorAll<HTMLElement>('button, [href], input, textarea, select, [tabindex]:not([tabindex="-1"])')].filter((el) => !el.hasAttribute('disabled')) : [];
    requestAnimationFrame(() => (focusables()[0] ?? node)?.focus({ preventScroll: true }));
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        close.current();
      } else if (event.key === 'Tab') {
        const list = focusables();
        if (!list.length) return;
        const first = list[0]!;
        const last = list[list.length - 1]!;
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener('keydown', onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = overflow;
      opener?.focus?.({ preventScroll: true });
    };
  }, [open]);
  return ref;
}

/** A bottom sheet on phones, a centred panel on wide screens. */
export function Sheet({
  open,
  onClose,
  title,
  children,
  dismissible = true,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  /** False while a request runs, so the result is never hidden. */
  dismissible?: boolean;
}) {
  const reduced = useReducedMotion();
  const titleId = useId();
  const ref = useModal(open, () => dismissible && onClose());
  return createPortal(
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            key="overlay"
            className="overlay"
            variants={fade}
            initial="hidden"
            animate="shown"
            exit="exit"
            onClick={() => dismissible && onClose()}
          />
          <motion.div
            key="sheet"
            ref={ref}
            className="sheet"
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            tabIndex={-1}
            variants={reduced ? fade : sheetVariants}
            initial="hidden"
            animate="shown"
            exit="exit"
            drag={dismissible && !reduced ? 'y' : false}
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.6 }}
            onDragEnd={(_, info) => {
              if (info.offset.y > 120 || info.velocity.y > 600) onClose();
            }}
          >
            <div className="sheet__handle" aria-hidden />
            <h2 id={titleId} className="visually-hidden">
              {title}
            </h2>
            <div className="sheet__body">{children}</div>
          </motion.div>
        </>
      )}
    </AnimatePresence>,
    document.body,
  );
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  icon,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  icon?: ReactNode;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const ref = useModal(open, onCancel);
  const titleId = useId();
  return createPortal(
    <AnimatePresence>
      {open && (
        <>
          <motion.div key="overlay" className="overlay" variants={fade} initial="hidden" animate="shown" exit="exit" onClick={onCancel} />
          <motion.div
            key="dialog"
            ref={ref}
            className="dialog"
            role="alertdialog"
            aria-modal="true"
            aria-labelledby={titleId}
            variants={dialogVariants}
            initial="hidden"
            animate="shown"
            exit="exit"
          >
            {icon && <div className="empty__icon dialog__icon">{icon}</div>}
            <h2 id={titleId} className="t-section">
              {title}
            </h2>
            <p className="t-secondary" style={{ marginTop: 6 }}>
              {message}
            </p>
            <div className="stack-sm" style={{ marginTop: 20 }}>
              <Button block onClick={onConfirm}>
                {confirmLabel}
              </Button>
              <Button variant="ghost" muted block onClick={onCancel}>
                Cancel
              </Button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>,
    document.body,
  );
}
