import { Check, ChevronDown, ChevronUp, CircleAlert, Copy, ExternalLink, Info, QrCode as QrIcon, RefreshCw, Send, TimerOff, WifiOff } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { UpiPaymentLink, UpiReference, type GatewayCheckout, type Invoice, type PaymentTransaction, type UpiSettings } from '../core/billing';
import { Currency } from '../core/money';
import { AppFormat } from '../core/time';
import { useApp } from '../state/app';
import { QrCode } from './QrCode';
import { Sheet } from './Sheet';
import { Button, Card, Fact, FadeIn, Notice, QrLoader } from './ui';
import { iconSize } from './sizes';

const messageFor = (error: unknown) => (error instanceof Error && error.message ? error.message : 'Something went wrong. Please try again.');

/** A phone or tablet, where a UPI app may be on the same device. */
export const onPhone = () => typeof window !== 'undefined' && window.matchMedia?.('(pointer: coarse)').matches === true;

/** Runs [onBack] when the guest returns to this tab after leaving it. */
function useReturnToTab(active: boolean, onBack: () => void) {
  const left = useRef(false);
  const callback = useRef(onBack);
  callback.current = onBack;
  useEffect(() => {
    if (!active) return;
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') left.current = true;
      else if (left.current) {
        left.current = false;
        callback.current();
      }
    };
    document.addEventListener('visibilitychange', onVisibility);
    return () => document.removeEventListener('visibilitychange', onVisibility);
  }, [active]);
}

/** Asks the server every [ms] while mounted (the outcome arrives on its own). */
function usePoll(ms: number, poll: () => Promise<unknown>) {
  const callback = useRef(poll);
  callback.current = poll;
  useEffect(() => {
    const timer = setInterval(() => {
      if (document.visibilityState === 'visible') void callback.current().catch(() => undefined);
    }, ms);
    return () => clearInterval(timer);
  }, [ms]);
}

function CopyRow({ label, value, copy }: { label: string; value: string; copy?: string }) {
  const { toasts } = useApp();
  return (
    <div className="row" style={{ padding: '2px 0' }}>
      <div className="grow col">
        <span className="t-caption">{label}</span>
        <span className="t-label t-strong" style={{ userSelect: 'all', overflowWrap: 'anywhere' }}>
          {value}
        </span>
      </div>
      <button
        type="button"
        className="icon-btn"
        aria-label={`Copy ${label}`}
        style={{ color: 'var(--accent-text)' }}
        onClick={() => void navigator.clipboard?.writeText(copy ?? value).then(() => toasts.show(`${label} copied`))}
      >
        <Copy size={iconSize.md} />
      </button>
    </div>
  );
}

/**
 * Paying the restaurant's own UPI ID. The guest pays in their own UPI app;
 * this page never sees the money, so it only asks what happened, and the
 * bill is marked paid only after the restaurant confirms the money arrived.
 *
 * The filled-in link is never handed to a UPI app (Google Pay and PhonePe
 * refuse such app-initiated payments to a personal UPI ID): on a phone the
 * guest copies the UPI ID and pays in their app; the QR code holds the full
 * request for scanning from another phone.
 */
