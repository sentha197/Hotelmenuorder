import { useId } from 'react';
import { useTheme } from '@/theme/theme';

const base = import.meta.env.BASE_URL;

/**
 * The DineQR symbol, drawn from the same geometry as the Flutter design
 * system (`DineQrMarkPainter`, a 240 × 196 design space): the chef's hat,
 * the fork and spoon, the four QR modules and the smile. [tone] `inverted`
 * is the white mark for the dark navigation frame. An empty [label] hides it
 * from screen readers.
 */
export function DineQrMark({ size = 48, tone = 'color', label = 'DineQR Admin' }: { size?: number; tone?: 'color' | 'inverted'; label?: string }) {
  const id = useId().replace(/:/g, '');
  const ref = (name: string) => `url(#${name}-${id})`;
  const color = tone === 'color';
  const depth = color ? '#6E0A10' : 'rgba(58,5,8,0.55)';
  return (
    <svg width={size} height={(size * 196) / 240} viewBox="-4 -4 250 206" {...(label ? { role: 'img', 'aria-label': label } : { 'aria-hidden': true })}>
      <defs>
        <linearGradient id={`ribbon-${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={color ? '#D62828' : '#fff'} />
          <stop offset="0.5" stopColor={color ? '#B5121B' : '#fff'} />
          <stop offset="1" stopColor={color ? '#8E0F17' : '#fff'} />
        </linearGradient>
        <linearGradient id={`lobe-${id}`} x1="0" y1="0.5" x2="1" y2="1">
          <stop offset="0" stopColor={color ? '#D62828' : '#fff'} />
          <stop offset="0.55" stopColor={color ? '#FF6A00' : '#fff'} />
          <stop offset="1" stopColor={color ? '#FF8A00' : '#FFE9DC'} />
        </linearGradient>
        <linearGradient id={`swoosh-${id}`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor={color ? '#8E0F17' : '#fff'} />
          <stop offset="0.3" stopColor={color ? '#B5121B' : '#fff'} />
          <stop offset="0.75" stopColor={color ? '#FF6A00' : '#fff'} />
          <stop offset="1" stopColor={color ? '#FF8A00' : '#FFC796'} />
        </linearGradient>
        <linearGradient id={`cutlery-${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color ? '#D62828' : '#fff'} />
          <stop offset="0.5" stopColor={color ? '#B5121B' : '#fff'} />
          <stop offset="1" stopColor={color ? '#8E0F17' : '#fff'} />
        </linearGradient>
        <linearGradient id={`module-${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={color ? '#FF6A00' : '#FF8A00'} />
          <stop offset="1" stopColor={color ? '#D62828' : '#FF6A00'} />
        </linearGradient>
        <mask id={`ribbon-mask-${id}`} maskUnits="userSpaceOnUse" x="-20" y="-20" width="300" height="260">
          <g fill="#fff">
            <circle cx="41" cy="76.5" r="39.8" />
            <circle cx="112.4" cy="62.7" r="60.5" />
            <path d={LEG_OUTER} />
          </g>
          <g fill="#000">
            <circle cx="50.6" cy="81.3" r="26.8" />
            <circle cx="114.6" cy="71.3" r="48.4" />
            <circle cx="191.5" cy="86.5" r="25" />
            <circle cx="199" cy="80" r="43" />
            <path d={LEG_INNER} />
          </g>
        </mask>
        <clipPath id={`lobe-clip-${id}`}>
          <path d={LOBE_SECTOR} />
        </clipPath>
      </defs>
      <g transform="translate(1.6 2.2)">
        <rect width="240" height="196" fill={depth} mask={ref('ribbon-mask')} />
        <path d={LOBE_RING} fill={depth} fillRule="evenodd" clipPath={ref('lobe-clip')} />
      </g>
      <rect width="240" height="196" fill={ref('ribbon')} mask={ref('ribbon-mask')} />
      <path d={LOBE_RING} fill={ref('lobe')} fillRule="evenodd" clipPath={ref('lobe-clip')} />
      <path d={FORK} fill={depth} transform="translate(1.6 2.2)" />
      <path d={SPOON} fill={depth} transform="translate(1.6 2.2)" />
      <path d={FORK} fill={ref('cutlery')} />
      <path d={SPOON} fill={ref('cutlery')} />
      {MODULES.map((d, i) => (
        <g key={i}>
          <path d={d} fill={depth} fillRule="evenodd" transform="translate(1.6 2.2)" />
          <path d={d} fillRule="evenodd" fill={i === 3 ? (color ? '#8E0F17' : '#fff') : ref('module')} />
        </g>
      ))}
      <path d={SWOOSH} fill={depth} transform="translate(1.6 2.2)" />
      <path d={SWOOSH} fill={ref('swoosh')} />
      <g transform="translate(206 144)">
        <circle r="9" fill={color ? '#FFC83D' : '#FF8A00'} opacity="0.35" />
        <path d={STAR} fill={color ? '#FF8A00' : '#fff'} />
      </g>
    </svg>
  );
}

/** The lockup art's transparent margins, as fractions of its height. */
const lockupMargin = { top: 0.19, right: 0.65, bottom: 0.21, left: 0.63 };

/**
 * Symbol and "DineQR" lettering (the brand's lockup art), white on the dark
 * theme and in colour on the light one; [onDark] keeps it white on a surface
 * that is always dark, [onLight] in colour on paper.
 */
export function Lockup({ height = 30, onDark = false, onLight = false, trim = false }: { height?: number; onDark?: boolean; onLight?: boolean; trim?: boolean }) {
  const { theme } = useTheme();
  const white = onDark || (!onLight && theme === 'dark');
  const margin = trim ? [lockupMargin.top, lockupMargin.right, lockupMargin.bottom, lockupMargin.left].map((f) => `${-f * height}px`).join(' ') : undefined;
  return (
    <img
      src={`${base}brand/${white ? 'dineqr_lockup_horizontal_white.png' : 'dineqr_lockup_horizontal.png'}`}
      alt="DineQR"
      height={height}
      style={{ height, width: 'auto', maxWidth: '100%', objectFit: 'contain', margin }}
      draggable={false}
    />
  );
}

// ------------------------------------------------------------- geometry

const LEG_OUTER = 'M1.5 78Q4 131 46 156L66 156L66 70Z';
const LEG_INNER = 'M58 92L150 92L150 58L260 58L260 216L58 216Z';

const circle = (cx: number, cy: number, r: number) => `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0Z`;

/** Right lobe: a ring with an off-centre hole (thicker on one side). */
const LOBE_RING = `${circle(199, 80, 39.5)}${circle(191.5, 86.5, 25)}`;

/** The 278° sector from 200° that keeps the ring open towards the hat. */
const LOBE_SECTOR = (() => {
  const r = 49.5;
  const a = (200 * Math.PI) / 180;
  const b = ((200 + 278) * Math.PI) / 180;
  const point = (t: number) => `${(199 + r * Math.cos(t)).toFixed(2)} ${(80 + r * Math.sin(t)).toFixed(2)}`;
  return `M199 80L${point(a)}A${r} ${r} 0 1 1 ${point(b)}Z`;
})();

const rrect = (x: number, y: number, w: number, h: number, r: number) =>
  `M${x + r} ${y}H${x + w - r}A${r} ${r} 0 0 1 ${x + w} ${y + r}V${y + h - r}A${r} ${r} 0 0 1 ${x + w - r} ${y + h}H${x + r}A${r} ${r} 0 0 1 ${x} ${y + h - r}V${y + r}A${r} ${r} 0 0 1 ${x + r} ${y}Z`;

const FORK = (() => {
  const tine = 4.6;
  const gap = 2.53;
  const tines = [0, 1, 2, 3].map((i) => rrect(64 + i * (tine + gap), 67, tine, 32, tine / 2)).join('');
  const neck = 'M64 94L90 94L90 98Q90 107.5 81.5 110.5L81.5 156A4.5 4.5 0 0 1 72.5 156L72.5 110.5Q64 107.5 64 98Z';
  return tines + neck;
})();

const SPOON =
  'M158.5 68C168.5 68 174.5 80 174.5 92C174.5 106 166.5 117 158.5 117C150.5 117 142.5 106 142.5 92C142.5 80 148.5 68 158.5 68Z' +
  'M154.2 110L162.8 110L162.8 156A4.3 4.3 0 0 1 154.2 156Z';

/** Three finder rings and one solid block, as in the app icon. */
const MODULES = (() => {
  const size = 19;
  const gap = 4;
  const left = 95.5;
  const top = 116.5;
  const ring = (x: number, y: number) => rrect(x, y, size, size, 4.8) + rrect(x + 5.2, y + 5.2, size - 10.4, size - 10.4, 2);
  const solid = (x: number, y: number) => rrect(x, y, size, size, 4.8) + rrect(x + 7, y + 7, size - 14, size - 14, 1.5);
  const x2 = left + size + gap;
  const y2 = top + size + gap;
  return [ring(left, top), ring(x2, top), ring(left, y2), solid(x2, y2)];
})();

const SWOOSH = 'M44 149Q110 226 206 144Q120 184 58 146Z';

/** A four-point sparkle centred on the smile's tip. */
const STAR = 'M0 -8L1.6 -1.6L8 0L1.6 1.6L0 8L-1.6 1.6L-8 0L-1.6 -1.6Z';
