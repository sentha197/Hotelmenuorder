import { ArrowRight, ChevronLeft, ChevronRight, Pause, Play } from 'lucide-react';
import { useReducedMotion } from 'motion/react';
import { useEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type PointerEvent } from 'react';
import { useNavigate } from 'react-router';
import type { MenuItem } from '../core/menu';
import { Currency } from '../core/money';
import { paths } from '../routes/paths';
import { FoodImage } from './food';
import { iconSize } from './sizes';
import { RatingBadge, VegIndicator } from './ui';

/** A drag past this many pixels changes the slide. */
const SWIPE = 48;

type Gesture = { id: number; x: number; y: number; axis: 'x' | 'y' | null };

/**
 * The home page's featured dishes (marked "Home banner" in admin), one
 * banner at a time. A new banner cross-fades in while its plate swings in
 * from the side of travel and the copy rises line by line.
 *
 * The active dot's fill is the timer (6 s, styles in system.css): the slide
 * advances when its animation ends, so anything that pauses the animation
 * pauses the carousel — hovering it, keyboard focus inside it, a finger on
 * it, scrolling it out of view, or the pause button. With reduced motion
 * the fill does not run (no autoplay) and slides only cross-fade.
 * Swipe, the arrows, the dots and the arrow keys change slides by hand.
 */
