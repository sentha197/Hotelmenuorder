import { Minus, Plus } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useRef } from 'react';
import { iconSize } from './sizes';

/** − n + with the number rolling up or down as it changes. */
export function QuantitySelector({
  quantity,
  onIncrement,
  onDecrement,
  min = 0,
  max = 20,
  compact = false,
  itemName,
}: {
  quantity: number;
  onIncrement: () => void;
  onDecrement: () => void;
  min?: number;
  max?: number;
  compact?: boolean;
  itemName: string;
}) {
  const reduced = useReducedMotion();
  const previous = useRef(quantity);
  const direction = quantity >= previous.current ? 1 : -1;
  previous.current = quantity;
  return (
    <div className={`qty ${compact ? 'qty--compact' : ''}`} role="group" aria-label={`Quantity of ${itemName}`}>
      <motion.button
        type="button"
        className="qty__btn"
        onClick={onDecrement}
        disabled={quantity <= min}
        whileTap={{ scale: 0.8 }}
        aria-label={quantity <= 1 && min === 0 ? `Remove ${itemName}` : `Decrease ${itemName}`}
      >
        <Minus size={compact ? iconSize.sm : iconSize.md} />
      </motion.button>
      <span className="qty__value" aria-live="polite">
        <AnimatePresence initial={false} mode="popLayout" custom={direction}>
          <motion.span
            key={quantity}
            custom={direction}
            initial={reduced ? false : { y: direction * 14, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={reduced ? { opacity: 0 } : { y: direction * -14, opacity: 0 }}
            transition={{ duration: 0.18 }}
          >
            {quantity}
          </motion.span>
        </AnimatePresence>
      </span>
      <motion.button
        type="button"
        className="qty__btn"
        onClick={onIncrement}
        disabled={quantity >= max}
        whileTap={{ scale: 0.8 }}
        aria-label={`Increase ${itemName}`}
      >
        <Plus size={compact ? iconSize.sm : iconSize.md} />
      </motion.button>
    </div>
  );
}
