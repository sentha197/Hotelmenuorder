import { ArrowLeft, QrCode as QrGlyph, Star } from 'lucide-react';
import { motion, useReducedMotion, type HTMLMotionProps } from 'motion/react';
import { Fragment, useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { useNavigate } from 'react-router';
import { fadeSlideIn, fadeSlideInX, tap } from '../animations/variants';
import { emblemSize, iconSize } from './sizes';

type ButtonVariant = 'primary' | 'secondary' | 'ghost';

interface ButtonProps extends Omit<HTMLMotionProps<'button'>, 'children'> {
  variant?: ButtonVariant;
  icon?: ReactNode;
  trailingIcon?: ReactNode;
  loading?: boolean;
  block?: boolean;
  compact?: boolean;
  muted?: boolean;
  success?: boolean;
  children?: ReactNode;
}

/** The app's buttons. A loading button is disabled, so it cannot submit twice. */
export function Button({
  variant = 'primary',
  icon,
  trailingIcon,
  loading = false,
  block = false,
  compact = false,
  muted = false,
  success = false,
  disabled,
  className = '',
  children,
  type = 'button',
  ...rest
}: ButtonProps) {
  const off = disabled || loading;
  const classes = [
    'btn',
    `btn--${variant}`,
    block && 'btn--block',
    compact && 'btn--compact',
    muted && 'btn--muted',
    success && 'btn--success',
    className,
  ]
    .filter(Boolean)
    .join(' ');
  return (
    <motion.button
      type={type}
      className={classes}
      disabled={off}
      aria-busy={loading || undefined}
      whileTap={off ? undefined : tap}
      {...rest}
    >
      {loading ? <QrLoader size={18} color="currentColor" label="Working" /> : icon}
      {children != null && <span className="btn__label">{children}</span>}
      {!loading && trailingIcon}
    </motion.button>
  );
}

export function IconButton({
  label,
  children,
  filled = false,
  className = '',
  ...rest
}: Omit<HTMLMotionProps<'button'>, 'children'> & { label: string; children: ReactNode; filled?: boolean }) {
  return (
    <motion.button
      type="button"
      className={`icon-btn ${filled ? 'icon-btn--filled' : ''} ${className}`}
      aria-label={label}
      title={label}
      whileTap={{ scale: 0.88 }}
      {...rest}
    >
      {children}
    </motion.button>
  );
}

/**
 * A page's header: a floating glass bar (back, actions) above the page's
 * title as a large display heading that rises in word by word. Once that
 * heading scrolls under the bar, the bar shows the title instead. Without
 * [hero] (or a title) only the bar is shown, with the title in it.
 */
export function AppBar({
  title,
  onBack,
  back = true,
  actions,
  eyebrow,
  subtitle,
  hero = true,
}: {
  title?: ReactNode;
  onBack?: () => void;
  back?: boolean;
  actions?: ReactNode;
  eyebrow?: ReactNode;
  subtitle?: ReactNode;
  hero?: boolean;
}) {
  const navigate = useNavigate();
  const heading = useRef<HTMLDivElement>(null);
  const [condensed, setCondensed] = useState(false);
  const showHero = hero && title != null && title !== '';
  useEffect(() => {
    const node = heading.current;
    if (!node || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(([entry]) => setCondensed(entry != null && !entry.isIntersecting), { rootMargin: '-76px 0px 0px 0px' });
    observer.observe(node);
    return () => observer.disconnect();
  }, [showHero]);
  const goBack = () => {
    if (onBack) onBack();
    else if (window.history.state && window.history.state.idx > 0) navigate(-1);
    else navigate('/home', { replace: true });
  };
  return (
    <>
      <header className={`app-bar ${condensed || !showHero ? 'is-condensed' : ''}`}>
        <div className="app-bar__inner">
          {back ? (
            <IconButton label="Back" className="app-bar__back" onClick={goBack}>
              <ArrowLeft size={iconSize.lg} />
            </IconButton>
          ) : (
            <span className="app-bar__spacer" />
          )}
          {showHero ? (
            <span className="app-bar__title" aria-hidden>
              {title}
            </span>
          ) : (
            <h1 className="app-bar__title">{title}</h1>
          )}
          {actions}
        </div>
      </header>
      {showHero && (
        <div className="page-hero" ref={heading}>
          {eyebrow && <Eyebrow>{eyebrow}</Eyebrow>}
          <h1 className="page-hero__title">
            <MaskedText>{title}</MaskedText>
          </h1>
          {subtitle && <p className="page-hero__subtitle">{subtitle}</p>}
        </div>
      )}
    </>
  );
}

/**
 * Display text that rises out of a mask after [delay] seconds: word by
 * word (a string), or as one line with [by] "line".
 */
export function MaskedText({ children, delay = 0, by = 'word' }: { children: ReactNode; delay?: number; by?: 'word' | 'line' }) {
  const words = typeof children === 'string' && by === 'word' ? children.split(' ') : [children];
  return (
    <>
      {words.map((word, i) => (
        <Fragment key={i}>
          <span className="masked">
            <span style={{ '--i': i, '--d0': `${delay}s` } as CSSProperties}>{word}</span>
          </span>
          {i < words.length - 1 ? ' ' : ''}
        </Fragment>
      ))}
    </>
  );
}

/** A kicker above a title: an icon tile pinned left, the label beside it. */
export function Eyebrow({ icon, children, className = '' }: { icon?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <span className={`eyebrow ${className}`}>
      <i aria-hidden>{icon ?? <QrGlyph size={iconSize.sm} />}</i>
      <b>{children}</b>
    </span>
  );
}

/** Staggered entrance; with reduced motion it is shown at once. */
export function FadeIn({
  index = 0,
  axis = 'y',
  className,
  children,
  as = 'div',
  ...rest
}: {
  index?: number;
  axis?: 'x' | 'y';
  className?: string;
  children: ReactNode;
  as?: 'div' | 'li' | 'section';
} & Omit<HTMLMotionProps<'div'>, 'children'>) {
  const reduced = useReducedMotion();
  const Component = as === 'li' ? motion.li : as === 'section' ? motion.section : motion.div;
  return (
    <Component
      className={className}
      variants={axis === 'x' ? fadeSlideInX : fadeSlideIn}
      initial={reduced ? false : 'hidden'}
      animate="shown"
      custom={index}
      {...(rest as object)}
    >
      {children}
    </Component>
  );
}

export function Card({ children, className = '', soft = false, tight = false, ...rest }: React.HTMLAttributes<HTMLDivElement> & { soft?: boolean; tight?: boolean }) {
  return (
    <div className={`card ${soft ? 'card--soft' : ''} ${tight ? 'card--tight' : ''} ${className}`} {...rest}>
      {children}
    </div>
  );
}

/** Red brand surface with the faint logo watermark. */
export function BrandPanel({
  children,
  className = '',
  watermark = true,
  banner = false,
  lifted = false,
  padded = true,
}: {
  children: ReactNode;
  className?: string;
  watermark?: boolean;
  banner?: boolean;
  lifted?: boolean;
  padded?: boolean;
}) {
  return (
    <div
      className={`brand-panel ${banner ? 'brand-panel--banner' : ''} ${lifted ? 'brand-panel--lifted' : ''} ${padded ? 'brand-panel--padded' : ''} ${className}`}
    >
      {watermark && <img className="brand-panel__watermark" src={`${import.meta.env.BASE_URL}brand/dineqr_symbol_white.png`} alt="" />}
      {children}
    </div>
  );
}

export function DemoTag({ label = 'DEMO', dark = false }: { label?: string; dark?: boolean }) {
  return <span className={`demo-tag ${dark ? 'demo-tag--dark' : ''}`}>{label}</span>;
}

export function VegIndicator({ veg, size = 12 }: { veg: boolean; size?: number }) {
  return (
    <span
      className={`veg ${veg ? 'veg--yes' : 'veg--no'}`}
      style={{ '--veg-size': `${size}px` } as React.CSSProperties}
      role="img"
      aria-label={veg ? 'Vegetarian' : 'Non-vegetarian'}
    />
  );
}

export function RatingBadge({ rating, reviews, size = 12 }: { rating: number; reviews?: number; size?: number }) {
  return (
    <span className="rating" style={{ '--rating-size': `${size}px` } as React.CSSProperties} aria-label={`Rated ${rating.toFixed(1)}${reviews ? ` from ${reviews} reviews` : ''}`}>
      <Star size={size} aria-hidden />
      {rating.toFixed(1)}
      {reviews != null && reviews > 0 && <span className="rating__count">({reviews})</span>}
    </span>
  );
}

export function StarRow({ rating, size = iconSize.sm }: { rating: number; size?: number }) {
  return (
    <span className="row" style={{ gap: 2 }} role="img" aria-label={`${rating} out of 5 stars`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <Star key={n} size={size} color={n <= rating ? '#FFC83D' : 'var(--inactive)'} fill={n <= rating ? '#FFC83D' : 'var(--inactive)'} aria-hidden />
      ))}
    </span>
  );
}

