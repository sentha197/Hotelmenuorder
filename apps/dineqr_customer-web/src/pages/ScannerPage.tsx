import { ArrowLeft, ArrowUpRight, CameraOff, CircleAlert, Flashlight, FlashlightOff, Keyboard, QrCode as QrIcon, RefreshCw, ScanLine } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { collapse, fadeSlideIn } from '../animations/variants';
import { Wordmark } from '../components/brand';
import { DineQrMark } from '../components/DineQrMark';
import { QrCode } from '../components/QrCode';
import { Sheet } from '../components/Sheet';
import { Button, DemoTag, IconButton, QrLoader, SuccessEmblem } from '../components/ui';
import { allowedQrOrigins, basePath } from '../config';
import { OrderTables, TAKEAWAY_TABLE } from '../core/orders';
import { parseTableQr, payloadFor, qrErrorMessage, tableOf, TAKEAWAY_PAYLOAD } from '../core/qr';
import { AppFormat } from '../core/time';
import { useQrScanner, type CameraIssue } from '../hooks/useQrScanner';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { emblemSize, iconSize } from '../components/sizes';

const showDemoCodes = import.meta.env.VITE_DEMO_QR_CODES === 'true';

const issueText: Record<CameraIssue, string> = {
  unsupported: 'This browser cannot use the camera here. Open your phone’s camera app or Google Lens and point it at the code: it opens this page for your table.',
  insecure: 'The camera only works on a secure (https://) page. Open your phone’s camera app or Google Lens and point it at the code instead.',
  permissionDenied: 'Camera access is off. Allow the camera for this site in your browser settings, then tap Retry. Or scan with your phone’s camera app.',
  noCamera: 'No camera was found on this device. Scan the code with your phone’s camera app or Google Lens.',
  inUse: 'The camera is busy in another app. Close it and tap Retry.',
  failed: 'The camera could not start. Tap Retry, or scan the code with your phone’s camera app.',
};

const demoCodes = [
  { title: 'Table 05', payload: payloadFor(5) },
  { title: 'Table 12', payload: payloadFor(12) },
  { title: 'Takeaway order', payload: TAKEAWAY_PAYLOAD },
  { title: 'Invalid code', subtitle: 'A website link, to see validation', payload: 'https://example.com/menu' },
  { title: 'Unknown table', payload: 'DINEQR:TABLE:99' },
];

/**
 * The first screen of a direct visit: the restaurant's QR code is scanned
 * with this page's own camera view. (A guest who scans with Google Lens or
 * the phone camera arrives on /t/NN instead and never sees this.)
 */
