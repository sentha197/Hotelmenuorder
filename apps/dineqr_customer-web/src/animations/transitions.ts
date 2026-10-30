import type { Transition } from 'motion/react';

/** Durations and curves shared by every animation (Flutter's Motion). */
export const durations = { fast: 0.18, medium: 0.28, slow: 0.42 } as const;

export const ease = {
  standard: [0.2, 0, 0, 1],
  brand: [0.22, 1, 0.36, 1],
  exit: [0.4, 0, 1, 1],
} as const;

export const transitions = {
  fast: { duration: durations.fast, ease: ease.standard },
  medium: { duration: durations.medium, ease: ease.standard },
  brand: { duration: durations.slow, ease: ease.brand },
  spring: { type: 'spring', stiffness: 520, damping: 32, mass: 0.7 },
  softSpring: { type: 'spring', stiffness: 260, damping: 24 },
  sheet: { type: 'spring', stiffness: 380, damping: 36 },
} satisfies Record<string, Transition>;

/** Stagger step for list entrances, capped so long lists do not lag. */
export const staggerDelay = (index: number, step = 0.045, max = 0.32) => Math.min(index * step, max);
