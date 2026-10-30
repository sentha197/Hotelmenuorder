import { CheckCircle2, Copy, FlaskConical, Landmark, Wallet, X, XCircle } from 'lucide-react';
import { useMemo, useState } from 'react';
import { paymentOptionInfo, type Invoice, type PaymentOption } from '../core/billing';
import { Currency, type Paise } from '../core/money';
import { randomId } from '../core/time';
import type { SimulatedOutcome } from '../services/paymentService';
import { useApp } from '../state/app';
import { methodIcon } from './invoice';
import { QrCode } from './QrCode';
import { Sheet } from './Sheet';
import { Button, DemoTag } from './ui';
import { iconSize } from './sizes';

export interface DemoCheckoutResult {
  outcome: SimulatedOutcome;
  detail: string;
}

/** Shown, never payable. */
const DEMO_UPI_ID = 'dineqr.demo@demo';
const demoBanks = ['HDFC Bank', 'ICICI Bank', 'State Bank of India', 'Axis Bank', 'Kotak Mahindra Bank'];
const demoWallets = ['Paytm', 'PhonePe', 'Amazon Pay', 'MobiKwik'];

const safety: Partial<Record<PaymentOption, string>> = {
  upi: 'Demo UPI ID and QR code: not a real account or payment request. Scanning it cannot start a payment, and no UPI PIN is asked for.',
  scanAndPay: 'Demo UPI ID and QR code: not a real account or payment request. Scanning it cannot start a payment, and no UPI PIN is asked for.',
  card: 'Demo card: no real card number, expiry date or CVV is asked for or stored.',
  netBanking: 'No bank is contacted and no banking password is asked for.',
  wallet: 'No wallet is contacted and nothing is debited from it.',
};

/**
 * The demo checkout for an online option. Closing it records nothing; only
 * "Confirm demo payment" (or a simulated failure) goes to the server's
 * simulator, which labels the payment as a demo.
 */
