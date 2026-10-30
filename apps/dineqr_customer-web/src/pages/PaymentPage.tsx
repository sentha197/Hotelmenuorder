import { AtSign, Banknote, CheckCircle2, CircleAlert, CreditCard, FlaskConical, Landmark, Lock, QrCode as QrIcon, ScanLine, Split, Store, Wallet, ChevronRight } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useState, type ReactNode } from 'react';
import { useNavigate, useParams } from 'react-router';
import { collapse } from '../animations/variants';
import { PaymentStatusBadge } from '../components/badges';
import { Mark } from '../components/brand';
import { DemoCheckoutSheet, type DemoCheckoutResult } from '../components/DemoCheckout';
import { GatewayPanel, onPhone, UpiPanel } from '../components/paymentPanels';
import { AppBar, BrandPanel, Button, Card, DemoTag, EmptyState, Fact, FadeIn, IconHalo, QrLoader, SuccessEmblem } from '../components/ui';
import { isOnlineOption, paymentOptionInfo, type Invoice, type PaymentOption, type PaymentTransaction } from '../core/billing';
import { Currency, type Paise } from '../core/money';
import { AppFormat, randomId } from '../core/time';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { emblemSize, iconSize } from '../components/sizes';

type Stage = 'choose' | 'processing' | 'success' | 'failed' | 'cancelled' | 'counter' | 'upi' | 'gateway';

const optionIcon: Record<PaymentOption, ReactNode> = {
  upi: <AtSign size={iconSize.lg} />,
  scanAndPay: <ScanLine size={iconSize.lg} />,
  card: <CreditCard size={iconSize.lg} />,
  netBanking: <Landmark size={iconSize.lg} />,
  wallet: <Wallet size={iconSize.lg} />,
  cash: <Banknote size={iconSize.lg} />,
  payAtCounter: <Store size={iconSize.lg} />,
};

/**
 * Pays all or part of a bill: UPI (to the restaurant, or through the live
 * gateway), QR Payment, card / net banking / wallet where the demo offers
 * them, cash or the counter, or split. Coming back from a UPI app never
 * counts as payment: only the server's answer does.
 */