export function ScannerPage() {
  const { settings, session } = useApp();
  const navigate = useNavigate();
  const reduced = useReducedMotion();
  useStore(session);
  const videoRef = useRef<HTMLVideoElement>(null);
  const [detected, setDetected] = useState<number | null>(null);
  const [checking, setChecking] = useState(false);
  const [error, setError] = useState<{ message: string; count: number } | null>(null);
  const [manualOpen, setManualOpen] = useState(false);
  const [demoOpen, setDemoOpen] = useState(false);
  const lastInvalid = useRef<{ raw: string; at: number } | null>(null);
  const busy = useRef(false);
  const errorTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showError = useCallback((message: string) => {
    setError((current) => ({ message, count: (current?.count ?? 0) + 1 }));
    if (errorTimer.current) clearTimeout(errorTimer.current);
    errorTimer.current = setTimeout(() => setError(null), 4500);
    navigator.vibrate?.([30, 40, 30]);
  }, []);

  useEffect(() => () => void (errorTimer.current && clearTimeout(errorTimer.current)), []);

  /**
   * Checks a scanned (or typed) value against the restaurant's tables and,
   * when it is valid, opens that table. Returns true once it has been
   * accepted, so the camera stops reporting codes.
   */
  const handle = useCallback(
    (raw: string): boolean => {
      if (busy.current || detected != null) return false;
      // The camera keeps reporting the same wrong code: react every 3 s.
      const now = Date.now();
      if (lastInvalid.current && lastInvalid.current.raw === raw && now - lastInvalid.current.at < 3000) return false;
      busy.current = true;
      const validate = () => {
        const result = parseTableQr(raw, {
          allowedOrigins: allowedQrOrigins(),
          basePath,
          tableExists: settings.isKnownTable,
          tableActive: settings.isOrderable,
          takeawayEnabled: settings.settings.takeawayOrdersEnabled,
        });
        const table = tableOf(result);
        if (result.kind === 'invalid' || table == null) {
          lastInvalid.current = { raw, at: Date.now() };
          showError(qrErrorMessage[result.kind === 'invalid' ? result.error : 'unrecognized']);
          busy.current = false;
          return false;
        }
        setError(null);
        setDetected(table);
        navigator.vibrate?.(20);
        // The confirmation beat, then the table's own page.
        window.setTimeout(() => navigate(paths.table(table), { replace: true }), reduced ? 300 : 900);
        return true;
      };
      if (settings.state === 'ready') return validate();
      // The code is checked against the restaurant's tables: wait for them.
      setChecking(true);
      settings
        .load()
        .then(() => {
          if (validate()) scanner.markHandled();
        })
        .catch(() => {
          busy.current = false;
          showError('Cannot reach the restaurant server to check this code. Check your connection and try again.');
        })
        .finally(() => setChecking(false));
      return false;
    },
    // `scanner` is read later, inside the promise: it is declared below.
    [detected, navigate, reduced, settings, showError],
  );

  const scanner = useQrScanner(videoRef, handle, detected == null);
  const camera = scanner.state;
  const issue = camera.status === 'issue' ? camera.issue : null;
  const saved = session.tableNumber;
  const canGoBack = window.history.state?.idx > 0;
  const takeaway = detected != null && OrderTables.isTakeaway(detected);

  const submit = (raw: string) => {
    if (handle(raw)) scanner.markHandled();
  };

  return (
    <div className={`scanner ${camera.status === 'running' ? 'scanner--live' : ''}`} data-testid="scanner">
      <video ref={videoRef} className={`scanner__video ${camera.status === 'running' ? 'is-on' : ''}`} muted playsInline autoPlay aria-hidden />
      {camera.status !== 'running' && (
        <div className="scanner__backdrop" aria-hidden>
          <div className="scanner__glow" />
          <div className="scanner__grid" />
        </div>
      )}

      <div className="scanner__layout">
        <header className="scanner__header">
          <div className="scanner__bar">
            {canGoBack && (
              <IconButton label="Back" className="scanner__icon" onClick={() => navigate(-1)}>
                <ArrowLeft size={iconSize.lg} />
              </IconButton>
            )}
            <span className="scanner__brand">
              <DineQrMark size={32} draw label="" />
              <Wordmark size={17} />
            </span>
            <Link to={paths.about} className="scanner__about">
              How it works <ArrowUpRight size={iconSize.sm} aria-hidden />
            </Link>
          </div>
          <p className="scanner__eyebrow">
            <span className="scanner__dot" aria-hidden /> QR table ordering
          </p>
          <h1 className="scanner__title">
            <span className="scanner__rise">
              Scan <span className="scanner__accent">QR Code</span>
            </span>
          </h1>
          <p className="scanner__hint">Scan the restaurant QR code on your table to continue.</p>
        </header>

        <div className="scanner__frame-area">
          <motion.div
            className={`scan-frame ${camera.status === 'running' ? 'is-live' : ''} ${detected != null ? 'is-success' : ''}`}
            initial={reduced ? false : { opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.55, ease: [0.22, 1, 0.36, 1], delay: 0.1 }}
          >
            <span className="scan-frame__corner scan-frame__corner--tl" />
            <span className="scan-frame__corner scan-frame__corner--tr" />
            <span className="scan-frame__corner scan-frame__corner--br" />
            <span className="scan-frame__corner scan-frame__corner--bl" />
            {detected == null && camera.status === 'running' && <span className="scan-frame__line" aria-hidden />}
            {detected == null && (camera.status === 'starting' || checking) && (
              <div className="scan-frame__status" role="status">
                <QrLoader size={30} color="#fff" label={checking ? 'Checking the code' : 'Starting the camera'} />
                <span>{checking ? 'Checking the code…' : 'Starting the camera…'}</span>
              </div>
            )}
            {detected == null && issue && !checking && (
              <div className="scan-frame__status">
                <span className="scan-frame__icon">
                  <CameraOff size={showDemoCodes ? iconSize.xl : iconSize.hero} aria-hidden />
                </span>
                {showDemoCodes && (
                  <button type="button" className="scanner__demo-card" onClick={() => submit(payloadFor(5))}>
                    <QrCode payload={payloadFor(5)} size={88} label="Table 05 QR code" branded />
                    <span className="scanner__demo-beam" aria-hidden />
                    <span>Table 05 · Tap to simulate</span>
                  </button>
                )}
              </div>
            )}
            <AnimatePresence>
              {detected != null && (
                <motion.div className="scan-frame__success" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.25 }}>
                  <SuccessEmblem green size={emblemSize.sm} label={takeaway ? 'Takeaway selected' : 'Table detected'} />
                  <strong>{takeaway ? 'Takeaway selected' : `Table ${AppFormat.table(detected)} detected`}</strong>
                  <span>{takeaway ? 'Opening the menu…' : 'Opening your table…'}</span>
                </motion.div>
              )}
            </AnimatePresence>
          </motion.div>

          <div className="scanner__notices">
            <AnimatePresence mode="wait">
              {error ? (
                <motion.div
                  key={`error-${error.count}`}
                  className="scanner__notice scanner__notice--error"
                  role="alert"
                  initial={reduced ? { opacity: 0 } : { opacity: 0, x: 0 }}
                  animate={reduced ? { opacity: 1 } : { opacity: 1, x: [0, -10, 10, -6, 6, 0] }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.45 }}
                >
                  <CircleAlert size={iconSize.lg} />
                  <span className="grow">{error.message}</span>
                  <button type="button" className="scanner__notice-action" onClick={() => setError(null)}>
                    Try again
                  </button>
                </motion.div>
              ) : issue && detected == null ? (
                <motion.div key={issue} className="scanner__notice" role="status" variants={fadeSlideIn} initial="hidden" animate="shown" exit={{ opacity: 0 }}>
                  <CameraOff size={iconSize.lg} />
                  <span className="grow">{issueText[issue]}</span>
                  {issue !== 'unsupported' && issue !== 'insecure' && issue !== 'noCamera' && (
                    <button type="button" className="scanner__notice-action" onClick={() => void scanner.retry()}>
                      <RefreshCw size={iconSize.sm} /> Retry
                    </button>
                  )}
                </motion.div>
              ) : null}
            </AnimatePresence>
          </div>
        </div>

        <footer className="scanner__controls">
          {camera.status === 'running' && camera.torch != null && (
            <motion.button
              type="button"
              className={`scanner__round ${camera.torch ? 'is-active' : ''}`}
              whileTap={{ scale: 0.9 }}
              aria-label={camera.torch ? 'Turn flash off' : 'Turn flash on'}
              aria-pressed={camera.torch}
              onClick={() => void scanner.toggleTorch()}
            >
              {camera.torch ? <Flashlight size={iconSize.xl} /> : <FlashlightOff size={iconSize.xl} />}
            </motion.button>
          )}
          <motion.button type="button" className="scanner__cta" whileTap={{ scale: 0.97 }} onClick={() => setManualOpen(true)} disabled={detected != null}>
            <Keyboard size={iconSize.lg} /> Enter code or link
          </motion.button>
          {(showDemoCodes || (saved != null && detected == null)) && (
            <div className="scanner__secondary">
              {showDemoCodes && (
                <button type="button" className="scanner__ghost" onClick={() => setDemoOpen(true)} disabled={detected != null}>
                  <QrIcon size={iconSize.sm} /> Use a demo QR code
                </button>
              )}
              {saved != null && detected == null && (
                <button type="button" className="scanner__ghost" onClick={() => submit(payloadFor(saved))}>
                  {saved === TAKEAWAY_TABLE ? 'Continue with takeaway' : `Continue at Table ${AppFormat.table(saved)}`}
                </button>
              )}
            </div>
          )}
        </footer>
      </div>

      <ManualEntrySheet open={manualOpen} onClose={() => setManualOpen(false)} onSubmit={(raw) => {
        setManualOpen(false);
        submit(raw);
      }} />
      {showDemoCodes && (
        <Sheet open={demoOpen} onClose={() => setDemoOpen(false)} title="Demo QR codes">
          <div className="row" style={{ marginBottom: 6 }}>
            <h2 className="t-screen-title">Demo QR codes</h2>
            <DemoTag />
          </div>
          <p className="t-secondary">No table code nearby? Pick one to simulate a scan. Each goes through the same checks as the camera.</p>
          <div className="stack-sm" style={{ marginTop: 16 }}>
            {demoCodes.map((code) => (
              <button
                key={code.payload}
                type="button"
                className="card row demo-code"
                onClick={() => {
                  setDemoOpen(false);
                  submit(code.payload);
                }}
              >
                <QrCode payload={code.payload} size={52} label="" />
                <span className="col grow" style={{ textAlign: 'left' }}>
                  <span className="t-card-title">{code.title}</span>
                  <span className="t-caption">{code.subtitle ?? code.payload}</span>
                </span>
                <ScanLine size={iconSize.lg} color="var(--accent-text)" />
              </button>
            ))}
          </div>
        </Sheet>
      )}
    </div>
  );
}

function ManualEntrySheet({ open, onClose, onSubmit }: { open: boolean; onClose: () => void; onSubmit: (raw: string) => void }) {
  const [value, setValue] = useState('');
  useEffect(() => {
    if (open) setValue('');
  }, [open]);
  return (
    <Sheet open={open} onClose={onClose} title="Enter the code">
      <motion.form
        variants={collapse}
        initial="hidden"
        animate="shown"
        className="stack-md"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit(value);
        }}
      >
        <h2 className="t-screen-title">Enter the code or link</h2>
        <p className="t-secondary">
          Paste the link the table’s QR code opens (for example from Google Lens), or type the code text. It goes through the same checks as a scan.
        </p>
        <label className="field">
          <span className="field__label">Link or code</span>
          <input
            className="input"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={`${window.location.origin}${paths.table(5)}`}
            autoComplete="off"
            autoCapitalize="off"
            spellCheck={false}
            inputMode="url"
          />
        </label>
        <Button type="submit" block disabled={!value.trim()}>
          Continue
        </Button>
        <p className="t-caption t-center">Tip: your phone’s camera app or Google Lens can open the table’s code directly.</p>
      </motion.form>
    </Sheet>
  );
}
