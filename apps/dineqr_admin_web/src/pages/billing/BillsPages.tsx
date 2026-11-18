import { Banknote, FileText, Hourglass, Printer, ReceiptText, RefreshCw, SearchX, ShieldCheck, Store, Undo2, Wallet, Ban, CircleCheck } from 'lucide-react';
import { motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router';
import { InvoiceView, PaymentStatusBadge } from '@/components/domain/Domain';
import { Tag } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { cn } from '@/components/ui/cn';
import { Checkbox, FilterChips, SearchField, Select, TextField } from '@/components/ui/Form';
import { Dialog, confirmDialog } from '@/components/ui/Dialog';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { MetricCard, MetricGrid } from '@/components/ui/Metric';
import { Page } from '@/components/ui/Page';
import { awaitsUpiVerification, invoiceStatusLabel, paymentMethodLabel, paymentMethods, type CounterRequest, type Invoice, type PaymentMethodType, type PaymentTransaction } from '@/core/billing';
import { Currency, parseRupees, sumPaise, type Paise } from '@/core/money';
import { AppFormat, DateRanges, rangePresetLabel, type RangePreset } from '@/core/time';
import { Upi, UpiReference } from '@/core/upi';
import { cancelUpiPayment, reconcileBill, recordCounterPayment, refundPayment, rejectUpiPayment, verifyUpiPayment } from '@/state/actions';
import { useBills, usePaymentConfig, usePaymentSettings } from '@/state/data';
import { runAction, useAction } from '@/state/run';
import { useAccess } from '@/state/session';

type BillFilter = 'all' | 'counter' | 'unpaid' | 'partial' | 'paid' | 'pending' | 'failed' | 'refunded' | 'voided';
const billFilters: BillFilter[] = ['all', 'counter', 'unpaid', 'partial', 'paid', 'pending', 'failed', 'refunded', 'voided'];
const billFilterLabel: Record<BillFilter, string> = {
  all: 'All',
  counter: 'At the counter',
  unpaid: 'Unpaid',
  partial: 'Partially paid',
  paid: 'Paid',
  pending: 'Pending',
  failed: 'Failed',
  refunded: 'Refunded',
  voided: 'Void',
};

function matchesFilter(f: BillFilter, i: Invoice): boolean {
  switch (f) {
    case 'all':
      return true;
    // Guests waiting to pay at the counter.
    case 'counter':
      return i.openCounterRequest != null;
    case 'unpaid':
      return i.status === 'unpaid';
    case 'partial':
      return i.status === 'partiallyPaid';
    case 'paid':
      return i.status === 'paid';
    case 'pending':
      return i.status === 'pending';
    case 'failed':
      return i.status === 'failed' || i.payments.some((p) => p.status === 'failed');
    case 'refunded':
      return i.status === 'refunded' || i.status === 'partiallyRefunded' || i.refundDue;
    case 'voided':
      return i.isVoid;
  }
}

const PAGE = 100;

/** All bills with filters, totals and reconciliation (AdminBillsScreen). */
export function BillsPage() {
  const query = useBills();
  const bills = query.data ?? [];
  const gateway = usePaymentConfig();
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<BillFilter>('all');
  const [period, setPeriod] = useState<RangePreset | null>('last7');
  const [method, setMethod] = useState<PaymentMethodType | null>(null);
  const [limit, setLimit] = useState(PAGE);

  const { scoped, shown } = useMemo(() => {
    const now = new Date();
    const scoped = bills.filter((i) => {
      if (period != null && !DateRanges.contains(DateRanges.preset(period, now), i.createdAt)) return false;
      if (method != null && !i.payments.some((p) => p.method === method && p.status === 'succeeded')) return false;
      const q = search.trim().toLowerCase().replaceAll('#', '');
      if (!q) return true;
      return (
        i.billNumber.toLowerCase().includes(q) ||
        i.orderId.toLowerCase().includes(q) ||
        (i.isTakeaway ? q.length >= 3 && 'takeaway'.startsWith(q.replaceAll(' ', '')) : AppFormat.table(i.tableNumber) === q.padStart(2, '0')) ||
        i.payments.some((p) => p.reference.toLowerCase().includes(q))
      );
    });
    return { scoped, shown: scoped.filter((i) => matchesFilter(status, i)) };
  }, [bills, period, method, search, status]);

  const total = sumPaise(shown.filter((i) => !i.isVoid).map((i) => i.total));
  const collected = sumPaise(shown.map((i) => i.netPaid));
  const due = sumPaise(shown.map((i) => i.outstanding));

  return (
    <Page title="Bills" subtitle={gateway.gatewayAvailable ? `Online payments via ${gateway.providerName}` : 'UPI to the restaurant and payments at the counter'}>
      <MetricGrid min={150}>
        <MetricCard index={0} label="Bills" numeric={shown.length} format={String} icon={FileText} />
        <MetricCard index={1} label="Billed" numeric={total} format={Currency.format} icon={ReceiptText} />
        <MetricCard index={2} label="Collected (net)" numeric={collected} format={Currency.format} icon={Wallet} tone="success" />
        <MetricCard index={3} label="Outstanding" numeric={due} format={Currency.format} icon={Hourglass} tone={due === 0 ? 'muted' : 'brand'} />
      </MetricGrid>
      <SearchField value={search} onChange={setSearch} placeholder="Bill number, order id, table or reference" />
      <div className="flex flex-col gap-2.5">
        <FilterChips name="bills-period" values={['today', 'last7', 'last30', null] as (RangePreset | null)[]} selected={period} labelOf={(p) => (p ? rangePresetLabel[p] : 'All time')} onSelect={setPeriod} />
        <FilterChips name="bills-status" values={billFilters} selected={status} labelOf={(f) => billFilterLabel[f]} countOf={(f) => scoped.filter((i) => matchesFilter(f, i)).length} onSelect={setStatus} />
        <FilterChips name="bills-method" values={[null, ...paymentMethods] as (PaymentMethodType | null)[]} selected={method} labelOf={(m) => (m ? paymentMethodLabel[m] : 'Any method')} onSelect={setMethod} />
      </div>
      {query.isPending ? (
        <PageSkeleton />
      ) : shown.length === 0 ? (
        <Empty icon={FileText} title="No bills match" message="Try another filter or period." />
      ) : (
        <>
          <div className="grid gap-3 lg:grid-cols-2">
            {shown.slice(0, limit).map((i, index) => (
              <BillRow key={i.id} invoice={i} index={index} />
            ))}
          </div>
          {shown.length > limit && (
            <div className="flex justify-center">
              <Button onClick={() => setLimit((l) => l + PAGE)}>Show more ({shown.length - limit} left)</Button>
            </div>
          )}
        </>
      )}
    </Page>
  );
}

function BillRow({ invoice, index }: { invoice: Invoice; index: number }) {
  const navigate = useNavigate();
  const last = invoice.latestSuccessfulPayment;
  const request = invoice.openCounterRequest;
  return (
    <motion.button
      type="button"
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: Math.min(index, 12) * 0.025 }}
      onClick={() => navigate(`/bills/${encodeURIComponent(invoice.id)}`)}
      className={cn('panel flex w-full flex-col gap-3 p-4 text-left transition-[border-color,transform] hover:-translate-y-0.5 hover:border-line-strong', (invoice.hasPendingPayment || invoice.refundDue) && 'border-info/45')}
    >
      <div className="flex w-full items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="flex flex-wrap items-center gap-1.5 text-[14px] font-semibold text-ink">
            {invoice.billNumber}
            {invoice.isDemoSample && <Tag>Sample</Tag>}
          </p>
          <p className="truncate text-[12px] text-faint">
            {AppFormat.orderNumber(invoice.orderId)} · {invoice.tableLabel} · {AppFormat.dateTime(invoice.createdAt)}
          </p>
        </div>
        <PaymentStatusBadge status={invoice.status} />
      </div>
      <div className="flex flex-wrap gap-x-6 gap-y-1">
        <Amount label="Total" value={invoice.total} />
        <Amount label="Paid" value={invoice.amountPaid} className="text-success" />
        {invoice.amountRefunded !== 0 && <Amount label="Refunded" value={invoice.amountRefunded} className="text-warning" />}
        <Amount label="Due" value={invoice.outstanding} className={invoice.outstanding === 0 ? 'text-muted' : 'text-brand-text'} />
      </div>
      {last && <p className="text-[12px] text-faint">{[last.methodLabel, ...(last.reference ? [`Ref ${last.reference}`] : []), ...(last.isSimulated ? ['test payment'] : [])].join(' · ')}</p>}
      {request && (
        <p className="text-[12px] font-semibold text-info">
          Guest will pay {Currency.format(request.amount)} {request.kind === 'cash' ? 'in cash' : 'at the counter'}
        </p>
      )}
      {invoice.refundDue && <p className="text-[12px] text-info">Order cancelled after payment: refund due</p>}
    </motion.button>
  );
}