export function PaymentPage() {
  const { billing } = useApp();
  useStore(billing);
  const { invoiceId = '' } = useParams();
  const navigate = useNavigate();
  const invoice = billing.byId(invoiceId);

  const [stage, setStage] = useState<Stage>(() => {
    const unfinished = invoice?.payments.filter((p) => (p.isUpiDirect || p.isGateway) && p.status === 'pending').at(-1);
    return unfinished ? (unfinished.isGateway ? 'gateway' : 'upi') : 'choose';
  });
  const [paymentId, setPaymentId] = useState<string | null>(
    () => invoice?.payments.filter((p) => (p.isUpiDirect || p.isGateway) && p.status === 'pending').at(-1)?.id ?? null,
  );
  const [option, setOption] = useState<PaymentOption | null>(null);
  const [payFull, setPayFull] = useState(true);
  const [amountText, setAmountText] = useState('');
  const [amountError, setAmountError] = useState<string | null>(null);
  const [result, setResult] = useState<PaymentTransaction | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  // Reused when an attempt is retried after its result never arrived, so the
  // server returns that attempt instead of charging again.
  const [attemptKey, setAttemptKey] = useState<string | null>(null);
  const [inApp, setInApp] = useState(false);
  const [starting, setStarting] = useState(false);
  const [demo, setDemo] = useState<{ option: PaymentOption; amount: Paise } | null>(null);

  useEffect(() => {
    // The payee may have changed since the bill was loaded.
    void billing.loadUpiSettings();
  }, [billing]);

  // The payment shown is no longer on the bill (it was reloaded): back to the choice.
  const missing = (stage === 'upi' || stage === 'gateway') && invoice != null && payments(invoice, paymentId) == null;
  useEffect(() => {
    if (!missing) return;
    setStage('choose');
    setPaymentId(null);
  }, [missing]);

  if (!invoice) {
    return (
      <div>
        <AppBar title="Payment" />
        <EmptyState icon={<CircleAlert size={iconSize.hero} />} title="Bill not found" message="This bill is not available in this session." />
      </div>
    );
  }

  const options = billing.paymentOptions;
  // Real-money UPI is chosen until the guest picks another, so the page never
  // opens on demo wording.
  const selected: PaymentOption | null =
    option && options.includes(option) ? option : billing.gatewayUpiAvailable || billing.upiDirectAvailable ? 'upi' : null;
  const amount: Paise | null = payFull ? invoice.payableNow : Currency.parse(amountText);
  const processing = stage === 'processing';

  const retry = () => {
    setStage('choose');
    setPaymentId(null);
    setResult(null);
    setMessage(null);
  };

  const pay = async (chosen: PaymentOption) => {
    if (starting || processing) return;
    if (amount == null) return setAmountError('Enter an amount, e.g. 250 or 250.50.');
    const problem = billing.validate(invoice, amount);
    if (problem) return setAmountError(problem);
    setAmountError(null);
    const info = paymentOptionInfo[chosen];
    if (!isOnlineOption(chosen)) {
      setStage('processing');
      try {
        await billing.requestCounterPayment(invoice.id, info.counter!, amount);
        setStage('counter');
      } catch (error) {
        setStage('choose');
        setAmountError(error instanceof Error ? error.message : 'Please try again.');
      }
      return;
    }
    // QR Payment is paid by scanning, so no app opens for it.
    const app = chosen === 'upi' && onPhone();
    if (billing.isGatewayOption(chosen)) {
      setStarting(true);
      const key = attemptKey ?? randomId();
      setAttemptKey(key);
      try {
        const payment = await billing.startGatewayUpi(invoice.id, amount, key, app ? '' : paymentOptionInfo.scanAndPay.detail);
        setAttemptKey(null);
        setPaymentId(payment.id);
        setInApp(app);
        setStage('gateway');
      } catch (error) {
        setResult(null);
        setMessage(error instanceof Error ? error.message : null);
        setStage('failed');
      } finally {
        setStarting(false);
      }
      return;
    }
    if (billing.isDirectUpiOption(chosen)) {
      setStarting(true);
      try {
        // The payee as the server has it now, never a stale one.
        await billing.loadUpiSettings();
        if (!billing.upiSettings.isReady) {
          throw new Error('The restaurant’s UPI details are not available right now. Pay at the counter, or try again in a moment.');
        }
        const payment = await billing.startUpiPayment(invoice.id, amount);
        setPaymentId(payment.id);
        setStage('upi');
      } catch (error) {
        setResult(null);
        setMessage(error instanceof Error ? error.message : null);
        setStage('failed');
      } finally {
        setStarting(false);
      }
      return;
    }
    if (billing.isSimulated) {
      // The demo checkout: paid only once the guest confirms there.
      setDemo({ option: chosen, amount });
      return;
    }
    await payOnline(chosen, amount, { outcome: 'success', detail: info.detail });
  };

  const payOnline = async (chosen: PaymentOption, value: Paise, checkout: DemoCheckoutResult) => {
    const key = attemptKey ?? randomId();
    setAttemptKey(key);
    setStage('processing');
    try {
      const payment = await billing.payOnline({
        invoiceId: invoice.id,
        amount: value,
        method: paymentOptionInfo[chosen].method!,
        methodDetail: checkout.detail,
        idempotencyKey: key,
        outcome: checkout.outcome,
      });
      setAttemptKey(null);
      setResult(payment);
      setMessage(payment.failureReason || null);
      setStage(payment.status === 'succeeded' ? 'success' : payment.status === 'cancelled' ? 'cancelled' : 'failed');
      navigator.vibrate?.(payment.status === 'succeeded' ? 30 : [30, 40, 30]);
    } catch (error) {
      // The key is kept: trying again replays this attempt, never a second charge.
      setResult(null);
      setMessage(error instanceof Error ? error.message : null);
      setStage('failed');
    }
  };

  const shown = payments(invoice, paymentId);
  const header = (value: Paise) => <AmountHeader invoice={invoice} amount={value} />;
  const done = () => navigate(paths.bill(invoice.id), { replace: true });
  const receipt = () => navigate(paths.receipt(invoice.id));

  let body: ReactNode;
  if (stage === 'upi' || stage === 'gateway') {
    if (!shown) {
      body = <QrLoader size={28} label="Loading the payment" />;
    } else if (shown.status === 'pending') {
      body =
        stage === 'upi' ? (
          <UpiPanel
            header={header(shown.amount)}
            invoice={invoice}
            payment={shown}
            settings={billing.upiSettings}
            onClaim={(reference) => billing.claimUpiPayment(shown.id, reference)}
            onCancel={() => billing.cancelPayment(shown.id)}
            onRefresh={() => billing.checkPending(invoice.id)}
          />
        ) : (
          <GatewayPanel
            key={shown.id}
            header={header(shown.amount)}
            invoice={invoice}
            payment={shown}
            inAppAtStart={inApp}
            checkout={(qr) => billing.gatewayCheckout(shown.id, qr)}
            onRefresh={() => billing.checkPending(invoice.id)}
            onCancel={() => billing.cancelPayment(shown.id)}
          />
        );
    } else if (shown.status === 'succeeded') {
      body = (
        <Result
          success
          title={stage === 'upi' ? 'Payment confirmed' : shown.isSimulated ? 'Demo payment successful' : 'Payment successful'}
          message={stage === 'upi' ? 'The restaurant confirmed your UPI payment.' : `${shown.provider} confirmed your UPI payment. Your bill is updated.`}
          invoice={invoice}
          transaction={shown}
          primary={['Done', done]}
          secondary={['View, print or share receipt', receipt]}
        />
      );
    } else {
      const failedText =
        stage === 'upi'
          ? shown.status === 'failed'
            ? `${shown.failureReason || 'The restaurant did not receive this payment.'} Your bill is still unpaid. If money left your account, show your UPI receipt to the staff.`
            : 'Nothing was recorded on your bill. If money has left your account, show your UPI receipt to the staff.'
          : shown.failureReason || (shown.status === 'failed' ? 'The payment did not go through. No money was taken.' : 'Nothing was charged. You can try again any time.');
      body = (
        <Result
          title={stage === 'upi' ? (shown.status === 'failed' ? 'Payment not received' : 'Payment cancelled') : shown.status === 'failed' ? 'Payment failed' : 'Payment not completed'}
          message={failedText}
          invoice={invoice}
          transaction={shown}
          primary={['Try again', retry]}
          secondary={['Back to bill', done]}
        />
      );
    }
  } else if (stage === 'processing') {
    const counter = selected != null && !isOnlineOption(selected);
    body = (
      <div className="processing" role="status">
        <Mark size={80} />
        <QrLoader size={28} label={counter ? 'Letting staff know' : 'Confirming payment'} />
        <h2 className="t-section">{counter ? 'Letting the staff know…' : billing.isSimulated ? 'Confirming your demo payment…' : 'Confirming your payment…'}</h2>
        <p className="t-secondary">{counter ? 'Nothing is charged here.' : billing.isSimulated ? 'The demo simulator is processing it. No money moves.' : 'Please keep this page open.'}</p>
      </div>
    );
  } else if (stage === 'success') {
    body = (
      <Result
        success
        title={result?.isSimulated ? 'Demo payment successful' : 'Payment successful'}
        invoice={invoice}
        transaction={result}
        primary={['Done', done]}
        secondary={['View, print or share receipt', receipt]}
      />
    );
  } else if (stage === 'failed' || stage === 'cancelled') {
    body = (
      <Result
        title={stage === 'failed' ? 'Payment failed' : 'Payment cancelled'}
        message={stage === 'failed' ? message || 'The payment did not go through. No money was taken.' : 'Nothing was charged. You can try again any time.'}
        invoice={invoice}
        transaction={result}
        primary={['Try again', retry]}
        secondary={['Back to bill', done]}
      />
    );
  } else if (stage === 'counter') {
    body = <CounterResult invoice={invoice} simulated={billing.isSimulated} onDone={done} onPayOnline={billing.onlinePaymentsAvailable ? async () => {
      try {
        await billing.cancelCounterRequest(invoice.id);
      } catch {
        // The choice screen shows the bill as it is.
      }
      retry();
    } : null} />;
  } else {
    body = <ChooseForm
      invoice={invoice}
      selected={selected}
      onSelect={(o) => {
        setOption(o);
        setAttemptKey(null);
        setAmountError(null);
      }}
      payFull={payFull}
      onPayFull={(full) => {
        setPayFull(full);
        setAmountError(null);
        setAttemptKey(null);
      }}
      amountText={amountText}
      onAmountText={(text) => {
        setAmountText(text);
        setAmountError(null);
        setAttemptKey(null);
      }}
      amountError={amountError}
      amount={amount}
    />;
  }

  const canPay = stage === 'choose' && invoice.payableNow > 0 && selected != null;
  return (
    <div className={canPay ? 'with-bottom-bar' : undefined}>
      <AppBar title="Payment" back={!processing} />
      <div className="page page--narrow">
        <AnimatePresence mode="wait">
          <motion.div key={stage} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.22 }}>
            {body}
          </motion.div>
        </AnimatePresence>
      </div>
      {canPay && (
        <div className="bottom-bar">
          <div className="bottom-bar__inner">
            <Button
              block
              loading={starting}
              icon={selected === 'scanAndPay' ? <QrIcon size={iconSize.lg} /> : isOnlineOption(selected) ? <Lock size={iconSize.md} /> : <Store size={iconSize.lg} />}
              onClick={() => void pay(selected)}
              data-testid="pay-button"
            >
              {payLabel(selected, amount)}
            </Button>
          </div>
        </div>
      )}
      {demo && (
        <DemoCheckoutSheet
          open
          option={demo.option}
          amount={demo.amount}
          invoice={invoice}
          onDone={(checkout) => {
            const chosen = demo;
            setDemo(null);
            if (checkout) void payOnline(chosen.option, chosen.amount, checkout);
          }}
        />
      )}
    </div>
  );
}

