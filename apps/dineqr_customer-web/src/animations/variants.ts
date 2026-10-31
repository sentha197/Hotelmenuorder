import type { Variants } from 'motion/react';
import { durations, ease, staggerDelay, transitions } from './transitions';

/** Fade in while sliding up a little; [custom] is the item index. */
export const fadeSlideIn: Variants = {
  hidden: { opacity: 0, y: 14 },
  shown: (index: number = 0) => ({
    opacity: 1,
    y: 0,
    transition: { ...transitions.brand, delay: staggerDelay(index) },
  }),
};

/**
 * The entrance with reduced motion: the same fade and stagger, nothing
 * offset (MotionConfig alone would still draw the first frame displaced).
 */
export const fadeInStill: Variants = {
  hidden: { opacity: 0 },
  shown: (index: number = 0) => ({
    opacity: 1,
    transition: { ...transitions.brand, delay: staggerDelay(index) },
  }),
};

/** Same, sideways, for horizontal carousels. */
export const fadeSlideInX: Variants = {
  hidden: { opacity: 0, x: 24 },
  shown: (index: number = 0) => ({
    opacity: 1,
    x: 0,
    transition: { ...transitions.brand, delay: staggerDelay(index) },
  }),
};

/** Whole pages: a short fade and lift; leaving is quicker than arriving. */
export const page: Variants = {
  hidden: { opacity: 0, y: 10 },
  shown: { opacity: 1, y: 0, transition: { duration: durations.medium, ease: ease.brand } },
  exit: { opacity: 0, transition: { duration: durations.fast, ease: ease.exit } },
};

export const sheet: Variants = {
  hidden: { y: '100%' },
  shown: { y: 0, transition: transitions.sheet },
  exit: { y: '100%', transition: { duration: durations.medium, ease: ease.exit } },
};

export const fade: Variants = {
  hidden: { opacity: 0 },
  shown: { opacity: 1, transition: transitions.medium },
  exit: { opacity: 0, transition: transitions.fast },
};

export const pop: Variants = {
  hidden: { opacity: 0, scale: 0.6 },
  shown: { opacity: 1, scale: 1, transition: transitions.spring },
  exit: { opacity: 0, scale: 0.6, transition: transitions.fast },
};

export const dialog: Variants = {
  hidden: { opacity: 0, scale: 0.94 },
  shown: { opacity: 1, scale: 1, transition: transitions.softSpring },
  exit: { opacity: 0, scale: 0.96, transition: transitions.fast },
};

/** Expanding panels (option details, search field). */
export const collapse: Variants = {
  hidden: { opacity: 0, height: 0 },
  shown: { opacity: 1, height: 'auto', transition: transitions.medium },
  exit: { opacity: 0, height: 0, transition: transitions.fast },
};

/** Press feedback for tappable cards and buttons. */
export const tap = { scale: 0.97 } as const;
export const tapSmall = { scale: 0.9 } as const;
