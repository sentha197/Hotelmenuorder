import { ArrowRight, BookOpen, CircleAlert, ConciergeBell, Hand, QrCode as QrIcon, RefreshCw, ShoppingBag, UtensilsCrossed, WifiOff } from 'lucide-react';
import { animate, motion, useReducedMotion } from 'motion/react';
import { useEffect, useState } from 'react';
import { Navigate, useNavigate, useParams } from 'react-router';
import { Lockup, Wordmark } from '../components/brand';
import { Button, Confetti, FadeIn, QrLoader } from '../components/ui';
import { allowedQrOrigins, basePath } from '../config';
import { OrderTables, TAKEAWAY_TABLE } from '../core/orders';
import { parseTableQr, payloadFor, qrErrorMessage, tableOf, type QrError } from '../core/qr';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { ApiException } from '../services/api';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize, lockupHeight } from '../components/sizes';

/** How long the server may take before we say it is waking up. */
const SLOW_AFTER_MS = 8000;

/**
 * `/t/05` and `/takeaway`: where a table's QR code leads when it is scanned
 * with Google Lens or the phone camera (and where the in-app scanner goes).
 * The table is checked against the restaurant before anything is offered,
 * and the guest confirms it before the server session starts.
 */
export function TableEntryPage({ takeaway = false }: { takeaway?: boolean }) {
  const { settings, session } = useApp();
  useStore(settings);
  useStore(session);
  const params = useParams();
  const [slow, setSlow] = useState(false);

  const raw = takeaway ? null : (params.table ?? '');
  const table = takeaway ? TAKEAWAY_TABLE : /^\d{1,3}$/.test(raw ?? '') ? Number(raw) : null;

  useEffect(() => {
    if (settings.state === 'ready') return;
    settings.load().catch(() => undefined);
    const timer = setTimeout(() => setSlow(true), SLOW_AFTER_MS);
    return () => clearTimeout(timer);
  }, [settings]);

  if (table == null) return <EntryProblem error="unrecognized" />;
  if (settings.state === 'error') return <EntryOffline onRetry={() => settings.load().catch(() => undefined)} />;
  if (settings.state !== 'ready') return <EntryLoading slow={slow} takeaway={takeaway} />;

  const result = parseTableQr(payloadFor(table), {
    allowedOrigins: allowedQrOrigins(),
    basePath,
    tableExists: settings.isKnownTable,
    tableActive: settings.isOrderable,
    takeawayEnabled: settings.settings.takeawayOrdersEnabled,
  });
  if (result.kind === 'invalid') return <EntryProblem error={result.error} />;
  const resolved = tableOf(result)!;
  // Already ordering here (a refresh, or the code scanned again).
  if (session.canOrder && session.tableNumber === resolved) return <Navigate to={paths.home} replace />;
  return <Welcome table={resolved} restaurant={settings.settings.name} />;
}

function EntryLoading({ slow, takeaway }: { slow: boolean; takeaway: boolean }) {
  return (
    <div className="entry entry--center" role="status">
      <Lockup height={lockupHeight.lg} onDark />
      <QrLoader size={34} label="Opening your table" />
      <p className="t-section">{takeaway ? 'Opening takeaway…' : 'Opening your table…'}</p>
      {slow && (
        <FadeIn>
          <p className="t-secondary t-center" style={{ maxWidth: 300 }}>
            The restaurant server is taking a while. It may be waking up; this can take up to half a minute.
          </p>
        </FadeIn>
      )}
    </div>
  );
}

function EntryOffline({ onRetry }: { onRetry: () => void }) {
  const navigate = useNavigate();
  return (
    <div className="entry entry--center">
      <Lockup height={lockupHeight.lg} onDark />
      <div className="empty__icon">
        <WifiOff size={iconSize.hero} />
      </div>
      <h1 className="t-screen-title">Can’t reach the restaurant</h1>
      <p className="t-secondary t-center" style={{ maxWidth: 320 }}>
        Cannot reach the restaurant server. Check your connection and try again.
      </p>
      <div className="stack-sm" style={{ width: 'min(100%, 320px)' }}>
        <Button block icon={<RefreshCw size={iconSize.md} />} onClick={onRetry}>
          Try again
        </Button>
        <Button block variant="ghost" icon={<QrIcon size={iconSize.md} />} onClick={() => navigate(paths.scan)}>
          Scan a code instead
        </Button>
      </div>
    </div>
  );
}

function EntryProblem({ error }: { error: QrError }) {
  const navigate = useNavigate();
  const title = error === 'tableInactive' || error === 'takeawayUnavailable' ? 'Not taking orders here' : 'This code doesn’t work';
  return (
    <div className="entry entry--center">
      <Lockup height={lockupHeight.lg} onDark />
      <div className="empty__icon">
        <CircleAlert size={iconSize.hero} />
      </div>
      <h1 className="t-screen-title" data-testid="entry-error">
        {title}
      </h1>
      <p className="t-secondary t-center" style={{ maxWidth: 320 }} role="alert">
        {qrErrorMessage[error]}
      </p>
      <Button icon={<QrIcon size={iconSize.md} />} onClick={() => navigate(paths.scan, { replace: true })}>
        Scan another code
      </Button>
    </div>
  );
}