function payments(invoice: Invoice, id: string | null) {
  return id == null ? null : (invoice.payments.find((p) => p.id === id) ?? null);
}

function payLabel(option: PaymentOption, amount: Paise | null): string {
  const value = amount == null ? '' : ` ${Currency.format(amount)}`;
  switch (option) {
    case 'cash':
      return `Pay${value} in cash`;
    case 'payAtCounter':
      return `Pay${value} at the counter`;
    case 'scanAndPay':
      return `Pay${value} by QR code`;
    default:
      return `Pay${value} with ${paymentOptionInfo[option].label}`;
  }
}

function AmountHeader({ invoice, amount }: { invoice: Invoice; amount: Paise }) {
  return (
    <BrandPanel lifted className="amount-header">
      <span className="t-overline" style={{ color: 'rgb(255 255 255 / 75%)' }}>
        AMOUNT TO PAY
      </span>
      <motion.span key={amount} className="layered-text amount-header__value" initial={{ opacity: 0.4, y: 4 }} animate={{ opacity: 1, y: 0 }}>
        {Currency.format(amount)}
      </motion.span>
      <span className="t-caption" style={{ color: 'rgb(255 255 255 / 85%)' }}>
        Bill {invoice.billNumber} · {invoice.tableLabel} · Total {Currency.format(invoice.total)}
      </span>
      {invoice.amountPaid > 0 && (
        <span className="t-caption" style={{ color: 'var(--peach)' }}>
          Already paid {Currency.format(invoice.amountPaid)}
          {invoice.hasDemoPayments ? ' (demo)' : ''}
        </span>
      )}
    </BrandPanel>
  );
}

