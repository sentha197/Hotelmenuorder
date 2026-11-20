import { FileText, Hourglass, Printer, ReceiptText, SearchX, Store, Undo2, Wallet } from 'lucide-react';
import { motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router';
import { InvoiceView, PaymentStatusBadge } from '@/components/domain/Domain';
import { Tag } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { ANIMATED_ENTRIES, cn } from '@/components/ui/cn';
import { FilterChips, SearchField, Select, TextField } from '@/components/ui/Form';
import { Dialog } from '@/components/ui/Dialog';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { MetricCard, MetricGrid } from '@/components/ui/Metric';
import { Page } from '@/components/ui/Page';
import { counterMethods, invoiceStatusLabel, paymentMethodLabel, paymentMethods, type Invoice, type PaymentMethodType, type PaymentTransaction } from '@/core/billing';
import { Currency, parseRupees, sumPaise, type Paise } from '@/core/money';
import { AppFormat, DateRanges, rangePresetLabel, type RangePreset } from '@/core/time';
import { recordCounterPayment, refundPayment } from '@/state/actions';
import { useBills } from '@/state/data';
import { useAction } from '@/state/run';
import { useAccess } from '@/state/session';

type BillFilter = 'all' | 'unpaid' | 'partial' | 'paid' | 'refunded' | 'voided';
const billFilters: BillFilter[] = ['all', 'unpaid', 'partial', 'paid', 'refunded', 'voided'];
const billFilterLabel: Record<BillFilter, string> = {
  all: 'All',
  unpaid: 'Unpaid',
  partial: 'Partially paid',
  paid: 'Paid',
  refunded: 'Refunded',
  voided: 'Void',
};

function matchesFilter(f: BillFilter, i: Invoice): boolean {
  switch (f) {
    case 'all':
      return true;
    // Still to be collected at the billing counter.
    case 'unpaid':
      return i.status === 'unpaid' || i.status === 'failed' || i.status === 'pending';
    case 'partial':
      return i.status === 'partiallyPaid';
    case 'paid':
      return i.status === 'paid';
    case 'refunded':
      return i.status === 'refunded' || i.status === 'partiallyRefunded' || i.refundDue;
    case 'voided':
      return i.isVoid;
  }
}

const PAGE = 100;

/** All bills with filters and totals (AdminBillsScreen). Guests pay at the billing counter. */
export function BillsPage() {
  const query = useBills();
  const bills = query.data ?? [];
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
    <Page title="Bills" subtitle="Payments taken at the billing counter">
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
  return (
    <motion.button
      type="button"
      // Only rows on screen animate in; the rest appear in place.
      initial={index < ANIMATED_ENTRIES ? { opacity: 0, y: 8 } : false}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: Math.min(index, 12) * 0.025 }}
      onClick={() => navigate(`/bills/${encodeURIComponent(invoice.id)}`)}
      className={cn('panel list-item-lazy flex w-full flex-col gap-3 p-4 text-left transition-[border-color,transform] hover:-translate-y-0.5 hover:border-line-strong', invoice.refundDue && 'border-info/45')}
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
 * One bill for staff: the invoice, payments taken at the billing counter,
 * refunds and the receipt (AdminBillDetailScreen).
 */
export function BillDetailPage() {
  const { invoiceId = '' } = useParams();
  const navigate = useNavigate();
  const { can } = useAccess();
  const query = useBills();
  const invoice = (query.data ?? []).find((i) => i.id === invoiceId);
  const [recording, setRecording] = useState(false);
  const [refunding, setRefunding] = useState<PaymentTransaction | null>(null);

  if (query.isPending) return <Page title="Bill" back="/bills"><PageSkeleton rows={3} /></Page>;
  if (!invoice) {
    return (
      <Page title="Bill" back="/bills">
        <Empty icon={SearchX} title="Bill not found" message="It may be older than 90 days, or it was removed." />
      </Page>
    );
  }
  const canCollect = can('collectPayments') && invoice.payableNow !== 0;
  const canRefund = can('issueRefunds');
  const receipt = () => navigate(`/bills/${encodeURIComponent(invoice.id)}/receipt`);

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
      {canCollect && (
        <div className="flex flex-wrap gap-2">
          <Button variant="primary" icon={Store} onClick={() => setRecording(true)}>
            Record payment
          </Button>
        </div>
      )}
      <InvoiceView
        invoice={invoice}
        paymentActions={(payment) => {
          // Online payments from before they were retired are refunded at the gateway.
          if (!canRefund || payment.isGateway || invoice.refundableOn(payment.id) === 0) return null;
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
    </Page>
  );
}

/** For money taken at the billing counter (_RecordPaymentDialog). */
function RecordPaymentDialog({ open, invoice, onClose, onRecorded }: { open: boolean; invoice: Invoice; onClose: () => void; onRecorded: () => void }) {
  const max = invoice.payableNow;
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState<PaymentMethodType>('cash');
  const [reference, setReference] = useState('');
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  const [lastOpen, setLastOpen] = useState(false);
  if (open !== lastOpen) {
    setLastOpen(open);
    if (open) {
      setAmount(Currency.plain(max));
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
      description={`For money taken at the billing counter. Balance due: ${Currency.format(max)}.`}
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
          {counterMethods.map((m) => (
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
        ) : (
          <p className="text-[12.5px] text-muted">Return the money at the counter (card terminal or your own UPI app); this records it.</p>
        )}
        <TextField label="Refund amount" inputMode="decimal" prefix={Currency.symbol} value={amount} error={error} onChange={(e) => (setAmount(e.target.value), setError(null))} />
        <TextField label="Reason" maxLength={120} showCount value={reason} onChange={(e) => (setReason(e.target.value), setError(null))} />
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