export function DemoCheckoutSheet({
  open,
  option,
  amount,
  invoice,
  onDone,
}: {
  open: boolean;
  option: PaymentOption;
  amount: Paise;
  invoice: Invoice;
  onDone: (result: DemoCheckoutResult | null) => void;
}) {
  const { toasts } = useApp();
  const [credit, setCredit] = useState(true);
  const [bank, setBank] = useState(demoBanks[0]!);
  const [wallet, setWallet] = useState(demoWallets[0]!);
  // A fresh reference each time the sheet opens, so two codes never look alike.
  const ref = useMemo(() => (open ? randomId(8) : ''), [open]);
  const info = paymentOptionInfo[option];
  // Deliberately not a `upi://pay` request: no UPI app can start a transfer from it.
  const payload = `DINEQR-DEMO-PAYMENT|NOT-A-REAL-PAYMENT-REQUEST|bill=${invoice.billNumber}|amount=${Currency.plain(amount)}|currency=${Currency.code}|ref=${ref}`;
  const detail = option === 'card' ? (credit ? 'Credit' : 'Debit') : option === 'netBanking' ? bank : option === 'wallet' ? wallet : info.detail;
  const finish = (outcome: SimulatedOutcome) => onDone({ outcome, detail });

  return (
    <Sheet open={open} onClose={() => onDone(null)} title={option === 'scanAndPay' ? 'QR Payment' : `Pay by ${info.label}`}>
      <div className="row" style={{ marginBottom: 16 }}>
        <span className="option-icon is-selected">{info.method ? methodIcon(info.method, 22) : null}</span>
        <div className="grow col">
          <span className="t-section">{option === 'scanAndPay' ? 'QR Payment' : `Pay by ${info.label}`}</span>
          <span className="t-caption">
            {Currency.format(amount)} · Bill {invoice.billNumber}
          </span>
        </div>
        <DemoTag label="DEMO PAYMENT" />
      </div>
      {option === 'upi' && (
        <div className="stack-md">
          <span className="t-label">Pay to this UPI ID</span>
          <div className="copy-box">
            <span className="t-card-title grow ellipsis">{DEMO_UPI_ID}</span>
            <button
              type="button"
              className="icon-btn"
              aria-label="Copy UPI ID"
              onClick={() => {
                void navigator.clipboard?.writeText(DEMO_UPI_ID).then(() => toasts.show('Demo UPI ID copied'));
              }}
            >
              <Copy size={iconSize.md} />
            </button>
          </div>
          <div className="row" style={{ gap: 12 }}>
            <QrCode payload={payload} size={112} label="Demo payment QR code" branded />
            <p className="t-secondary grow">Open any UPI app, pay {Currency.format(amount)} to the ID above, then confirm below. Or scan the code.</p>
          </div>
        </div>
      )}
      {option === 'scanAndPay' && (
        <div className="col" style={{ alignItems: 'center', gap: 8 }}>
          <QrCode payload={payload} size={200} label="Demo QR Payment code" branded />
          <span className="t-card-title">Scan with any UPI app</span>
          <span className="t-caption">
            {Currency.format(amount)} to {DEMO_UPI_ID}
          </span>
        </div>
      )}
      {option === 'card' && (
        <div className="stack-md">
          <div className="segmented segmented--inline" role="radiogroup" aria-label="Card type">
            {[true, false].map((value) => (
              <button key={String(value)} type="button" role="radio" aria-checked={credit === value} className={`segmented__tab ${credit === value ? 'is-selected is-static' : ''}`} onClick={() => setCredit(value)}>
                <span className="segmented__label">{value ? 'Credit card' : 'Debit card'}</span>
              </button>
            ))}
          </div>
          <div className="demo-card">
            <div className="row">
              <span className="t-overline grow">{credit ? 'DEMO CREDIT CARD' : 'DEMO DEBIT CARD'}</span>
              <DemoTag dark />
            </div>
            <span className="demo-card__number">4111 1111 1111 1111</span>
            <span className="t-label">DINEQR DEMO GUEST · 12/30 · CVV •••</span>
          </div>
        </div>
      )}
      {(option === 'netBanking' || option === 'wallet') && (
        <fieldset className="choice-list">
          <legend className="t-label">{option === 'netBanking' ? 'Choose your bank' : 'Choose your wallet'}</legend>
          {(option === 'netBanking' ? demoBanks : demoWallets).map((name) => (
            <label key={name} className="choice-list__item">
              <input type="radio" name="demo-choice" checked={(option === 'netBanking' ? bank : wallet) === name} onChange={() => (option === 'netBanking' ? setBank(name) : setWallet(name))} />
              {option === 'netBanking' ? <Landmark size={iconSize.md} /> : <Wallet size={iconSize.md} />}
              <span className="t-label">{name}</span>
            </label>
          ))}
        </fieldset>
      )}
      {safety[option] && (
        <div className="notice tone-info" style={{ marginTop: 16 }}>
          <FlaskConical size={iconSize.md} />
          <span className="grow">{safety[option]} Confirming records a demo payment: no money is charged or transferred.</span>
        </div>
      )}
      <div className="stack-sm" style={{ marginTop: 16 }}>
        <Button block icon={<CheckCircle2 size={iconSize.lg} />} onClick={() => finish('success')} data-testid="confirm-demo">
          Confirm demo payment
        </Button>
        <div className="row center wrap" style={{ gap: 12 }}>
          <Button variant="ghost" style={{ color: 'var(--error)' }} icon={<XCircle size={iconSize.md} />} onClick={() => finish('failure')}>
            Simulate failure
          </Button>
          <Button variant="ghost" muted icon={<X size={iconSize.md} />} onClick={() => finish('cancel')}>
            Cancel payment
          </Button>
        </div>
      </div>
    </Sheet>
  );
}