function Amount({ label, value, className }: { label: string; value: Paise; className?: string }) {
  return (
    <div>
      <p className="text-[11px] text-faint">{label}</p>
      <p className={cn('text-[13.5px] font-bold tabular text-ink', className)}>{Currency.format(value)}</p>
    </div>
  );
}

/**
 * One bill for staff: the invoice, counter payments, UPI payments waiting for
 * confirmation, refunds, reconciliation and the receipt (AdminBillDetailScreen).
 */
export function BillDetailPage() {
  const { invoiceId = '' } = useParams();
  const navigate = useNavigate();
  const { can } = useAccess();
  const query = useBills();
  const invoice = (query.data ?? []).find((i) => i.id === invoiceId);
  const [recording, setRecording] = useState(false);
  const [refunding, setRefunding] = useState<PaymentTransaction | null>(null);
  const [confirming, setConfirming] = useState<PaymentTransaction | null>(null);
  const [rejecting, setRejecting] = useState<PaymentTransaction | null>(null);
  const reconcile = useAction();

  if (query.isPending) return <Page title="Bill" back="/bills"><PageSkeleton rows={3} /></Page>;
  if (!invoice) {
    return (
      <Page title="Bill" back="/bills">
        <Empty icon={SearchX} title="Bill not found" message="It may be older than 90 days, or it was removed." />
      </Page>
    );
  }
  const canCollect = can('collectPayments') && invoice.payableNow !== 0;
  const canReconcile = can('reconcilePayments') && invoice.hasPendingPayment;
  const canRefund = can('issueRefunds');
  const canConfirmUpi = can('collectPayments');
  const receipt = () => navigate(`/bills/${encodeURIComponent(invoice.id)}/receipt`);

  const runReconcile = () => reconcile.run(() => reconcileBill(invoice), { success: 'Pending payments checked' });

  const cancelUpi = async (payment: PaymentTransaction) => {
    const ok = await confirmDialog({
      title: 'Cancel this UPI payment?',
      message: `The guest started paying ${Currency.format(payment.amount)} by UPI but has not said they paid. Cancel it if they decided to pay another way; they can start again.`,
      confirmLabel: 'Cancel payment',
      icon: Ban,
      danger: true,
    });
    if (ok) await runAction(() => cancelUpiPayment(payment), { success: 'UPI payment cancelled' });
  };

  return (
    <Page
      title={invoice.billNumber}
      subtitle={`${AppFormat.orderNumber(invoice.orderId)} · ${invoice.tableLabel} · ${invoiceStatusLabel[invoice.status]}`}
      back="/bills"
      width="narrow"
      actions={
        <Button icon={Printer} onClick={receipt}>
          Receipt
        </Button>
      }
    >
      {invoice.refundDue && <Notice tone="info">The order was cancelled after a payment of {Currency.format(invoice.netPaid)}. Refund it below.</Notice>}
      {invoice.openCounterRequest && <CounterBanner request={invoice.openCounterRequest} onRecord={canCollect ? () => setRecording(true) : undefined} />}
      {(canCollect || canReconcile) && (
        <div className="flex flex-wrap gap-2">
          {canCollect && (
            <Button variant="primary" icon={Store} onClick={() => setRecording(true)}>
              Record payment
            </Button>
          )}
          {canReconcile && (
            <Button icon={RefreshCw} loading={reconcile.pending} onClick={() => void runReconcile()}>
              Reconcile pending
            </Button>
          )}
        </div>
      )}
      <InvoiceView
        invoice={invoice}
        onCheckPending={canReconcile ? () => void runReconcile() : undefined}
        paymentActions={(payment) => {
          // A UPI payment to the restaurant waits for someone to check the money arrived.
          if (canConfirmUpi && awaitsUpiVerification(payment)) {
            return (
              <div className="flex flex-col items-end gap-0.5">
                <button type="button" onClick={() => setConfirming(payment)} className="text-[12.5px] font-bold text-[#b5121b] hover:underline">
                  Confirm
                </button>
                <button type="button" onClick={() => (payment.isClaimed ? setRejecting(payment) : void cancelUpi(payment))} className="text-[12.5px] font-semibold text-[#6b5a5d] hover:underline">
                  {payment.isClaimed ? 'Not received' : 'Cancel'}
                </button>
              </div>
            );
          }
          if (!canRefund || invoice.refundableOn(payment.id) === 0) return null;
          return (
            <button type="button" onClick={() => setRefunding(payment)} className="text-[12.5px] font-bold text-[#b5121b] hover:underline">
              Refund
            </button>
          );
        }}
      />
      <p className="text-center text-[12px] text-faint">No thermal printer connected. Use Receipt to print or save a PDF through the browser.</p>

      <RecordPaymentDialog open={recording} invoice={invoice} onClose={() => setRecording(false)} onRecorded={receipt} />
      <RefundDialog payment={refunding} invoice={invoice} onClose={() => setRefunding(null)} />
      <ConfirmUpiDialog payment={confirming} invoice={invoice} onClose={() => setConfirming(null)} />
      <RejectUpiDialog payment={rejecting} onClose={() => setRejecting(null)} />
    </Page>
  );
}

