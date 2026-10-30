import { useReducedMotion } from 'motion/react';
import { useId } from 'react';

/**
 * The DineQR symbol, drawn from the same geometry as the Flutter design
 * system (`DineQrMarkPainter`, a 240 × 196 design space): the ribbon and
 * right lobe of the chef's hat, the fork and spoon, the four QR modules and
 * the smile. Each part sits on a darker copy shifted down-right, as in the
 * app. With [draw], the mark is drawn in: the hat sweeps in clockwise, the
 * cutlery outlines draw and rise, the modules pop one by one, the smile is
 * traced and fills, then the mark glows once and the smile's tip glints.
 * An empty [label] hides it from screen readers (decorative use).
 */
export function DineQrMark({
  size = 120,
  draw = false,
  tone = 'color',
  label = 'DineQR',
}: {
  size?: number;
  draw?: boolean;
  tone?: 'color' | 'inverted';
  label?: string;
}) {
  const id = useId().replace(/:/g, '');
  const ref = (name: string) => `url(#${name}-${id})`;
  const color = tone === 'color';
  const depth = color ? '#6E0A10' : 'rgba(58,5,8,0.55)';
  // With reduced motion the finished mark is shown at once.
  const reduced = useReducedMotion();
  if (reduced) draw = false;
  const parts = draw ? 'mark mark--draw' : 'mark';
  return (
    <svg
      className={parts}
      width={size}
      height={(size * 196) / 240}
      viewBox="-4 -4 250 206"
      {...(label ? { role: 'img', 'aria-label': label } : { 'aria-hidden': true })}
    >
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
        {/* The ribbon: outer lobes and leg, minus everything inside the hat. */}
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
        {/* The drawing sweep: a pie growing clockwise from the bottom-left. */}
        <mask id={`sweep-${id}`} maskUnits="userSpaceOnUse" x="-20" y="-20" width="300" height="260">
          <circle className="mark__sweep" cx="118" cy="104" r="100" fill="none" stroke="#fff" strokeWidth="200" pathLength={1} transform="rotate(125 118 104)" />
        </mask>
      </defs>

      <g className="mark__hat" mask={draw ? ref('sweep') : undefined}>
        <g transform="translate(1.6 2.2)">
          <rect width="240" height="196" fill={depth} mask={ref('ribbon-mask')} />
          <path d={LOBE_RING} fill={depth} fillRule="evenodd" clipPath={ref('lobe-clip')} />
        </g>
        <rect width="240" height="196" fill={ref('ribbon')} mask={ref('ribbon-mask')} />
        <path d={LOBE_RING} fill={ref('lobe')} fillRule="evenodd" clipPath={ref('lobe-clip')} />
      </g>

      <g className="mark__cutlery">
        <path d={FORK} fill={depth} transform="translate(1.6 2.2)" />
        <path d={SPOON} fill={depth} transform="translate(1.6 2.2)" />
        <path className="mark__fill" d={FORK} fill={ref('cutlery')} />
        <path className="mark__fill" d={SPOON} fill={ref('cutlery')} />
        <path className="mark__pen" d={FORK} pathLength={1} />
        <path className="mark__pen" d={SPOON} pathLength={1} />
      </g>

      {MODULES.map((d, i) => (
        <g key={i} className="mark__module" style={{ '--i': i } as React.CSSProperties}>
          <path d={d} fill={depth} fillRule="evenodd" transform="translate(1.6 2.2)" />
          <path d={d} fillRule="evenodd" fill={i === 3 ? (color ? '#8E0F17' : '#fff') : ref('module')} />
        </g>
      ))}

      <g className="mark__smile">
        <path d={SWOOSH} fill={depth} transform="translate(1.6 2.2)" className="mark__fill" />
        <path className="mark__fill" d={SWOOSH} fill={ref('swoosh')} />
        <path className="mark__pen mark__pen--smile" d={SWOOSH} pathLength={1} />
        <g transform="translate(206 144)">
          <g className="mark__glint">
            <circle r="9" fill={color ? '#FFC83D' : '#FF8A00'} opacity="0.35" />
            <path d={STAR} fill={color ? '#FF8A00' : '#fff'} />
          </g>
        </g>
      </g>
    </svg>
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