function ChooseForm({
  invoice,
  selected,
  onSelect,
  payFull,
  onPayFull,
  amountText,
  onAmountText,
  amountError,
  amount,
}: {
  invoice: Invoice;
  selected: PaymentOption | null;
  onSelect: (option: PaymentOption) => void;
  payFull: boolean;
  onPayFull: (full: boolean) => void;
  amountText: string;
  onAmountText: (text: string) => void;
  amountError: string | null;
  amount: Paise | null;
}) {
  const { billing } = useApp();
  const navigate = useNavigate();
  const payable = invoice.payableNow;
  if (payable === 0) {
    return (
      <EmptyState
        icon={<CheckCircle2 size={iconSize.hero} />}
        title="Nothing to pay"
        message={invoice.hasPendingPayment ? 'A payment for this bill is still being confirmed.' : 'This bill has no balance due.'}
      />
    );
  }
  const direct = selected != null && billing.isDirectUpiOption(selected);
  const gateway = selected != null && billing.isGatewayOption(selected);
  // The demo simulator never applies to real-money UPI.
  const simulated = billing.isSimulated && !direct && !gateway;
  const shown = Currency.format(amount ?? payable);
  const describe = (option: PaymentOption) =>
    option === 'upi' && billing.isDirectUpiOption(option)
      ? `Pay ${billing.upiSettings.payeeName} directly`
      : option === 'upi'
        ? 'Google Pay, PhonePe, Paytm or any UPI app'
        : paymentOptionInfo[option].description;
  const details = (option: PaymentOption): ReactNode =>
    option === 'upi' ? (
      <p className="t-caption">
        {billing.isDirectUpiOption(option)
          ? onPhone()
            ? `Next you copy the restaurant’s UPI ID and pay ${shown} in your own UPI app; a QR code is shown too.`
            : `A QR code with ${shown} filled in appears next. Scan it with your phone’s UPI app.`
          : billing.isGatewayOption(option)
            ? onPhone()
              ? `Next your phone offers its UPI apps, with ${shown} filled in.`
              : `This device cannot open a UPI app: a QR code with ${shown} filled in appears next.`
            : `Pay ${shown} by UPI.`}
      </p>
    ) : option === 'scanAndPay' ? (
      <p className="t-caption">A QR code with {shown} filled in appears next. Scan it with any UPI app, on this phone or another.</p>
    ) : null;

  return (
    <div className="stack-lg">
      {simulated && (
        <FadeIn>
          <div className="notice tone-info">
            <FlaskConical size={iconSize.lg} />
            <span className="grow">Demo payment: nothing will be charged. Use it to try the payment flow.</span>
            <DemoTag />
          </div>
        </FadeIn>
      )}
      <FadeIn index={1}>
        <AmountHeader invoice={invoice} amount={amount ?? payable} />
      </FadeIn>
      {billing.allowPartialPayments ? (
        <section className="stack-sm">
          <h2 className="t-section">Amount</h2>
          <div className="row" style={{ gap: 12 }} role="radiogroup" aria-label="Amount">
            {[true, false].map((full) => (
              <motion.button
                key={String(full)}
                type="button"
                role="radio"
                aria-checked={payFull === full}
                className={`amount-choice ${payFull === full ? 'is-selected' : ''}`}
                whileTap={{ scale: 0.97 }}
                onClick={() => onPayFull(full)}
              >
                <span className="t-card-title">{full ? 'Full balance' : 'Part payment'}</span>
                <span className="t-caption">{full ? Currency.format(payable) : 'Pay the rest later'}</span>
              </motion.button>
            ))}
          </div>
          <AnimatePresence initial={false}>
            {!payFull && (
              <motion.label key="amount" className="field" variants={collapse} initial="hidden" animate="shown" exit="exit" style={{ overflow: 'hidden' }}>
                <span className="visually-hidden">Amount to pay</span>
                <div className="input-wrap">
                  <span className="input-wrap__prefix">{Currency.symbol}</span>
                  <input
                    className="input"
                    inputMode="decimal"
                    value={amountText}
                    onChange={(e) => onAmountText(e.target.value)}
                    placeholder={`Amount (up to ${Currency.format(payable)})`}
                    aria-invalid={amountError != null}
                    style={{ paddingLeft: 34 }}
                  />
                </div>
              </motion.label>
            )}
          </AnimatePresence>
        </section>
      ) : null}
      {amountError && (
        <p className="field__error" role="alert">
          {amountError}
        </p>
      )}
      <section className="stack-sm" aria-label="Payment options">
        <h2 className="t-section">Choose how to pay</h2>
        {!billing.onlinePaymentsAvailable && (
          <p className="t-caption">Online payment is not available right now. Pay in cash or at the counter; staff record it and this bill updates.</p>
        )}
        <div className="stack-sm" role="radiogroup" aria-label="Payment method">
          {billing.paymentOptions.map((option, index) => {
            const isSelected = option === selected;
            const demo = billing.isSimulated && isOnlineOption(option) && !billing.isDirectUpiOption(option) && !billing.isGatewayOption(option);
            const more = details(option);
            return (
              <FadeIn key={option} index={index}>
                <div className={`option ${isSelected ? 'is-selected' : ''}`}>
                  <motion.button type="button" role="radio" aria-checked={isSelected} className="option__main" whileTap={{ scale: 0.985 }} onClick={() => onSelect(option)} data-testid={`option-${option}`}>
                    <span className={`option-icon ${isSelected ? 'is-selected' : ''}`}>{optionIcon[option]}</span>
                    <span className="grow col" style={{ textAlign: 'left' }}>
                      <span className="row" style={{ gap: 8 }}>
                        <span className="t-card-title">{paymentOptionInfo[option].label}</span>
                        {demo && <DemoTag />}
                      </span>
                      <span className="t-caption">{describe(option)}</span>
                    </span>
                    <span className={`radio ${isSelected ? 'is-checked' : ''}`} aria-hidden />
                  </motion.button>
                  <AnimatePresence initial={false}>
                    {isSelected && more && (
                      <motion.div key="more" variants={collapse} initial="hidden" animate="shown" exit="exit" style={{ overflow: 'hidden' }}>
                        <div className="option__more">{more}</div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                </div>
              </FadeIn>
            );
          })}
        </div>
        {billing.canSplit && (
          <motion.button type="button" className="split-card" whileTap={{ scale: 0.98 }} onClick={() => navigate(paths.split(invoice.id), { replace: true })}>
            <span className="option-icon" style={{ background: 'var(--orange-soft)', color: 'var(--orange-text)' }}>
              <Split size={iconSize.lg} />
            </span>
            <span className="grow col" style={{ textAlign: 'left' }}>
              <span className="t-card-title">Split payment</span>
              <span className="t-caption">Pay with two or more methods, e.g. cash + UPI</span>
            </span>
            <ChevronRight size={iconSize.lg} color="var(--text-muted)" />
          </motion.button>
        )}
      </section>
      <p className="t-caption t-center">
        {gateway
          ? `Secured by ${billing.providerName}. Your bill updates by itself once ${billing.providerName} confirms the payment; there is nothing to show the staff.`
          : direct
            ? `You pay ${billing.upiSettings.payeeName} directly from your own UPI app. The bill is marked paid only after the restaurant confirms the money arrived.`
            : simulated
              ? 'Demo mode: payments are simulated by DineQR and never reach a bank. No money is charged, and every payment is labelled as a demo.'
              : `Payments are processed by ${billing.providerName}. The bill updates only after the payment is verified.`}
      </p>
    </div>
  );
}

function Result({
  success = false,
  title,
  message,
  invoice,
  transaction,
  primary,
  secondary,
}: {
  success?: boolean;
  title: string;
  message?: string | null;
  invoice: Invoice;
  transaction: PaymentTransaction | null;
  primary: [string, () => void];
  secondary: [string, () => void];
}) {
  const t = transaction;
  return (
    <div className="result">
      <div className="center">{success ? <SuccessEmblem size={emblemSize.md} label={title} /> : <IconHalo><CircleAlert size={iconSize.hero} /></IconHalo>}</div>
      <h2 className="t-headline t-center" data-testid="payment-result">
        {title}
      </h2>
      {message && <p className="t-secondary t-center">{message}</p>}
      {success && t && (
        <>
          <p className="t-secondary t-center">
            {Currency.format(t.amount)} paid by {t.methodLabel}
          </p>
          <Card>
            {t.isSimulated && (
              <div style={{ marginBottom: 8 }}>
                <DemoTag label="DEMO PAYMENT" />
              </div>
            )}
            <Fact label={t.isSimulated ? 'Demo transaction ref' : 'Reference'} value={t.reference || '—'} />
            <Fact label="Method" value={t.methodLabel} />
            <Fact label="Amount" value={Currency.format(t.amount)} />
            <Fact label="Bill" value={invoice.billNumber} />
            <Fact label="Paid at" value={AppFormat.dateTime(t.updatedAt)} />
            <Fact label="Balance due" value={Currency.format(invoice.outstanding)} />
            {t.isSimulated && (
              <p className="t-caption t-info" style={{ marginTop: 8 }}>
                Simulated demo payment, not verified by any bank or payment provider. No money was charged or transferred.
              </p>
            )}
          </Card>
        </>
      )}
      <div className="center">
        <PaymentStatusBadge status={invoice.status} />
      </div>
      <div className="stack-md">
        <Button block onClick={primary[1]}>
          {primary[0]}
        </Button>
        <Button variant="secondary" block onClick={secondary[1]}>
          {secondary[0]}
        </Button>
      </div>
    </div>
  );
}

function CounterResult({ invoice, simulated, onDone, onPayOnline }: { invoice: Invoice; simulated: boolean; onDone: () => void; onPayOnline: (() => void) | null }) {
  const request = invoice.openCounterRequest;
  const cash = request?.kind === 'cash';
  const amount = Currency.format(request?.amount ?? invoice.payableNow);
  return (
    <div className="result">
      <div className="center">
        <IconHalo>{cash ? <Banknote size={iconSize.hero} /> : <Store size={iconSize.hero} />}</IconHalo>
      </div>
      <h2 className="t-headline t-center" data-testid="counter-result">
        {cash ? `Pay ${amount} in cash` : `Pay ${amount} at the counter`}
      </h2>
      <p className="t-secondary t-center">
        {cash ? 'Hand the cash to your server or pay at the counter. Staff have been told.' : 'Pay at the counter by any method they take. Staff have been told.'}
      </p>
      <Card>
        <Fact label="Bill" value={invoice.billNumber} />
        <Fact label="To pay at the counter" value={amount} />
        <Fact label="Status" value={<PaymentStatusBadge status={invoice.status} />} />
        <p className="t-caption" style={{ marginTop: 8 }}>
          Nothing has been paid yet. The bill updates here as soon as the cashier records your payment.
          {simulated ? ' In demo mode their record is a demo payment too.' : ''}
        </p>
      </Card>
      <div className="stack-md">
        <Button block onClick={onDone}>
          Back to bill
        </Button>
        {onPayOnline && (
          <Button variant="secondary" block onClick={onPayOnline}>
            Pay online instead
          </Button>
        )}
      </div>
    </div>
  );
}
