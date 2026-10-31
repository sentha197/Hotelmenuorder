import { Award } from 'lucide-react';
import { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router';
import type { MenuItem } from '../core/menu';
import { Currency } from '../core/money';
import { paths } from '../routes/paths';
import { FoodImage } from './food';
import { iconSize } from './sizes';

const CARDS = 24;
/** Cards past this angle (either side of the front) are hidden. */
const CULL = 42;
/** Degrees per second. */
const SPEED = 2.4;

/**
 * The home page's centrepiece: the restaurant's dishes on a slowly turning
 * 3D ring. The camera sits at the ring's centre (perspective = radius), so
 * every card faces it and the ring curves towards the viewer at the sides.
 * Decorative: hidden from assistive tech (every dish is listed below), but
 * a click opens the dish. Turning pauses off screen, while hovered, and
 * with reduced motion (the ring is still drawn, just still). A sideways
 * drag spins it by hand, with a little momentum unless motion is reduced;
 * a vertical drag scrolls the page as usual.
 */
export function DishRing({ items }: { items: MenuItem[] }) {
  const stage = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();
  const pictured = items.filter((item) => item.image);
  const cards = pictured.length ? Array.from({ length: CARDS }, (_, i) => pictured[i % pictured.length]!) : [];

  useEffect(() => {
    const node = stage.current;
    if (!node || cards.length === 0) return;
    const els = [...node.querySelectorAll<HTMLElement>('.dish-ring__card')];
    const step = 360 / els.length;
    const cull = Math.cos((CULL * Math.PI) / 180);
    let radius = 0;
    let phase = -step / 2;
    let last = 0;
    let frame = 0;
    let onScreen = true;
    let hovered = false;
    // A drag in progress, and the spin it leaves behind (degrees per second).
    let drag = null as { id: number; x: number; y: number; axis: 'x' | 'y' | null; last: number; at: number } | null;
    let fling = 0;
    let dragged = false;
    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

    const measure = () => {
      const width = els[0]?.offsetWidth || 120;
      // Circumference for the cards plus their gaps.
      radius = (els.length * width * 1.16) / (2 * Math.PI);
      node.style.setProperty('--ring-r', `${radius.toFixed(1)}px`);
    };
    const render = () => {
      els.forEach((el, i) => {
        const a = ((((i * step + phase) % 360) + 540) % 360) - 180;
        if (Math.abs(a) > CULL) {
          el.style.visibility = 'hidden';
          return;
        }
        const r = (a * Math.PI) / 180;
        const c = Math.cos(r);
        el.style.visibility = 'visible';
        el.style.transform = `translate3d(${(radius * Math.sin(r)).toFixed(1)}px,0,${(radius * (1 - c)).toFixed(1)}px) rotateY(${(-a).toFixed(2)}deg)`;
        // The front card is brightest; the sides fall into shadow.
        el.style.filter = `brightness(${(1 - (0.5 * (1 - c)) / (1 - cull)).toFixed(3)})`;
      });
    };
    const tick = (t: number) => {
      const dt = last ? Math.min((t - last) / 1000, 0.1) : 0;
      last = t;
      if (drag?.axis === 'x') {
        // The finger moves the ring.
      } else if (Math.abs(fling) > 1) {
        phase += fling * dt;
        fling *= Math.pow(0.06, dt);
      } else if (!hovered) {
        phase -= SPEED * dt;
      }
      render();
      frame = requestAnimationFrame(tick);
    };
    const start = () => {
      if (reduced || frame || !onScreen || document.visibilityState !== 'visible') return;
      last = 0;
      frame = requestAnimationFrame(tick);
    };
    const stop = () => {
      cancelAnimationFrame(frame);
      frame = 0;
    };

    measure();
    render();
    start();
    const resize =
      typeof ResizeObserver === 'undefined'
        ? null
        : new ResizeObserver(() => {
            measure();
            render();
          });
    resize?.observe(node);
    const view =
      typeof IntersectionObserver === 'undefined'
        ? null
        : new IntersectionObserver(([entry]) => {
            onScreen = entry?.isIntersecting ?? true;
            if (onScreen) start();
            else stop();
          });
    view?.observe(node);
    const onVisibility = () => (document.visibilityState === 'visible' ? start() : stop());
    document.addEventListener('visibilitychange', onVisibility);
    const enter = (e: PointerEvent) => e.pointerType === 'mouse' && (hovered = true);
    const leave = () => (hovered = false);
    // One card width of drag turns the ring by one card.
    const degreesPerPixel = () => step / ((els[0]?.offsetWidth || 120) * 1.16);
    const down = (e: PointerEvent) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      drag = { id: e.pointerId, x: e.clientX, y: e.clientY, axis: null, last: e.clientX, at: e.timeStamp };
      dragged = false;
      fling = 0;
    };
    const move = (e: PointerEvent) => {
      if (!drag || drag.id !== e.pointerId) return;
      if (!drag.axis) {
        if (Math.hypot(e.clientX - drag.x, e.clientY - drag.y) < 6) return;
        drag.axis = Math.abs(e.clientX - drag.x) > Math.abs(e.clientY - drag.y) ? 'x' : 'y';
        if (drag.axis === 'x') {
          node.setPointerCapture?.(e.pointerId);
          node.dataset.dragging = '';
        }
      }
      if (drag.axis !== 'x') return;
      dragged = true;
      const turned = (e.clientX - drag.last) * degreesPerPixel();
      fling = (turned * 1000) / Math.max(8, e.timeStamp - drag.at);
      phase += turned;
      drag.last = e.clientX;
      drag.at = e.timeStamp;
      if (!frame) render();
    };
    const up = (e: PointerEvent) => {
      if (!drag || drag.id !== e.pointerId) return;
      const spun = drag.axis === 'x';
      drag = null;
      delete node.dataset.dragging;
      if (!spun || reduced) fling = 0;
    };
    // The end of a drag is not a tap on a card.
    const click = (e: MouseEvent) => {
      if (!dragged) return;
      dragged = false;
      e.stopPropagation();
      e.preventDefault();
    };
    node.addEventListener('pointerenter', enter);
    node.addEventListener('pointerleave', leave);
    node.addEventListener('pointerdown', down);
    node.addEventListener('pointermove', move);
    node.addEventListener('pointerup', up);
    node.addEventListener('pointercancel', up);
    node.addEventListener('click', click, true);
    return () => {
      stop();
      resize?.disconnect();
      view?.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      node.removeEventListener('pointerenter', enter);
      node.removeEventListener('pointerleave', leave);
      node.removeEventListener('pointerdown', down);
      node.removeEventListener('pointermove', move);
      node.removeEventListener('pointerup', up);
      node.removeEventListener('pointercancel', up);
      node.removeEventListener('click', click, true);
    };
  }, [cards.length]);

  if (cards.length === 0) return null;
  return (
    <div className="dish-ring" ref={stage} aria-hidden>
      <div className="dish-ring__stage">
        {cards.map((item, i) => (
          <div key={i} className="dish-ring__card" onClick={() => navigate(paths.dish(item.id))}>
            <FoodImage src={item.image} width="100%" height="100%" eager={i < 6} />
            <span className="dish-ring__shade" />
            {item.isChefSpecial && (
              <span className="dish-ring__ribbon">
                <Award size={iconSize.xs} /> Chef’s pick
              </span>
            )}
            <span className="dish-ring__name">{item.name}</span>
            <span className="dish-ring__price">{Currency.format(item.price)}</span>
            <span className="dish-ring__edge" />
          </div>
        ))}
      </div>
    </div>
  );
}
