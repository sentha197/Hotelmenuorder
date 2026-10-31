import { useTheme } from '../theme';

const base = import.meta.env.BASE_URL;

/**
 * Symbol and "DineQR" lettering side by side (the brand's lockup art): the
 * white art on dark surfaces, the colour art on light ones. Without
 * [onDark] it follows the page's theme.
 */
export function Lockup({ height = 30, onDark }: { height?: number; onDark?: boolean }) {
  const { theme } = useTheme();
  const white = onDark ?? theme === 'dark';
  return (
    <img
      src={`${base}brand/${white ? 'dineqr_lockup_horizontal_white.png' : 'dineqr_lockup_horizontal.png'}`}
      alt="DineQR"
      height={height}
      style={{ height, width: 'auto', maxWidth: '100%' }}
      draggable={false}
    />
  );
}

/** The chef's-hat symbol on its own. */
export function Mark({ size = 96, onDark = false }: { size?: number; onDark?: boolean }) {
  return (
    <img
      src={`${base}brand/${onDark ? 'dineqr_symbol_white.png' : 'dineqr_symbol_color.png'}`}
      alt=""
      width={size}
      style={{ width: size, height: 'auto' }}
      draggable={false}
    />
  );
}

/** "Dine" in charcoal, "QR" in the layered red-orange gradient. */
export function Wordmark({ size = 38 }: { size?: number }) {
  return (
    <span className="wordmark" style={{ fontSize: size }} aria-label="DineQR">
      <span aria-hidden>Dine</span>
      <span className="wordmark__qr" aria-hidden>
        QR
      </span>
    </span>
  );
}

export function Tagline() {
  return (
    <span className="tagline" aria-label="Scan, order, enjoy">
      SCAN <i>•</i> ORDER <i>•</i> ENJOY
    </span>
  );
}