export type Tone = 'info' | 'success' | 'warning' | 'error' | 'primary' | 'plain';

export function Notice({ icon, tone = 'info', children, live = false }: { icon?: ReactNode; tone?: Tone; children: ReactNode; live?: boolean }) {
  return (
    <div className={`notice ${tone === 'plain' ? 'notice--plain' : `tone-${tone}`}`} role={live ? (tone === 'error' ? 'alert' : 'status') : undefined}>
      {icon}
      <div className="grow">{children}</div>
    </div>
  );
}

export function Fact({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="fact">
      <span className="fact__label">{label}</span>
      <span className="fact__value">{value}</span>
    </div>
  );
}

export function EmptyState({
  icon,
  title,
  message,
  action,
}: {
  icon: ReactNode;
  title: string;
  message?: string;
  action?: ReactNode;
}) {
  return (
    <FadeIn className="empty">
      {/* The icon inside a scan window: four corners and a sweeping beam. */}
      <div className="empty__art" aria-hidden>
        <span className="empty__corners" />
        <span className="empty__beam" />
        <div className="empty__icon">{icon}</div>
      </div>
      <h2 className="empty__title">{title}</h2>
      {message && <p className="empty__message">{message}</p>}
      {action && <div style={{ marginTop: 12 }}>{action}</div>}
    </FadeIn>
  );
}