/** The guest said they will pay at the counter: the cashier collects and records it. */
function CounterBanner({ request, onRecord }: { request: CounterRequest; onRecord?: () => void }) {
  const cash = request.kind === 'cash';
  return (
    <Notice
      tone="info"
      icon={cash ? Banknote : Store}
      action={
        onRecord && (
          <Button size="sm" onClick={onRecord}>
            Record
          </Button>
        )
      }
    >
      Guest will pay {Currency.format(request.amount)} {cash ? 'in cash' : 'at the counter'} (since {AppFormat.time(request.requestedAt)}). Nothing is paid until you record it.
    </Notice>
  );
}

/** For money taken at the counter (_RecordPaymentDialog). */
function RecordPaymentDialog({ open, invoice, onClose, onRecorded }: { open: boolean; invoice: Invoice; onClose: () => void; onRecorded: () => void }) {
  const max = invoice.payableNow;
  const request = invoice.openCounterRequest;
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState<PaymentMethodType>('cash');
  const [reference, setReference] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  const [lastOpen, setLastOpen] = useState(false);
  if (open !== lastOpen) {
    setLastOpen(open);
    if (open) {
      setAmount(Currency.plain(request?.amount ?? max));
      setMethod('cash');
      setReference('');
      setError(null);
    }
  }
  const submit = async () => {
    const value = parseRupees(amount);
    if (value == null || value <= 0) return setError('Enter an amount.');
    if (value > max) return setError(`At most ${Currency.format(max)} is due.`);
    const ok = await run(() => recordCounterPayment(invoice, value, method, reference, method === 'cash' ? '' : 'Counter'), {
      success: `Payment of ${Currency.format(value)} recorded`,
      successAction: { label: 'Receipt', onClick: onRecorded },
    });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Record payment"
      icon={Store}
      description={`For money taken at the counter. Balance due: ${Currency.format(max)}.`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            Record
          </Button>
        </>
      }
    >
      <form
        className="flex flex-col gap-4 pb-2"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        {request && (
          <p className="text-[12.5px] text-muted">
            The guest chose {request.kind === 'cash' ? 'cash at the counter' : 'pay at the counter'} for {Currency.format(request.amount)}.
          </p>
        )}
        <TextField
          label="Amount received"
          inputMode="decimal"
          prefix={Currency.symbol}
          value={amount}
          error={error}
          onChange={(e) => {
            setAmount(e.target.value);
            setError(null);
          }}
        />
        <Select label="Method" value={method} onChange={(e) => setMethod(e.target.value as PaymentMethodType)}>
          {(['cash', 'card', 'upi'] as const).map((m) => (
            <option key={m} value={m}>
              {m === 'cash' ? 'Cash' : `${paymentMethodLabel[m]} (counter terminal)`}
            </option>
          ))}
        </Select>
        <TextField label="Reference (optional)" placeholder="Terminal slip or UPI id" maxLength={40} value={reference} onChange={(e) => setReference(e.target.value)} />
      </form>
    </Dialog>
  );
}

