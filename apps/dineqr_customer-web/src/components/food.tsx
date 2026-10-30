import { UtensilsCrossed } from 'lucide-react';
import { useState, type CSSProperties, type ReactNode } from 'react';
import { imageUrl } from '../config';
import { iconSize } from './sizes';

/**
 * A dish or category photo: fades in once loaded, lazy below the fold, and
 * falls back to a plain mark when the picture cannot be loaded.
 */
export function FoodImage({
  src,
  width,
  height,
  radius = 0,
  alt = '',
  eager = false,
  className = '',
  style,
}: {
  src: string;
  width?: number | string;
  height?: number | string;
  radius?: number | string;
  alt?: string;
  eager?: boolean;
  className?: string;
  style?: CSSProperties;
}) {
  const [state, setState] = useState<'loading' | 'loaded' | 'failed'>(src ? 'loading' : 'failed');
  const url = imageUrl(src);
  return (
    <div
      className={`food-img ${className}`}
      style={{ width, height, '--radius': typeof radius === 'number' ? `${radius}px` : radius, ...style } as CSSProperties}
    >
      {state !== 'failed' && (
        <img
          key={url}
          src={url}
          alt={alt}
          loading={eager ? 'eager' : 'lazy'}
          decoding="async"
          draggable={false}
          className={state === 'loaded' ? 'is-loaded' : ''}
          onLoad={() => setState('loaded')}
          onError={() => setState('failed')}
        />
      )}
      {state === 'failed' && (
        <div className="food-img__fallback" aria-hidden>
          <UtensilsCrossed size={iconSize.lg} />
        </div>
      )}
    </div>
  );
}

/** Greys a sold-out dish's photo and labels it. */
export function SoldOutVeil({ soldOut, radius = 0, children }: { soldOut: boolean; radius?: number; children: ReactNode }) {
  return (
    <div className={`sold-out ${soldOut ? 'sold-out--on' : ''}`} style={{ '--radius': `${radius}px` } as CSSProperties}>
      {children}
      {soldOut && (
        <div className="sold-out__veil">
          <span>Sold out</span>
        </div>
      )}
    </div>
  );
}
