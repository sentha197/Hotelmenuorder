/**
 * The size scale's TypeScript side, for props that take pixels (lucide's
 * `size`, logos, emblems). Mirrors the tokens in styles/tokens.css; inside
 * buttons, tiles and bars the stylesheet sizes icons for each breakpoint
 * and the prop is only the starting size.
 */
export const iconSize = {
  xs: 12,
  sm: 14,
  md: 16,
  lg: 18,
  xl: 20,
  /** Empty states and result halos. */
  hero: 30,
} as const;

/** Heights of the DineQR lockup. */
export const lockupHeight = {
  sm: 22,
  md: 26,
  lg: 28,
  /** On the bill, trimmed to the art (about 24 px of logo). */
  bill: 40,
} as const;

/** Success emblems and halos on result screens. */
export const emblemSize = {
  sm: 64,
  md: 76,
  lg: 88,
} as const;
