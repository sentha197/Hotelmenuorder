/** Joins class names, skipping falsy ones. */
export function cn(...parts: (string | false | null | undefined)[]): string {
  return parts.filter(Boolean).join(' ');
}

/** Semantic tones for badges, chips and accents (CSS variables of the theme). */
export type Tone = 'brand' | 'ember' | 'success' | 'warning' | 'info' | 'danger' | 'muted';

export const toneVar: Record<Tone, string> = {
  brand: 'var(--brand-text)',
  ember: 'var(--ember-text)',
  success: 'var(--success)',
  warning: 'var(--warning)',
  info: 'var(--info)',
  danger: 'var(--danger)',
  muted: 'var(--muted)',
};

export const toneStyle = (tone: Tone) => ({ '--tone': toneVar[tone] }) as React.CSSProperties;

/**
 * How many cards of a list play their entrance animation: about a screenful.
 * Cards further down appear in place (they are off screen as the list opens),
 * so a long list opens without hundreds of animations at once.
 */
export const ANIMATED_ENTRIES = 12;
