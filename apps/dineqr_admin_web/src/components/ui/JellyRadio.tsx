import { useAnimate, useReducedMotion } from 'motion/react';
import {
  useEffect,
  useLayoutEffect,
  useRef,
  type CSSProperties,
  type KeyboardEvent,
  type ReactNode,
} from 'react';
import './JellyRadio.css';

// The same component lives in the admin and customer web apps
// (src/components/ui/JellyRadio.tsx and src/components/JellyRadio.tsx):
// change both together.

export type JellyRadioItem<T> = {
  value: T;
  /** The label; a function gets whether this item is the checked one. */
  label: ReactNode | ((checked: boolean) => ReactNode);
  icon?: ReactNode;
  disabled?: boolean;
  /** Accessible name when the label alone is not enough. */
  ariaLabel?: string;
  /** Extra class on this chip (e.g. its own --jr-* colours). */
  className?: string;
};

export type JellyRadioProps<T> = {
  items: readonly JellyRadioItem<T>[];
  /** Always controlled: the checked value. */
  value: T;
  onChange: (value: T) => void;
  ariaLabel: string;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
  /**
   * Overrides for the size: chip height, font size, side padding (px).
   * Left unset, the size (or the page's own --jr-* values) decides.
   */
  height?: number;
  fontSize?: number;
  paddingX?: number;
  /** Space between chips (px; 6 by default). */
  gap?: number;
  /** Any CSS background (gradients work: the CSS uses `background`). */
  chipColor?: string;
  activeColor?: string;
  textColor?: string;
  activeTextColor?: string;
  /** Corner radius (px; a pill by default). */
  radius?: number;
  /** How far the chosen chip swells (0.12 = 12%). */
  swell?: number;
  /** How far neighbours are pushed aside (px). */
  barge?: number;
  /** How far the other chips shrink back (0.03 = 3%). */
  shrink?: number;
  /** Wobble after the swell (0 = none, 1 = full). */
  jelly?: number;
  /** Overshoot as pushed chips come back (0-1). */
  bounce?: number;
  /** Delay per chip as the push travels outward (ms). */
  stagger?: number;
  /** Spring stiffness: higher is quicker. */
  stiffness?: number;
};

/**
 * A row of single-select chips (a radio group) whose chosen chip swells with
 * a jelly wobble and nudges its neighbours aside. Arrow keys, Home and End
 * move the choice. With reduced motion nothing moves; only colours change.
 * If it sits in a horizontal scroller, a newly chosen chip is scrolled into
 * view.
 */