/** "Welcome to DineQR · Table 05": the guest confirms where they are ordering. */
function Welcome({ table, restaurant }: { table: number; restaurant: string }) {
  const { session, toasts } = useApp();
  const navigate = useNavigate();
  const reduced = useReducedMotion();
  const [starting, setStarting] = useState(false);
  const isTakeaway = OrderTables.isTakeaway(table);

  const start = async () => {
    if (starting) return;
    setStarting(true);
    try {
      // The server checks the table again and issues the guest session.
      await session.startSession(table);
      navigate(paths.home, { replace: true });
    } catch (error) {
      setStarting(false);
      toasts.show(error instanceof ApiException ? error.message : 'Something went wrong. Please try again.', { tone: 'error' });
    }
  };

  const steps = [
    { icon: <BookOpen size={iconSize.lg} />, label: 'Browse' },
    { icon: <Hand size={iconSize.lg} />, label: 'Order' },
    isTakeaway ? { icon: <ShoppingBag size={iconSize.lg} />, label: 'Collect' } : { icon: <ConciergeBell size={iconSize.lg} />, label: 'Enjoy' },
  ];

  return (
    <div className="entry welcome">
      <div className="welcome__wash" aria-hidden />
      <Confetti seed={3} />
      <div className="welcome__content">
        <FadeIn>
          <Lockup height={lockupHeight.md} onDark />
        </FadeIn>
        <motion.div
          className="welcome__badge"
          initial={reduced ? false : { scale: 0.6, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', stiffness: 220, damping: 12 }}
        >
          {/* An orbit with a satellite circling the table, and a scan beam across it. */}
          <span className="welcome__orbit" aria-hidden>
            <i />
          </span>
          <div className="welcome__badge-inner">
            <TableArt label={isTakeaway ? 'Takeaway' : AppFormat.table(table)} takeaway={isTakeaway} />
            <span className="welcome__beam" aria-hidden />
          </div>
        </motion.div>
        <FadeIn index={1}>
          <p className="welcome__to">Welcome to</p>
        </FadeIn>
        <FadeIn index={2}>
          <Wordmark size={36} />
        </FadeIn>
        <FadeIn index={3}>
          <span className="welcome__chip">
            {isTakeaway ? <ShoppingBag size={iconSize.md} /> : <UtensilsCrossed size={iconSize.md} />}
            {isTakeaway ? 'Takeaway order' : <CountUp to={table} />}
          </span>
        </FadeIn>
        <FadeIn index={4}>
          <p className="t-secondary t-center welcome__text">
            {isTakeaway
              ? 'You’re all set. Browse the menu, order, and collect it at the counter when it’s ready.'
              : 'You’re all set. Browse the menu and order straight from your table.'}
            {restaurant ? <span className="welcome__restaurant"> {restaurant}</span> : null}
          </p>
        </FadeIn>
        <FadeIn index={5} className="welcome__steps">
          {steps.map((step, i) => (
            <div key={step.label} className="row" style={{ gap: 0 }}>
              {i > 0 && <span className="welcome__step-line" aria-hidden />}
              <div className="welcome__step">
                <span className="welcome__step-icon">{step.icon}</span>
                <span className="t-caption">{step.label}</span>
              </div>
            </div>
          ))}
        </FadeIn>
        <FadeIn index={6} className="welcome__actions">
          <Button block loading={starting} trailingIcon={<ArrowRight size={iconSize.lg} />} onClick={start} data-testid="start-ordering">
            Start Ordering
          </Button>
          <Button variant="ghost" muted block icon={<QrIcon size={iconSize.md} />} disabled={starting} onClick={() => navigate(paths.scan, { replace: true })}>
            {isTakeaway ? 'Eating in? Scan your table QR' : 'Not your table? Scan again'}
          </Button>
        </FadeIn>
      </div>
    </div>
  );
}

/** "Table 12" with the number counting up from 00. */
function CountUp({ to }: { to: number }) {
  const reduced = useReducedMotion();
  const [value, setValue] = useState(reduced ? to : 0);
  useEffect(() => {
    if (reduced) return;
    const controls = animate(0, to, { duration: 0.9, ease: [0.33, 1, 0.68, 1], onUpdate: (v) => setValue(Math.round(v)) });
    return () => controls.stop();
  }, [to, reduced]);
  return <span className="tabular" aria-label={`Table ${AppFormat.table(to)}`}>Table {AppFormat.table(value)}</span>;
}

/** A table-tent illustration carrying the table number. */
function TableArt({ label, takeaway }: { label: string; takeaway: boolean }) {
  return (
    <svg viewBox="0 0 120 110" width="108" aria-hidden data-takeaway={takeaway}>
      <defs>
        <linearGradient id="tent" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#D62828" />
          <stop offset="0.6" stopColor="#FF6A00" />
          <stop offset="1" stopColor="#FF8A00" />
        </linearGradient>
      </defs>
      <ellipse cx="60" cy="98" rx="46" ry="7" fill="#3A0508" opacity="0.12" />
      {takeaway ? (
        <g>
          <path d="M30 40h60l-6 54H36z" fill="url(#tent)" />
          <path d="M44 40c0-12 7-20 16-20s16 8 16 20" fill="none" stroke="#8E0F17" strokeWidth="5" strokeLinecap="round" />
          <text x="60" y="76" textAnchor="middle" fontFamily="Poppins" fontWeight="700" fontSize="13" fill="#fff">
            {label}
          </text>
        </g>
      ) : (
        <g>
          <path d="M28 92 46 20h28l18 72z" fill="url(#tent)" />
          <rect x="44" y="34" width="32" height="20" rx="4" fill="#fff" opacity="0.95" />
          <text x="60" y="49" textAnchor="middle" fontFamily="Poppins" fontWeight="800" fontSize="14" fill="#B5121B">
            {label}
          </text>
          <g fill="#fff" opacity="0.9">
            <rect x="50" y="62" width="7" height="7" rx="2" />
            <rect x="63" y="62" width="7" height="7" rx="2" />
            <rect x="50" y="74" width="7" height="7" rx="2" />
            <rect x="63" y="74" width="7" height="7" rx="2" opacity="0.5" />
          </g>
        </g>
      )}
    </svg>
  );
}
