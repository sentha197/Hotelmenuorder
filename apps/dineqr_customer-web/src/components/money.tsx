import { animate, useReducedMotion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { Currency, type Paise } from '../core/money';

/**
 * An amount that counts to its new value. While counting it shows whole
 * rupees so decimals don't flicker; screen readers only hear the final value.
 */
export function AnimatedMoney({ value, className }: { value: Paise; className?: string }) {
  const reduced = useReducedMotion();
  const [shown, setShown] = useState(value);
  const previous = useRef(value);

  useEffect(() => {
    const from = previous.current;
    previous.current = value;
    if (reduced || from === value) {
      setShown(value);
      return;
    }
    const controls = animate(from, value, {
      duration: 0.32,
      ease: [0.2, 0, 0, 1],
      onUpdate: (latest) => setShown(Math.round(latest / 100) * 100),
      onComplete: () => setShown(value),
    });
    return () => controls.stop();
  }, [value, reduced]);

  return (
    <span className={`tabular ${className ?? ''}`} aria-label={Currency.format(value)}>
      <span aria-hidden>{Currency.format(shown === value ? value : shown)}</span>
    </span>
  );
}