export function JellyRadio<T>({
  items,
  value,
  onChange,
  ariaLabel,
  className = '',
  size = 'md',
  height,
  fontSize,
  paddingX,
  gap,
  chipColor,
  activeColor,
  textColor,
  activeTextColor,
  radius,
  swell = 0.12,
  barge = 4,
  shrink = 0.03,
  jelly = 1,
  bounce = 0.25,
  stagger = 22,
  stiffness = 580,
}: JellyRadioProps<T>) {
  const [scope, animate] = useAnimate<HTMLDivElement>();
  const reduced = useReducedMotion();
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);
  const checkedIndex = items.findIndex((i) => Object.is(i.value, value));
  const previous = useRef(checkedIndex);

  // Play the jelly when the checked chip changes (not on first render).
  useLayoutEffect(() => {
    const from = previous.current;
    const to = checkedIndex;
    previous.current = to;
    if (from === to || to < 0) return;
    scrollIntoView(buttons.current[to]);
    if (reduced) return;
    // A spring's settle time, roughly, for this stiffness.
    const duration = Math.min(Math.max(14 / Math.sqrt(stiffness), 0.32), 1.1);
    const wobble = jelly;
    buttons.current.forEach((button, i) => {
      if (!button) return;
      const skin = button.querySelector<HTMLElement>('.jelly-radio__skin');
      const distance = Math.abs(i - to);
      const delay = (distance * stagger) / 1000;
      if (i === to && skin) {
        void animate(
          skin,
          {
            scaleX: [1, 1 + swell, 1 - swell * 0.45 * wobble, 1 + swell * 0.2 * wobble, 1],
            scaleY: [1, 1 - swell * 0.55, 1 + swell * 0.35 * wobble, 1 - swell * 0.12 * wobble, 1],
          },
          { duration, ease: 'easeOut', times: [0, 0.22, 0.5, 0.75, 1] },
        );
        return;
      }
      // Neighbours: pushed away from the chosen chip, less the further they are.
      if (distance <= 3 && barge > 0) {
        const push = (Math.sign(i - to) * barge) / distance;
        // Plain transform keyframes: motion's `x` shorthand left these chips
        // unpainted in Chrome while it ran.
        void animate(
          button,
          { transform: [0, push, -push * bounce, 0].map((px) => `translateX(${px}px)`) },
          { duration: duration * 0.9, delay, ease: 'easeOut', times: [0, 0.25, 0.6, 1] },
        );
      }
      if (skin && shrink > 0) {
        const dip = i === from ? shrink * 2 : shrink;
        void animate(skin, { scale: [1, 1 - dip, 1] }, { duration: duration * 0.7, delay, ease: 'easeOut' });
      }
    });
  }, [checkedIndex]);

  // Keep the refs array the length of the items.
  useEffect(() => {
    buttons.current.length = items.length;
  }, [items.length]);

  const enabled = (i: number) => !items[i]?.disabled;
  const move = (from: number, step: 1 | -1) => {
    for (let n = 1; n <= items.length; n++) {
      const i = (((from + step * n) % items.length) + items.length) % items.length;
      if (enabled(i)) return i;
    }
    return from;
  };
  const choose = (i: number) => {
    const item = items[i];
    if (!item || item.disabled) return;
    buttons.current[i]?.focus();
    if (!Object.is(item.value, value)) onChange(item.value);
  };
  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    const at = buttons.current.findIndex((b) => b === document.activeElement);
    const from = at >= 0 ? at : Math.max(checkedIndex, 0);
    let next: number | null = null;
    if (e.key === 'ArrowRight' || e.key === 'ArrowDown') next = move(from, 1);
    else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = move(from, -1);
    else if (e.key === 'Home') next = move(-1, 1);
    else if (e.key === 'End') next = move(items.length, -1);
    if (next == null) return;
    e.preventDefault();
    choose(next);
  };

  // Only what was passed goes inline, so a page's CSS can set the rest.
  const vars: Record<string, string | number> = {};
  if (height != null) vars['--jr-height'] = `${height}px`;
  if (fontSize != null) vars['--jr-font-size'] = `${fontSize}px`;
  if (paddingX != null) vars['--jr-padding-x'] = `${paddingX}px`;
  if (gap != null) vars['--jr-gap'] = `${gap}px`;
  if (radius != null) vars['--jr-radius'] = `${radius}px`;
  if (chipColor) vars['--jr-chip'] = chipColor;
  if (activeColor) vars['--jr-active'] = activeColor;
  if (textColor) vars['--jr-text'] = textColor;
  if (activeTextColor) vars['--jr-active-text'] = activeTextColor;

  // The only tab stop is the checked chip (or the first enabled one).
  const tabStop = checkedIndex >= 0 && enabled(checkedIndex) ? checkedIndex : items.findIndex((i) => !i.disabled);
  return (
    <div
      ref={scope}
      role="radiogroup"
      aria-label={ariaLabel}
      className={`jelly-radio jelly-radio--${size} ${className}`.trim()}
      style={vars as CSSProperties}
      onKeyDown={onKeyDown}
    >
      {items.map((item, i) => {
        const checked = i === checkedIndex;
        return (
          <button
            key={`${String(item.value)}-${i}`}
            ref={(el) => {
              buttons.current[i] = el;
            }}
            type="button"
            role="radio"
            aria-checked={checked}
            aria-label={item.ariaLabel}
            disabled={item.disabled}
            tabIndex={i === tabStop ? 0 : -1}
            className={item.className ? `jelly-radio__item ${item.className}` : 'jelly-radio__item'}
            onClick={() => choose(i)}
          >
            <span className="jelly-radio__skin" aria-hidden>
              <span className="jelly-radio__fill" />
            </span>
            <span className="jelly-radio__label">
              {item.icon}
              {typeof item.label === 'function' ? item.label(checked) : item.label}
            </span>
          </button>
        );
      })}
    </div>
  );
}

/** Scrolls [el] into view inside its nearest horizontal scroller only. */
function scrollIntoView(el: HTMLElement | null | undefined) {
  if (!el) return;
  let box = el.parentElement;
  while (box && box !== document.body) {
    const overflow = getComputedStyle(box).overflowX;
    if ((overflow === 'auto' || overflow === 'scroll') && box.scrollWidth > box.clientWidth) break;
    box = box.parentElement;
  }
  if (!box || box === document.body) return;
  const outer = box.getBoundingClientRect();
  const inner = el.getBoundingClientRect();
  const margin = 16;
  let delta = 0;
  if (inner.left < outer.left + margin) delta = inner.left - outer.left - margin;
  else if (inner.right > outer.right - margin) delta = inner.right - outer.right + margin;
  if (delta !== 0) box.scrollBy({ left: delta, behavior: 'smooth' });
}