function RefundDialog({ payment, invoice, onClose }: { payment: PaymentTransaction | null; invoice: Invoice; onClose: () => void }) {
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [shown, setShown] = useState<PaymentTransaction | null>(null);
  const { pending, run } = useAction();
  if (payment && payment !== shown) {
    setShown(payment);
    setAmount(Currency.plain(invoice.refundableOn(payment.id)));
    setReason('');
    setError(null);
  }
  const p = payment ?? shown;
  if (!p) return null;
  const max = invoice.refundableOn(p.id);
  const submit = async () => {
    const value = parseRupees(amount);
    if (value == null || value <= 0) return setError('Enter an amount.');
    if (value > max) return setError(`At most ${Currency.format(max)} can be refunded.`);
    if (reason.trim().length < 3) return setError('Enter a reason.');
    const ok = await run(() => refundPayment(invoice, p, value, reason), { success: p.isSimulated ? 'Test refund recorded (no money moved)' : 'Refund recorded' });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={payment != null}
      onClose={onClose}
      title="Refund payment"
      icon={Undo2}
      description={`${paymentMethodLabel[p.method]} payment of ${Currency.format(p.amount)}${p.reference ? ` (ref ${p.reference})` : ''}. Refundable: ${Currency.format(max)}.`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            Refund
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 pb-2">
        {p.isSimulated ? (
          <Notice tone="info">Test payment: no money moved, so nothing is sent back. This only records the refund.</Notice>
        ) : p.method === 'cash' ? (
          <p className="text-[12.5px] text-muted">Return the cash at the counter; this records it.</p>
        ) : p.isUpiDirect ? (
          <p className="text-[12.5px] text-muted">This UPI payment went straight to your account. Send the money back from your own UPI app; this only records it.</p>
        ) : null}
        <TextField label="Refund amount" inputMode="decimal" prefix={Currency.symbol} value={amount} error={error} onChange={(e) => (setAmount(e.target.value), setError(null))} />
        <TextField label="Reason" maxLength={120} showCount value={reason} onChange={(e) => (setReason(e.target.value), setError(null))} />
      </div>
    </Dialog>
  );
}

/** Staff confirm that the money arrived, with the bank's UPI transaction ID (ConfirmUpiPaymentDialog). */
function ConfirmUpiDialog({ payment, invoice, onClose }: { payment: PaymentTransaction | null; invoice: Invoice; onClose: () => void }) {
  const upiId = usePaymentSettings().data?.upi.upiId ?? '';
  const [reference, setReference] = useState('');
  const [seen, setSeen] = useState(false);
  const [tried, setTried] = useState(false);
  const [shown, setShown] = useState<PaymentTransaction | null>(null);
  const { pending, run } = useAction();
  if (payment && payment !== shown) {
    setShown(payment);
    setReference(payment.reference);
    setSeen(false);
    setTried(false);
  }
  const p = payment ?? shown;
  if (!p) return null;
  const normalised = UpiReference.normalize(reference);
  const problem = !normalised ? 'Enter the UPI transaction ID from your bank.' : !UpiReference.isValid(normalised) ? UpiReference.rule : null;
  const amount = Currency.format(p.amount);
  const submit = async () => {
    setTried(true);
    if (!seen || problem) return;
    const ok = await run(() => verifyUpiPayment(p, normalised), { success: `Payment of ${amount} confirmed` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={payment != null}
      onClose={onClose}
      title="Confirm UPI payment"
      icon={ShieldCheck}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Back
          </Button>
          <Button variant="primary" icon={CircleCheck} loading={pending} onClick={() => void submit()}>
            Confirm payment
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 pb-2">
        <div>
          <p className="text-[14px] font-semibold text-ink">
            {amount} · Bill {invoice.billNumber} · {invoice.tableLabel}
          </p>
          <p className="text-[12.5px] text-muted">{p.claimedAt ? `The guest says they paid at ${AppFormat.dateTime(p.claimedAt)}.` : 'The guest started this payment but has not said they paid yet.'}</p>
        </div>
        <p className="text-[13px] leading-relaxed text-muted">
          Open your bank or UPI app and look for a credit of {amount}
          {upiId ? ` to ${upiId}` : ''}, usually with the note "{Upi.noteFor(invoice.billNumber, p.id)}". Only confirm once you can see it there: the guest's screen proves nothing.
        </p>
        <TextField
          label="UPI transaction ID"
          autoComplete="off"
          spellCheck={false}
          maxLength={40}
          value={reference}
          onChange={(e) => setReference(e.target.value.replace(/\s/g, '').toUpperCase())}
          hint={p.reference ? 'Typed by the guest. Check it against your statement.' : 'In the credit alert or statement (often 12 digits).'}
          error={tried ? problem : null}
        />
        <Checkbox checked={seen} onChange={setSeen} label={`I can see ${amount} received in our account.`} />
        {tried && !seen && <p className="-mt-2 text-[12px] text-danger">Tick the box once you have checked the credit.</p>}
      </div>
    </Dialog>
  );
}

/** The money did not arrive: the payment fails and the bill is open again (RejectUpiPaymentDialog). */
function RejectUpiDialog({ payment, onClose }: { payment: PaymentTransaction | null; onClose: () => void }) {
  const [reason, setReason] = useState('');
  const [shown, setShown] = useState<PaymentTransaction | null>(null);
  const { pending, run } = useAction();
  if (payment && payment !== shown) {
    setShown(payment);
    setReason('');
  }
  const p = payment ?? shown;
  if (!p) return null;
  const submit = async () => {
    const ok = await run(() => rejectUpiPayment(p, reason), { success: 'Payment rejected. The bill is unpaid again.' });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={payment != null}
      onClose={onClose}
      title="Payment not received?"
      icon={Ban}
      description={`Use this when ${Currency.format(p.amount)} did not reach your account. The bill stays unpaid and the guest can pay again or pay at the counter.`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Back
          </Button>
          <Button variant="danger" loading={pending} onClick={() => void submit()}>
            Reject payment
          </Button>
        </>
      }
    >
      <div className="pb-2">
        <TextField label="Reason (optional)" maxLength={120} value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Dialog>
  );
}

/** The bill as a receipt, ready to print or save as PDF from the browser (ReceiptPreviewScreen). */
export function ReceiptPage() {
  const { invoiceId = '' } = useParams();
  const query = useBills();
  const invoice = (query.data ?? []).find((i) => i.id === invoiceId);
  if (query.isPending) return <Page title="Receipt" back={`/bills/${invoiceId}`}><PageSkeleton rows={3} /></Page>;
  if (!invoice) {
    return (
      <Page title="Receipt" back="/bills">
        <Empty icon={SearchX} title="Bill not found" />
      </Page>
    );
  }
  return (
    <Page
      title={invoice.status === 'paid' ? 'Receipt' : 'Bill'}
      subtitle={`${invoice.billNumber} · print it, or choose "Save as PDF" in the print dialog`}
      back={`/bills/${encodeURIComponent(invoice.id)}`}
      width="narrow"
      actions={
        <Button variant="primary" icon={Printer} onClick={() => window.print()} className="no-print">
          Print / save PDF
        </Button>
      }
    >
      <div className="mx-auto w-full max-w-[640px]">
        <InvoiceView invoice={invoice} />
      </div>
    </Page>
  );
}
