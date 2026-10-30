import { CheckCircle2, Circle, CircleAlert, Lock, Plus, Split, Store, Trash2 } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useState } from 'react';
import { useNavigate, useParams } from 'react-router';
import { PaymentStatusBadge } from '../components/badges';
import { DemoCheckoutSheet, type DemoCheckoutResult } from '../components/DemoCheckout';
import { AppBar, Button, Card, DemoTag, EmptyState, IconButton, IconHalo, SuccessEmblem } from '../components/ui';
import { isOnlineOption, paymentOptionInfo, SplitPlan, type Invoice, type PaymentOption, type PaymentTransaction } from '../core/billing';
import { Currency, sum, type Paise } from '../core/money';
import { randomId } from '../core/time';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { emblemSize, iconSize } from '../components/sizes';

type PartStatus = 'planned' | 'paid' | 'failed' | 'atCounter';

interface Part {
  id: string;
  option: PaymentOption;
  amountText: string;
  status: PartStatus;
  /** Kept when a result never arrived (a retry replays it); new after a final failure. */
  key: string;
  payment: PaymentTransaction | null;
  message: string | null;
}

const newPart = (option: PaymentOption, amount: Paise): Part => ({
  id: randomId(6),
  option,
  amountText: Currency.plain(amount),
  status: 'planned',
  key: randomId(),
  payment: null,
  message: null,
});

const done = (p: Part) => p.status === 'paid' || p.status === 'atCounter';

/**
 * Splits a bill across options, e.g. part by card and the rest in cash.
 * Online parts are paid one by one; at most one part is left for the
 * counter, and staff are told once the online parts went through.
 */
export function SplitPaymentPage() {
  const { billing } = useApp();
  useStore(billing);
  const { invoiceId = '' } = useParams();
  const invoice = billing.byId(invoiceId);
  if (!invoice) {
    return (
      <div>
        <AppBar title="Split payment" />
        <EmptyState icon={<CircleAlert size={iconSize.hero} />} title="Bill not found" message="This bill is not available in this session." />
      </div>
    );
  }
  return <Splitter invoice={invoice} />;
}