export function UpiPanel({
  header,
  invoice,
  payment,
  settings,
  onClaim,
  onCancel,
  onRefresh,
}: {
  header: ReactNode;
  invoice: Invoice;
  payment: PaymentTransaction;
  settings: UpiSettings;
  onClaim: (reference: string) => Promise<unknown>;
  onCancel: () => Promise<unknown>;
  onRefresh: () => Promise<unknown>;
}) {
  const { toasts } = useApp();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [askOutcome, setAskOutcome] = useState(false);
  const [claimOpen, setClaimOpen] = useState(false);
  const [ownQr, setOwnQr] = useState(false);
  const link = UpiPaymentLink.forPayment(settings, invoice, payment);
  const phone = onPhone();
  usePoll(10_000, onRefresh);
  // Back from the UPI app: what happened there is for the guest to say.
  useReturnToTab(copied && !payment.isClaimed, () => {
    setAskOutcome(true);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  const run = async (action: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      setError(messageFor(e));
    } finally {
      setBusy(false);
    }
  };

  const copyId = async () => {
    try {
      await navigator.clipboard.writeText(settings.upiId);
      toasts.show('UPI ID copied');
    } catch {
      toasts.show('Copy the UPI ID shown below.');
    }
    setCopied(true);
  };

  return (
    <div className="stack-lg">
      <FadeIn>{header}</FadeIn>
      {error && (
        <Notice tone="error" icon={<CircleAlert size={iconSize.lg} />} live>
          {error}
        </Notice>
      )}
      {payment.isClaimed ? (
        <>
          <Card>
            <div className="col" style={{ alignItems: 'center', textAlign: 'center', gap: 8 }}>
              <QrLoader size={28} label="Waiting for the restaurant" />
              <h2 className="t-section">Waiting for the restaurant</h2>
              <p className="t-secondary">
                You told us you paid {Currency.format(payment.amount)}. The restaurant checks its UPI account and confirms it. This page updates by itself, and your bill is
                marked paid only then.
              </p>
            </div>
            <div style={{ marginTop: 12 }}>
              {payment.claimedAt && <Fact label="Told us at" value={AppFormat.dateTime(payment.claimedAt)} />}
              {payment.reference && <Fact label="Your UPI transaction ID" value={payment.reference} />}
              <Fact label="Pay to" value={settings.payeeName} />
            </div>
          </Card>
          <Button variant="secondary" block icon={<RefreshCw size={iconSize.md} />} disabled={busy} onClick={() => void run(onRefresh)}>
            Check again
          </Button>
          <p className="t-caption t-center">Paid by mistake, or changed your mind? Ask the staff: only they can cancel a payment you have already told us about.</p>
        </>
      ) : !settings.isReady ? (
        <>
          <Notice icon={<Info size={iconSize.lg} />}>
            The restaurant’s UPI details are not available right now, so this payment cannot continue. Cancel it and pay at the counter, or try again in a moment.
          </Notice>
          <Button variant="secondary" block icon={<RefreshCw size={iconSize.md} />} disabled={busy} onClick={() => void run(onRefresh)}>
            Try again
          </Button>
          <Button variant="ghost" muted block disabled={busy} onClick={() => void run(onCancel)}>
            Cancel this payment
          </Button>
        </>
      ) : (
        <>
          <AnimatePresence>
            {askOutcome && (
              <motion.div key="outcome" initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="outcome">
                <h2 className="t-section">Did your payment go through?</h2>
                <p className="t-secondary">We can’t see what happened in your UPI app, so please tell us. The restaurant will confirm the money before your bill is marked paid.</p>
                <Button block icon={<Check size={iconSize.md} />} disabled={busy} onClick={() => {
                  setAskOutcome(false);
                  setClaimOpen(true);
                }}>
                  Yes, I’ve paid
                </Button>
                <Button variant="secondary" block disabled={busy} onClick={() => void run(onCancel)}>
                  No, it failed or I cancelled
                </Button>
                <Button variant="ghost" muted block onClick={() => setAskOutcome(false)}>
                  Not sure yet
                </Button>
              </motion.div>
            )}
          </AnimatePresence>
          <FadeIn index={1}>
            <Card>
              {phone ? (
                <>
                  <h2 className="t-section">Pay with your UPI app</h2>
                  <p className="t-secondary" style={{ whiteSpace: 'pre-line', marginTop: 4 }}>
                    {`1. Tap below: we copy the restaurant's UPI ID.\n2. In your UPI app, choose “Pay UPI ID” (or “Pay anyone”), paste it and pay exactly ₹${link.amountText}. Add the note “${link.note}”.\n3. Come back here and tell us.`}
                  </p>
                  <div style={{ marginTop: 12 }}>
                    <Button block icon={<Copy size={iconSize.md} />} disabled={busy} onClick={() => void copyId()}>
                      {copied ? 'Copy UPI ID again' : 'Copy UPI ID'}
                    </Button>
                  </div>
                  <p className="t-caption" style={{ marginTop: 12 }}>
                    Why isn’t the amount filled in? Google Pay and PhonePe refuse a payment that another app fills in for a restaurant’s own UPI ID. A payment you start in
                    the app goes through.
                  </p>
                </>
              ) : (
                <>
                  <h2 className="t-section">Pay with your UPI app</h2>
                  <p className="t-secondary" style={{ marginTop: 4 }}>
                    Open this page on your phone to pay with a UPI app, or scan the QR code below with your phone.
                  </p>
                </>
              )}
            </Card>
          </FadeIn>
          <FadeIn index={2}>
            <Card>
              <div className="col" style={{ alignItems: 'center', textAlign: 'center', gap: 8 }}>
                <h2 className="t-section">{phone ? 'Or scan the QR code' : 'Scan with your phone'}</h2>
                <p className="t-caption">Any UPI app can scan this. The amount and note are filled in.</p>
                <div className="qr-box">
                  <QrCode payload={link.uriString} size={220} label={`QR code to pay ${Currency.format(payment.amount)} to ${settings.payeeName} by UPI`} />
                </div>
              </div>
            </Card>
          </FadeIn>
          <FadeIn index={3}>
            <Card>
              <h2 className="t-section">Or enter the details</h2>
              <p className="t-caption" style={{ margin: '4px 0 8px' }}>
                In your UPI app, pay to this UPI ID. Use exactly this amount, and add the note so the restaurant can match it.
              </p>
              <CopyRow label="Pay to" value={settings.payeeName} />
              <CopyRow label="UPI ID" value={settings.upiId} />
              <CopyRow label="Amount" value={`₹${link.amountText}`} copy={link.amountText} />
              <CopyRow label="Note" value={link.note} />
            </Card>
          </FadeIn>
          {settings.hasQrImage && (
            <Card>
              <button type="button" className="row" style={{ width: '100%' }} aria-expanded={ownQr} onClick={() => setOwnQr(!ownQr)}>
                <span className="t-section grow" style={{ textAlign: 'left' }}>
                  The restaurant’s own QR
                </span>
                {ownQr ? <ChevronUp size={iconSize.lg} /> : <ChevronDown size={iconSize.lg} />}
              </button>
              {ownQr && (
                <div className="stack-md" style={{ marginTop: 8 }}>
                  <p className="t-caption">
                    This one does not carry the amount: enter ₹{link.amountText} yourself, and add the note “{link.note}”.
                  </p>
                  <img src={settings.qrImageUrl} alt="The restaurant's UPI QR code" style={{ maxWidth: 240, margin: '0 auto' }} />
                </div>
              )}
            </Card>
          )}
          <Button variant="secondary" block icon={<Check size={iconSize.md} />} disabled={busy} onClick={() => setClaimOpen(true)} data-testid="upi-paid">
            I’ve paid
          </Button>
          <Button variant="ghost" muted block disabled={busy} onClick={() => void run(onCancel)}>
            Cancel this payment
          </Button>
        </>
      )}
      <ClaimSheet open={claimOpen} onClose={() => setClaimOpen(false)} onSend={onClaim} />
    </div>
  );
}

/** "I've paid", optionally with the UPI transaction ID. Only tells the staff. */
function ClaimSheet({ open, onClose, onSend }: { open: boolean; onClose: () => void; onSend: (reference: string) => Promise<unknown> }) {
  const [reference, setReference] = useState('');
  const [busy, setBusy] = useState(false);
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const send = async () => {
    const value = UpiReference.normalize(reference);
    if (value && !UpiReference.isValid(value)) return setFieldError(UpiReference.rule);
    setBusy(true);
    setFieldError(null);
    setError(null);
    try {
      await onSend(value);
      onClose();
    } catch (e) {
      setError(messageFor(e));
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet open={open} onClose={onClose} title="Tell the restaurant you paid" dismissible={!busy}>
      <form
        className="stack-md"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <h2 className="t-section">Tell the restaurant you paid</h2>
        <p className="t-secondary">They will check their UPI account and confirm it. Your bill is marked paid only after they do.</p>
        <label className="field">
          <span className="field__label">UPI transaction ID (optional)</span>
          <input
            className="input"
            value={reference}
            maxLength={40}
            disabled={busy}
            onChange={(e) => setReference(e.target.value.replace(/\s/g, ''))}
            autoCapitalize="characters"
            autoComplete="off"
            spellCheck={false}
            aria-invalid={fieldError != null}
          />
          <span className={fieldError ? 'field__error' : 'field__hint'}>{fieldError ?? 'Shown in your UPI app after paying. It helps the staff find your payment.'}</span>
        </label>
        {error && (
          <Notice tone="error" icon={<CircleAlert size={iconSize.lg} />} live>
            {error}
          </Notice>
        )}
        <Button type="submit" block loading={busy} icon={<Send size={iconSize.md} />}>
          Tell the restaurant
        </Button>
        <Button variant="ghost" muted block disabled={busy} onClick={onClose}>
          Back
        </Button>
      </form>
    </Sheet>
  );
}

/**
 * A UPI payment collected by the gateway while it waits. Nothing here
 * decides the outcome: the gateway reports to the server, which settles the
 * bill; this page asks the server every few seconds and when the guest comes
 * back from their UPI app.
 */
export function GatewayPanel({
  header,
  invoice,
  payment,
  inAppAtStart,
  checkout,
  onRefresh,
  onCancel,
}: {
  header: ReactNode;
  invoice: Invoice;
  payment: PaymentTransaction;
  /** Pay in a UPI app on this phone (else by QR code). */
  inAppAtStart: boolean;
  checkout: (qr: boolean) => Promise<GatewayCheckout>;
  onRefresh: () => Promise<unknown>;
  onCancel: () => Promise<unknown>;
}) {
  const [inApp, setInApp] = useState(inAppAtStart);
  const [data, setData] = useState<GatewayCheckout | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [offline, setOffline] = useState(false);
  const [launched, setLaunched] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [, setTick] = useState(0);
  const refreshing = useRef(false);
  const provider = payment.provider;
  const amount = Currency.format(payment.amount);

  const refresh = async () => {
    if (refreshing.current || cancelling) return;
    refreshing.current = true;
    try {
      await onRefresh();
      setOffline(false);
    } catch {
      setOffline(true);
    } finally {
      refreshing.current = false;
    }
  };
  usePoll(4000, refresh);
  useReturnToTab(true, () => void refresh());
  useEffect(() => {
    const timer = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  const load = async (qr: boolean) => {
    setLoading(true);
    setError(null);
    try {
      setData(await checkout(qr));
    } catch (e) {
      setError(messageFor(e));
    } finally {
      setLoading(false);
    }
  };
  // Loaded again only when switching between an app and the QR code.
  useEffect(() => {
    void load(!inApp);
  }, [inApp]);

  const openApp = () => {
    const link = data?.payLink;
    if (!link) return setError('This payment has no UPI app link. Pay by QR code instead.');
    setLaunched(true);
    // The phone offers its UPI apps for the upi:// link (the gateway's merchant ID).
    window.location.href = link;
  };

  const expires = data?.expiresAt;
  const left = expires ? expires.getTime() - Date.now() : null;
  const expired = left != null && left <= 0;
  const leftText = left != null && left > 0 ? `${Math.floor(left / 60000)}:${Math.floor((left % 60000) / 1000).toString().padStart(2, '0')}` : null;

  return (
    <div className="stack-lg">
      {header}
      <Card>
        <div className="row-top" style={{ gap: 12 }}>
          <QrLoader size={20} label="Waiting for the payment" />
          <div className="grow col">
            <h2 className="t-section">Waiting for your payment</h2>
            <p className="t-secondary">{inApp ? `Pay ${amount} in your UPI app.` : `Scan the QR code with any UPI app and pay ${amount}.`}</p>
            <p className="t-caption" style={{ marginTop: 4 }}>
              This page updates by itself as soon as {provider} confirms the payment. You do not need to show anyone a screenshot.
            </p>
            {leftText && <p className="t-label t-info" style={{ marginTop: 4 }}>Pay within {leftText}</p>}
          </div>
        </div>
      </Card>
      {offline && (
        <Notice tone="warning" icon={<WifiOff size={iconSize.lg} />}>
          Cannot reach the restaurant server right now. Still checking; if you paid, your payment is safe and will show here.
        </Notice>
      )}
      {expired && (
        <Notice tone="warning" icon={<TimerOff size={iconSize.lg} />}>
          The time to pay has run out. If you did not pay, cancel and start again.
        </Notice>
      )}
      {loading ? (
        <div className="center" style={{ padding: 16 }}>
          <QrLoader size={26} label="Preparing the payment" />
        </div>
      ) : error ? (
        <>
          <Notice tone="error" icon={<CircleAlert size={iconSize.lg} />} live>
            {error}
          </Notice>
          <Button variant="secondary" block onClick={() => void load(!inApp)}>
            Try again
          </Button>
        </>
      ) : inApp ? (
        <Button block icon={<ExternalLink size={iconSize.md} />} onClick={openApp}>
          {launched ? 'Open my UPI app again' : 'Open my UPI app'}
        </Button>
      ) : (
        <Card>
          <div className="col" style={{ alignItems: 'center', textAlign: 'center', gap: 8 }}>
            <h2 className="t-section">Scan to pay</h2>
            {data?.qrDataUrl ? (
              <img className="qr-box" src={data.qrDataUrl} width={220} height={220} alt={`UPI QR code for ${amount}`} style={{ imageRendering: 'pixelated' }} />
            ) : data?.qrText ? (
              <div className="qr-box">
                <QrCode payload={data.qrText} size={220} label={`UPI QR code for ${amount}`} />
              </div>
            ) : (
              <p className="t-secondary">The QR code is not available. Try a UPI app instead.</p>
            )}
            <span className="t-headline">{amount}</span>
            <span className="t-caption">
              To {invoice.restaurant.name} · Bill {invoice.billNumber}
            </span>
            <span className="t-caption">The amount is filled in. Scan with Google Pay, PhonePe, Paytm, BHIM or any UPI app, on this phone or another.</span>
          </div>
        </Card>
      )}
      {inApp ? (
        <Button variant="secondary" block icon={<QrIcon size={iconSize.md} />} disabled={loading} onClick={() => setInApp(false)}>
          Pay by QR code instead
        </Button>
      ) : (
        onPhone() && (
          <Button variant="ghost" block disabled={loading} onClick={() => setInApp(true)}>
            Pay with a UPI app on this phone
          </Button>
        )
      )}
      <Button
        variant="ghost"
        muted
        block
        disabled={cancelling}
        onClick={async () => {
          setCancelling(true);
          setError(null);
          try {
            await onCancel();
          } catch (e) {
            setError(messageFor(e));
          } finally {
            setCancelling(false);
          }
        }}
      >
        {cancelling ? 'Cancelling…' : 'Cancel payment'}
      </Button>
      <p className="t-caption t-center">
        Your bill is marked paid only when {provider} confirms the money reached the restaurant. Coming back from your UPI app does not change it on its own, and you are never
        charged twice for this payment.
      </p>
    </div>
  );
}