export function Skeleton({ width, height, radius = 8, circle = false }: { width?: number | string; height: number | string; radius?: number; circle?: boolean }) {
  return (
    <div
      className="skeleton"
      aria-hidden
      style={{ width: width ?? '100%', height, '--r': circle ? '50%' : `${radius}px` } as React.CSSProperties}
    />
  );
}

/** The brand's loader: four QR modules pulsing in turn. */
export function QrLoader({ size = 30, color, label = 'Loading' }: { size?: number; color?: string; label?: string }) {
  return (
    <span
      className="qr-loader"
      role="status"
      aria-label={label}
      style={{ '--size': `${size}px`, ...(color ? { '--loader-color': color } : {}) } as React.CSSProperties}
    >
      <span />
      <span />
      <span />
      <span />
    </span>
  );
}

export function IconHalo({ children, size = emblemSize.md }: { children: ReactNode; size?: number }) {
  return (
    <div className="halo" style={{ '--size': `${size}px` } as React.CSSProperties} aria-hidden>
      {children}
    </div>
  );
}

/**
 * A check that springs in while an orbit ring draws around it, then a ring
 * burst and a scatter of sparks; only shown for confirmed results.
 */
export function SuccessEmblem({ size = emblemSize.md, green = false, label, delay = 0 }: { size?: number; green?: boolean; label: string; delay?: number }) {
  const reduced = useReducedMotion();
  return (
    <div className={`success-emblem ${green ? 'success-emblem--green' : ''}`} style={{ '--size': `${size}px` } as React.CSSProperties} role="img" aria-label={label}>
      <svg className="success-emblem__orbit" viewBox="0 0 100 100" aria-hidden>
        <motion.circle
          cx={50}
          cy={50}
          r={48}
          initial={reduced ? false : { pathLength: 0, opacity: 0 }}
          animate={{ pathLength: 1, opacity: 1 }}
          transition={{ duration: 0.9, delay: delay + 0.05, ease: [0.65, 0, 0.35, 1] }}
        />
      </svg>
      {!reduced && (
        <>
          <motion.span
            className="success-emblem__ring"
            initial={{ scale: 0.8, opacity: 0.9 }}
            animate={{ scale: 1.7, opacity: 0 }}
            transition={{ duration: 0.9, delay: delay + 0.35, ease: 'easeOut' }}
          />
          <span className="success-emblem__sparks" style={{ '--d': `${delay + 0.4}s` } as CSSProperties} aria-hidden>
            {Array.from({ length: 8 }, (_, i) => (
              <i key={i} style={{ '--a': `${i * 45}deg` } as CSSProperties} />
            ))}
          </span>
        </>
      )}
      <motion.div
        className="success-emblem__disc"
        initial={reduced ? false : { scale: 0.3, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ type: 'spring', stiffness: 340, damping: 18, delay }}
      >
        <svg width={size * 0.46} height={size * 0.46} viewBox="0 0 24 24" fill="none" aria-hidden>
          <motion.path
            d="M5 12.5l4.5 4.5L19 7.5"
            stroke="currentColor"
            strokeWidth={2.8}
            strokeLinecap="round"
            strokeLinejoin="round"
            initial={reduced ? false : { pathLength: 0 }}
            animate={{ pathLength: 1 }}
            transition={{ duration: 0.45, delay: delay + 0.25, ease: 'easeOut' }}
          />
        </svg>
      </motion.div>
    </div>
  );
}

const confettiColors = ['#D62828', '#FF6A00', '#FF8A00', '#FFC83D', '#B5121B', '#39B060'];

/** Falling paper pieces, generated once per [seed]; none with reduced motion. */
export function Confetti({ seed = 7, count = 26 }: { seed?: number; count?: number }) {
  const reduced = useReducedMotion();
  const pieces = useMemo(() => {
    let state = seed;
    const random = () => {
      state = (state * 9301 + 49297) % 233280;
      return state / 233280;
    };
    return Array.from({ length: count }, (_, i) => ({
      left: `${random() * 100}%`,
      x: `${(random() - 0.5) * 120}px`,
      r: `${(random() - 0.5) * 900}deg`,
      d: `${1.8 + random() * 1.4}s`,
      delay: `${random() * 0.5}s`,
      color: confettiColors[i % confettiColors.length],
    }));
  }, [seed, count]);
  if (reduced) return null;
  return (
    <div className="confetti" aria-hidden>
      {pieces.map((p, i) => (
        <i
          key={i}
          style={{ left: p.left, background: p.color, '--x': p.x, '--r': p.r, '--d': p.d, '--delay': p.delay } as React.CSSProperties}
        />
      ))}
    </div>
  );
}
