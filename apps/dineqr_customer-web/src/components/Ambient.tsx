import { useMemo } from 'react';
import { useLocation } from 'react-router';
import { paths } from '../routes/paths';

/** A fixed seed, so the field is the same on every visit (and in tests). */
function sparks(count: number, blur: number, minAlpha: number, maxAlpha: number, seed: number) {
  let state = seed;
  const random = () => {
    state = (state * 9301 + 49297) % 233280;
    return state / 233280;
  };
  return Array.from({ length: count }, () => {
    const warm = Math.round(200 + random() * 40);
    const alpha = (minAlpha + random() * (maxAlpha - minAlpha)).toFixed(2);
    return `${(random() * 100).toFixed(2)}vw ${(random() * 100).toFixed(2)}vh ${blur}px 0 rgb(255 ${warm} ${warm - 20} / ${alpha})`;
  }).join(',');
}

/**
 * The stage's faint sparks behind every page: two fixed 1 px layers whose
 * whole field is one box-shadow list each (a fine layer and a few soft,
 * brighter points). Drawn once; nothing animates. The brand page (/about)
 * keeps its own backdrop.
 */
export function Ambient() {
  const { pathname } = useLocation();
  const layers = useMemo(() => [sparks(130, 0, 0.05, 0.26, 11), sparks(16, 1.2, 0.3, 0.62, 29)], []);
  if (pathname === paths.about) return null;
  return (
    <div className="ambient" aria-hidden>
      {layers.map((shadow, i) => (
        <span key={i} className="ambient__sparks" style={{ boxShadow: shadow }} />
      ))}
    </div>
  );
}
