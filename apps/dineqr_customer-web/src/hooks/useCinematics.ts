import { useEffect, type RefObject } from 'react';

const reducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

/** Parallax layers never drift further than this, so they stay inside their clipped panels. */
const MAX_DRIFT = 32;
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

/**
 * Scroll-driven effects for a long page, with one IntersectionObserver and
 * one requestAnimationFrame-throttled scroll handler:
 *
 * - `[data-reveal]` gets `data-in` once it enters the viewport (entrances,
 *   staggered by `--d` in CSS);
 * - `[data-live]` gets `data-visible` while on screen, so looping animations
 *   pause off screen;
 * - `[data-parallax="0.12"]` drifts against the scroll by that factor;
 * - `[data-words]` sets `--p` (0–1) on itself and `data-lit` on each
 *   `.word` child as the section scrolls through the viewport.
 *
 * Scrolling is never intercepted. With reduced motion everything is shown
 * at once and nothing moves.
 */
export function useCinematics(root: RefObject<HTMLElement | null>) {
  useEffect(() => {
    const node = root.current;
    if (!node) return;
    const reduced = reducedMotion();
    const reveals = node.querySelectorAll<HTMLElement>('[data-reveal]');
    const lives = node.querySelectorAll<HTMLElement>('[data-live]');
    const parallax = [...node.querySelectorAll<HTMLElement>('[data-parallax]')];
    const wordBlocks = [...node.querySelectorAll<HTMLElement>('[data-words]')].map((block) => ({
      block,
      words: [...block.querySelectorAll<HTMLElement>('.word')],
    }));

    if (reduced || typeof IntersectionObserver === 'undefined') {
      reveals.forEach((el) => el.setAttribute('data-in', ''));
      lives.forEach((el) => el.setAttribute('data-visible', ''));
      wordBlocks.forEach(({ words }) => words.forEach((w) => w.setAttribute('data-lit', '')));
      return;
    }

    const revealObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.setAttribute('data-in', '');
          revealObserver.unobserve(entry.target);
        }
      },
      { rootMargin: '0px 0px -12% 0px', threshold: 0.12 },
    );
    reveals.forEach((el) => revealObserver.observe(el));

    const liveObserver = new IntersectionObserver((entries) => {
      for (const entry of entries) entry.target.toggleAttribute('data-visible', entry.isIntersecting);
    });
    lives.forEach((el) => liveObserver.observe(el));

    let frame = 0;
    const update = () => {
      frame = 0;
      const vh = window.innerHeight;
      for (const el of parallax) {
        const rect = el.getBoundingClientRect();
        if (rect.bottom < -vh || rect.top > 2 * vh) continue;
        const factor = Number(el.dataset.parallax) || 0;
        const offset = clamp((rect.top + rect.height / 2 - vh / 2) * factor, -MAX_DRIFT, MAX_DRIFT);
        el.style.setProperty('--parallax', `${offset.toFixed(1)}px`);
      }
      for (const { block, words } of wordBlocks) {
        const rect = block.getBoundingClientRect();
        // 0 when the block's top reaches 85% of the viewport, 1 when its
        // bottom passes 55%: the words light up as they are read.
        const start = vh * 0.85;
        const end = vh * 0.55;
        const progress = Math.min(1, Math.max(0, (start - rect.top) / (rect.height + start - end)));
        block.style.setProperty('--p', progress.toFixed(3));
        const lit = Math.round(progress * words.length);
        words.forEach((w, i) => w.toggleAttribute('data-lit', i < lit));
      }
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    update();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      revealObserver.disconnect();
      liveObserver.disconnect();
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
      if (frame) cancelAnimationFrame(frame);
    };
  }, [root]);
}

/** Pointer-following 3D tilt for a card (fine pointers only, no reduced motion). */
export function tiltHandlers() {
  const enabled = () => !reducedMotion() && window.matchMedia?.('(pointer: fine)').matches;
  return {
    onPointerMove(event: React.PointerEvent<HTMLElement>) {
      if (!enabled()) return;
      const el = event.currentTarget;
      const rect = el.getBoundingClientRect();
      const x = (event.clientX - rect.left) / rect.width - 0.5;
      const y = (event.clientY - rect.top) / rect.height - 0.5;
      el.style.setProperty('--rx', `${(-y * 6).toFixed(2)}deg`);
      el.style.setProperty('--ry', `${(x * 8).toFixed(2)}deg`);
      el.style.setProperty('--mx', `${((x + 0.5) * 100).toFixed(1)}%`);
      el.style.setProperty('--my', `${((y + 0.5) * 100).toFixed(1)}%`);
    },
    onPointerLeave(event: React.PointerEvent<HTMLElement>) {
      const el = event.currentTarget;
      el.style.removeProperty('--rx');
      el.style.removeProperty('--ry');
    },
  };
}