export function FeaturedCarousel({ items }: { items: MenuItem[] }) {
  const navigate = useNavigate();
  const reduced = useReducedMotion();
  const root = useRef<HTMLElement>(null);
  const viewport = useRef<HTMLDivElement>(null);
  const gesture = useRef<Gesture | null>(null);
  const dragged = useRef(false);
  const [index, setIndex] = useState(0);
  const [direction, setDirection] = useState<1 | -1>(1);
  const [paused, setPaused] = useState(false);
  const [offscreen, setOffscreen] = useState(false);
  const [dragging, setDragging] = useState(false);
  const count = items.length;
  const current = Math.min(index, count - 1);

  useEffect(() => {
    const node = root.current;
    if (!node || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(([entry]) => setOffscreen(entry ? !entry.isIntersecting : false), { threshold: 0.3 });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  if (count === 0) return null;

  const go = (next: number, dir: 1 | -1) => {
    setDirection(dir);
    setIndex(((next % count) + count) % count);
  };
  const step = (dir: 1 | -1) => go(current + dir, dir);

  const setDrag = (px: number) => viewport.current?.style.setProperty('--drag', `${px}px`);
  const endGesture = () => {
    gesture.current = null;
    setDragging(false);
    setDrag(0);
  };
  const onPointerDown = (e: PointerEvent<HTMLDivElement>) => {
    if (count < 2 || (e.pointerType === 'mouse' && e.button !== 0)) return;
    gesture.current = { id: e.pointerId, x: e.clientX, y: e.clientY, axis: null };
    dragged.current = false;
  };
  const onPointerMove = (e: PointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (!g || g.id !== e.pointerId) return;
    const dx = e.clientX - g.x;
    const dy = e.clientY - g.y;
    if (!g.axis) {
      if (Math.hypot(dx, dy) < 8) return;
      // Mostly vertical: the page scrolls and the carousel stays out of it.
      g.axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';
      if (g.axis === 'x') {
        e.currentTarget.setPointerCapture?.(e.pointerId);
        setDragging(true);
      }
    }
    if (g.axis !== 'x') return;
    dragged.current = true;
    // Follows the finger, with resistance.
    setDrag(dx * 0.4);
  };
  const onPointerUp = (e: PointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (!g || g.id !== e.pointerId) return;
    const dx = e.clientX - g.x;
    const swiped = g.axis === 'x' && Math.abs(dx) > SWIPE;
    endGesture();
    if (swiped) step(dx < 0 ? 1 : -1);
  };
  const onKeyDown = (e: KeyboardEvent) => {
    if (count < 2) return;
    if (e.key === 'ArrowRight') step(1);
    else if (e.key === 'ArrowLeft') step(-1);
    else return;
    e.preventDefault();
  };

  const autoplay = count > 1 && !reduced;
  const holding = paused || offscreen || dragging;
  return (
    <section
      ref={root}
      className="featured"
      aria-roledescription="carousel"
      aria-label="Featured dishes"
      data-paused={holding || undefined}
      data-dragging={dragging || undefined}
      style={{ '--dir': direction } as CSSProperties}
      onKeyDown={onKeyDown}
    >
      <div
        ref={viewport}
        className="featured__viewport"
        aria-live={autoplay && !paused ? 'off' : 'polite'}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={endGesture}
        onClickCapture={(e) => {
          // The end of a swipe is not a tap on the banner.
          if (!dragged.current) return;
          dragged.current = false;
          e.preventDefault();
          e.stopPropagation();
        }}
      >
        {items.map((item, i) => {
          const active = i === current;
          return (
            <div
              key={item.id}
              className={`featured__slide ${active ? 'is-active' : ''}`}
              role="group"
              aria-roledescription="slide"
              aria-label={`${i + 1} of ${count}`}
              aria-hidden={!active}
              inert={!active}
            >
              <button type="button" className="featured__card" onClick={() => navigate(paths.dish(item.id))}>
                <span className="featured__glow" aria-hidden />
                <span className="featured__grid" aria-hidden />
                <span className="featured__copy">
                  <span className="featured__eyebrow" style={{ '--i': 0 } as CSSProperties}>
                    {item.isChefSpecial ? 'Chef’s pick' : 'Featured'}
                  </span>
                  <span className="featured__intro" style={{ '--i': 1 } as CSSProperties}>
                    Try our
                  </span>
                  <span className="featured__name" style={{ '--i': 2 } as CSSProperties}>
                    {item.name}
                  </span>
                  {item.shortDescription && (
                    <span className="featured__desc" style={{ '--i': 3 } as CSSProperties}>
                      {item.shortDescription}
                    </span>
                  )}
                  <span className="featured__meta" style={{ '--i': 4 } as CSSProperties}>
                    <VegIndicator veg={item.isVeg} size={11} />
                    <span className="featured__price">{Currency.format(item.price)}</span>
                    {item.rating > 0 && <RatingBadge rating={item.rating} size={11} />}
                  </span>
                  <span className="featured__cta" style={{ '--i': 5 } as CSSProperties}>
                    Order now <ArrowRight size={iconSize.sm} />
                  </span>
                </span>
                <span className="featured__plate" aria-hidden>
                  <span className="featured__halo" />
                  <FoodImage src={item.image} width="100%" height="100%" radius="50%" eager={i === 0} />
                </span>
              </button>
            </div>
          );
        })}
      </div>
      {count > 1 && (
        <div className="featured__controls">
          <button type="button" className="featured__arrow" aria-label="Previous dish" onClick={() => step(-1)}>
            <ChevronLeft size={iconSize.md} />
          </button>
          <div className="featured__dots" role="group" aria-label="Featured dishes">
            {items.map((item, i) => (
              <button
                key={item.id}
                type="button"
                className={`featured__dot ${i === current ? 'is-active' : ''}`}
                aria-label={`Show ${item.name}`}
                aria-current={i === current || undefined}
                onClick={() => i !== current && go(i, i > current ? 1 : -1)}
              >
                {/* The timer: a new fill per slide, so each one starts from empty. */}
                {i === current && autoplay && <span key={current} className="featured__fill" onAnimationEnd={() => step(1)} />}
              </button>
            ))}
          </div>
          <button type="button" className="featured__arrow" aria-label="Next dish" onClick={() => step(1)}>
            <ChevronRight size={iconSize.md} />
          </button>
          {autoplay && (
            <button
              type="button"
              className="featured__pause"
              aria-label={paused ? 'Play featured dishes' : 'Pause featured dishes'}
              aria-pressed={paused}
              onClick={() => setPaused(!paused)}
            >
              {paused ? <Play size={iconSize.xs} /> : <Pause size={iconSize.xs} />}
            </button>
          )}
        </div>
      )}
    </section>
  );
}