function Splitter({ invoice }: { invoice: Invoice }) {
  const { billing } = useApp();
  const navigate = useNavigate();
  const [parts, setParts] = useState<Part[]>(() => {
    const due = invoice.payableNow;
    const online = billing.splitOptions.find(isOnlineOption) ?? 'card';
    // Half online (whole rupees), the rest in cash.
    const half = Math.floor(due / 200) * 100;
    return [newPart(online, half), newPart('cash', due - half)];
  });
  const [started, setStarted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [demo, setDemo] = useState<Part | null>(null);

  const value = (p: Part) => Currency.parse(p.amountText);
  const plan = parts.every((p) => value(p) != null) ? parts.map((p) => ({ option: p.option, amount: value(p)! })) : null;
  const problem = plan == null ? 'Enter an amount for every part, e.g. 250.50.' : SplitPlan.validate(plan, invoice.payableNow, new Set(billing.splitOptions), billing.allowPartialPayments);
  const assigned = plan ? sum(plan.map((p) => p.amount)) : null;
  const next = parts.find((p) => isOnlineOption(p.option) && !done(p)) ?? parts.find((p) => !isOnlineOption(p.option) && !done(p)) ?? null;

  const update = (id: string, change: Partial<Part>) => setParts((list) => list.map((p) => (p.id === id ? { ...p, ...change } : p)));

  /** Keeps the last part covering whatever the others leave. */
  const rebalance = (list: Part[]): Part[] => {
    const others = sum(list.slice(0, -1).map((p) => value(p) ?? 0));
    const rest = invoice.payableNow - others;
    if (rest < 0) return list;
    return list.map((p, i) => (i === list.length - 1 ? { ...p, amountText: Currency.plain(rest) } : p));
  };

  const payOnline = async (part: Part, checkout: DemoCheckoutResult) => {
    setBusy(true);
    try {
      const payment = await billing.payOnline({
        invoiceId: invoice.id,
        amount: value(part)!,
        method: paymentOptionInfo[part.option].method!,
        methodDetail: checkout.detail,
        idempotencyKey: part.key,
        outcome: checkout.outcome,
      });
      if (payment.status === 'succeeded') update(part.id, { status: 'paid', payment, message: null });
      else
        update(part.id, {
          status: 'failed',
          payment,
          message: payment.status === 'cancelled' ? 'Cancelled. Nothing was charged.' : payment.failureReason || 'Declined. Nothing was charged.',
          // A final result: trying again is a new payment.
          key: randomId(),
        });
    } catch (error) {
      update(part.id, { status: 'failed', message: error instanceof Error ? error.message : 'Please try again.' });
    } finally {
      setBusy(false);
    }
  };

  const payNext = async () => {
    if (!next || busy) return;
    if (isOnlineOption(next.option)) {
      if (billing.isSimulated) setDemo(next);
      else await payOnline(next, { outcome: 'success', detail: paymentOptionInfo[next.option].detail });
      return;
    }
    setBusy(true);
    try {
      await billing.requestCounterPayment(invoice.id, paymentOptionInfo[next.option].counter!, value(next));
      update(next.id, { status: 'atCounter', message: null });
    } catch (error) {
      update(next.id, { status: 'failed', message: error instanceof Error ? error.message : 'Please try again.' });
    } finally {
      setBusy(false);
    }
  };

  const counter = parts.find((p) => !isOnlineOption(p.option));
  const label = !next
    ? 'Back to bill'
    : isOnlineOption(next.option)
      ? `${next.status === 'failed' ? 'Retry' : 'Pay'} part ${parts.indexOf(next) + 1}: ${Currency.format(value(next) ?? 0)} by ${paymentOptionInfo[next.option].label}`
      : next.option === 'cash'
        ? `Pay ${Currency.format(value(next) ?? 0)} in cash at the counter`
        : `Pay ${Currency.format(value(next) ?? 0)} at the counter`;

  return (
    <div className="with-bottom-bar">
      <AppBar title="Split payment" back={!busy} />
      <div className="page page--narrow stack-lg">
        <Card>
          <div className="row">
            <Split size={iconSize.lg} color="var(--accent-text)" />
            <div className="grow col">
              <span className="t-card-title">Balance due {Currency.format(invoice.payableNow)}</span>
              <span className="t-caption">
                Bill {invoice.billNumber} · {invoice.tableLabel}
              </span>
            </div>
            {billing.isSimulated && <DemoTag />}
          </div>
        </Card>
        {!started ? (
          <>
            <AnimatePresence initial={false}>
              {parts.map((part, index) => (
                <motion.div key={part.id} layout initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, height: 0 }}>
                  <Card>
                    <div className="row">
                      <span className="t-card-title grow">Part {index + 1}</span>
                      {parts.length > 2 && (
                        <IconButton label={`Remove part ${index + 1}`} onClick={() => setParts((list) => rebalance(list.filter((p) => p.id !== part.id)))}>
                          <Trash2 size={iconSize.md} />
                        </IconButton>
                      )}
                    </div>
                    <div className="split-fields">
                      <label className="field">
                        <span className="field__label">Method</span>
                        <select className="input" value={part.option} onChange={(e) => update(part.id, { option: e.target.value as PaymentOption })}>
                          {billing.splitOptions.map((option) => (
                            <option key={option} value={option}>
                              {paymentOptionInfo[option].label}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className="field">
                        <span className="field__label">Amount</span>
                        <div className="input-wrap">
                          <span className="input-wrap__prefix">{Currency.symbol}</span>
                          <input
                            className="input"
                            inputMode="decimal"
                            value={part.amountText}
                            style={{ paddingLeft: 34 }}
                            onChange={(e) =>
                              setParts((list) => {
                                const next = list.map((p) => (p.id === part.id ? { ...p, amountText: e.target.value } : p));
                                return index === list.length - 1 ? next : rebalance(next);
                              })
                            }
                          />
                        </div>
                      </label>
                    </div>
                  </Card>
                </motion.div>
              ))}
            </AnimatePresence>
            {parts.length < SplitPlan.maxParts && (
              <Button
                variant="ghost"
                icon={<Plus size={iconSize.md} />}
                onClick={() =>
                  setParts((list) => {
                    const used = new Set(list.map((p) => p.option));
                    const option = billing.splitOptions.find((o) => isOnlineOption(o) && !used.has(o)) ?? billing.splitOptions[0] ?? 'card';
                    return [...list.slice(0, -1), newPart(option, 0), list[list.length - 1]!];
                  })
                }
              >
                Add a method
              </Button>
            )}
            <p className="t-label t-strong">
              Assigned {assigned == null ? '—' : Currency.format(assigned)} of {Currency.format(invoice.payableNow)}
            </p>
            {problem && <p className="t-caption t-error">{problem}</p>}
            <p className="t-caption">Online parts are paid first, one by one. A cash or counter part is paid at the counter afterwards; the bill updates when staff record it.</p>
          </>
        ) : (
          <>
            {parts.map((part, index) => (
              <PartProgress key={part.id} number={index + 1} part={part} amount={value(part) ?? 0} />
            ))}
            {!next && (
              <div className="result">
                <div className="center">{invoice.status === 'paid' ? <SuccessEmblem size={emblemSize.md} label="Bill paid" /> : <IconHalo><Store size={iconSize.hero} /></IconHalo>}</div>
                <h2 className="t-headline t-center">{invoice.status === 'paid' ? 'Bill paid in full' : 'Online parts paid'}</h2>
                <p className="t-secondary t-center">
                  {counter
                    ? `Please pay ${Currency.format(value(counter) ?? 0)} ${counter.option === 'cash' ? 'in cash ' : ''}at the counter. Staff have been told, and the bill updates when they record it.`
                    : 'Every part went through.'}
                </p>
              </div>
            )}
            <div className="center">
              <PaymentStatusBadge status={invoice.status} />
            </div>
          </>
        )}
      </div>
      <div className="bottom-bar">
        <div className="bottom-bar__inner">
          {!started ? (
            <Button
              block
              icon={<Split size={iconSize.lg} />}
              disabled={problem != null}
              onClick={() => {
                // Online parts first (in the guest's order), the counter part last.
                setParts((list) => [...list.filter((p) => isOnlineOption(p.option)), ...list.filter((p) => !isOnlineOption(p.option))]);
                setStarted(true);
              }}
            >
              Start split payment
            </Button>
          ) : (
            <Button
              block
              loading={busy}
              icon={next ? isOnlineOption(next.option) ? <Lock size={iconSize.md} /> : <Store size={iconSize.lg} /> : undefined}
              onClick={() => (next ? void payNext() : navigate(paths.bill(invoice.id), { replace: true }))}
            >
              {label}
            </Button>
          )}
        </div>
      </div>
      {demo && (
        <DemoCheckoutSheet
          open
          option={demo.option}
          amount={value(demo) ?? 0}
          invoice={invoice}
          onDone={(checkout) => {
            const part = demo;
            setDemo(null);
            if (checkout) void payOnline(part, checkout);
          }}
        />
      )}
    </div>
  );
}

function PartProgress({ number, part, amount }: { number: number; part: Part; amount: Paise }) {
  const [color, label, icon] =
    part.status === 'paid'
      ? ['var(--success)', part.payment?.isSimulated ? 'Paid (demo)' : 'Paid', <CheckCircle2 size={iconSize.lg} key="i" />]
      : part.status === 'failed'
        ? ['var(--error)', 'Not paid', <CircleAlert size={iconSize.lg} key="i" />]
        : part.status === 'atCounter'
          ? ['var(--info)', 'Pay at the counter', <Store size={iconSize.lg} key="i" />]
          : ['var(--text-secondary)', 'To pay', <Circle size={iconSize.lg} key="i" />];
  const reference = part.payment?.reference ?? '';
  return (
    <motion.div layout>
      <Card>
        <div className="row-top">
          <div className="grow col">
            <span className="t-card-title">
              Part {number} · {part.payment?.methodLabel ?? paymentOptionInfo[part.option].label}
            </span>
            <span className="t-caption" style={{ color }}>
              {[Currency.format(amount), label, ...(part.status === 'paid' && reference ? [`Ref ${reference}`] : [])].join(' · ')}
            </span>
            {part.message && <span className="t-caption">{part.message}</span>}
          </div>
          <span style={{ color }}>{icon}</span>
        </div>
      </Card>
    </motion.div>
  );
}
