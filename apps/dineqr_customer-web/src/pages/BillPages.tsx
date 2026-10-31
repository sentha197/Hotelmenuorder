import { Banknote, Download, Lock, Printer, ReceiptText, RefreshCw, Share2, Store } from 'lucide-react';
import { useNavigate, useParams } from 'react-router';
import { PaymentStatusBadge } from '../components/badges';
import { methodIcon, InvoiceView } from '../components/invoice';
import { AnimatedMoney } from '../components/money';
import { AppBar, Button, Card, DemoTag, EmptyState, FadeIn, Fact, IconButton } from '../components/ui';
import type { Invoice } from '../core/billing';
import { Currency, sum } from '../core/money';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { PaymentError } from '../services/api';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize } from '../components/sizes';

function BillMissing({ title = 'Bill' }: { title?: string }) {
  return (
    <div>
      <AppBar title={title} />
      <EmptyState icon={<ReceiptText size={iconSize.hero} />} title="Bill not found" message="This bill is not available in this session." />
    </div>
  );
}

/** Asks the server about pending payments and says what it found. */
function useCheckPending(invoiceId: string) {
  const { billing, toasts } = useApp();
  return async () => {
    try {
      await billing.checkPending(invoiceId);
    } catch (error) {
      toasts.show(error instanceof Error ? error.message : 'Could not check the payment.', { tone: 'error' });
      return;
    }
    const invoice = billing.byId(invoiceId);
    const waitingOnRestaurant = invoice?.payments.some((p) => p.isUpiDirect && p.status === 'pending') ?? false;
    toasts.show(
      invoice?.hasPendingPayment
        ? waitingOnRestaurant
          ? 'Still waiting for the restaurant to confirm your payment.'
          : 'Still waiting for confirmation from the payment provider.'
        : 'Payment status updated.',
    );
  };
}

export function BillPage() {
  const { billing, toasts } = useApp();
  useStore(billing);
  const { invoiceId = '' } = useParams();
  const navigate = useNavigate();
  const invoice = billing.byId(invoiceId);
  const checkPending = useCheckPending(invoiceId);
  if (!invoice) return <BillMissing />;
  const cancelRequest = async () => {
    try {
      await billing.cancelCounterRequest(invoice.id);
    } catch (error) {
      toasts.show(error instanceof PaymentError ? error.message : 'Could not cancel. Please try again.', { tone: 'error' });
    }
  };
  return (
    <div className={invoice.outstanding ? 'with-bottom-bar' : undefined}>
      <AppBar
        title={invoice.status === 'paid' ? 'Receipt' : 'Bill'}
        actions={
          <IconButton label="Print, save or share the receipt" onClick={() => navigate(paths.receipt(invoice.id))}>
            <Printer size={iconSize.lg} />
          </IconButton>
        }
      />
      <div className="page page--narrow">
        <FadeIn>
          <InvoiceView invoice={invoice} onCheckPending={() => void checkPending()} />
        </FadeIn>
      </div>
      {invoice.outstanding > 0 && (
        <PayBar invoice={invoice} onPay={() => navigate(paths.pay(invoice.id))} onCheckPending={() => void checkPending()} onCancelRequest={() => void cancelRequest()} />
      )}
    </div>
  );
}

function PayBar({ invoice, onPay, onCheckPending, onCancelRequest }: { invoice: Invoice; onPay: () => void; onCheckPending: () => void; onCancelRequest: () => void }) {
  const upiPending = invoice.latestPending((p) => p.isUpiDirect);
  const gatewayPending = invoice.latestPending((p) => p.isGateway);
  const request = invoice.openCounterRequest;
  return (
    <div className="bottom-bar">
      <div className="bottom-bar__inner">
        {upiPending ? (
          <>
            <p className="t-caption t-info t-center" style={{ marginBottom: 8 }}>
              {upiPending.isClaimed
                ? `Waiting for the restaurant to confirm your UPI payment of ${Currency.format(upiPending.amount)}.`
                : `You started a UPI payment of ${Currency.format(upiPending.amount)}. It is not finished yet.`}
            </p>
            <Button variant="secondary" block onClick={onPay}>
              {upiPending.isClaimed ? 'View payment' : 'Continue UPI payment'}
            </Button>
          </>
        ) : gatewayPending ? (
          <>
            <p className="t-caption t-info t-center" style={{ marginBottom: 8 }}>
              Your UPI payment of {Currency.format(gatewayPending.amount)} is being confirmed. This updates by itself.
            </p>
            <Button variant="secondary" block onClick={onPay}>
              View payment
            </Button>
          </>
        ) : invoice.hasPendingPayment ? (
          <div className="col" style={{ alignItems: 'center' }}>
            <p className="t-caption t-info t-center">A payment is being confirmed. You will not be charged twice.</p>
            <Button variant="ghost" icon={<RefreshCw size={iconSize.md} />} onClick={onCheckPending}>
              Check status
            </Button>
          </div>
        ) : request ? (
          <>
            <div className="row-top t-caption t-info" style={{ marginBottom: 8 }}>
              {request.kind === 'cash' ? <Banknote size={iconSize.lg} /> : <Store size={iconSize.lg} />}
              <span>
                {request.kind === 'cash' ? 'Pay in cash' : 'Pay'} {Currency.format(request.amount)} at the counter. Staff will record your payment and the bill will update here.
              </span>
            </div>
            <div className="row" style={{ gap: 8 }}>
              <Button variant="secondary" compact className="grow" onClick={onPay}>
                Pay another way
              </Button>
              <Button variant="ghost" onClick={onCancelRequest}>
                Cancel
              </Button>
            </div>
          </>
        ) : (
          <Button block icon={<Lock size={iconSize.md} />} onClick={onPay} data-testid="pay-now">
            Pay Now · {Currency.format(invoice.outstanding)}
          </Button>
        )}
      </div>
    </div>
  );
}

/** The receipt, ready for the browser's print dialog (Save as PDF works too). */
export function ReceiptPage() {
  const { billing, toasts } = useApp();
  useStore(billing);
  const { invoiceId = '' } = useParams();
  const invoice = billing.byId(invoiceId);
  if (!invoice) return <BillMissing title="Receipt" />;

  const share = async () => {
    const text = [
      `${invoice.restaurant.name} · ${invoice.status === 'paid' ? 'Receipt' : 'Bill'} ${invoice.billNumber}`,
      `${invoice.tableLabel} · ${AppFormat.dateTime(invoice.createdAt)}`,
      ...invoice.lines.map((l) => `${l.quantity} × ${l.name} — ${Currency.format(l.unitPrice * l.quantity)}`),
      `Total ${Currency.format(invoice.total)} · Paid ${Currency.format(invoice.amountPaid)} · Due ${Currency.format(invoice.outstanding)}`,
      ...(invoice.demoNotice ? [invoice.demoNotice] : []),
    ].join('\n');
    try {
      if (navigator.share) {
        await navigator.share({ title: `Bill ${invoice.billNumber}`, text });
      } else {
        await navigator.clipboard.writeText(text);
        toasts.show('Receipt copied', { tone: 'success' });
      }
    } catch (error) {
      if ((error as { name?: string })?.name !== 'AbortError') toasts.show('The receipt could not be shared. Please try again.', { tone: 'error' });
    }
  };

  return (
    <div className="receipt-page">
      <div className="no-print">
        <AppBar title="Receipt" />
      </div>
      <div className="page page--narrow">
        <InvoiceView invoice={invoice} />
        <div className="stack-sm no-print" style={{ marginTop: 20 }}>
          <Button block icon={<Download size={iconSize.md} />} onClick={() => window.print()}>
            Print or save as PDF
          </Button>
          <Button variant="secondary" block icon={<Share2 size={iconSize.md} />} onClick={() => void share()}>
            Share receipt
          </Button>
        </div>
      </div>
    </div>
  );
}

/** The guest's bills and payments in this session. */
export function PaymentHistoryPage() {
  const { billing, orders } = useApp();
  useStore(billing);
  useStore(orders);
  const navigate = useNavigate();
  const bills = billing.forOrders(orders.guestOrders);
  const paid = sum(bills.map((b) => b.netPaid));
  const due = sum(bills.map((b) => b.outstanding));
  return (
    <div>
      <AppBar title="Bills & Payments" />
      {bills.length === 0 ? (
        <EmptyState icon={<ReceiptText size={iconSize.hero} />} title="No bills yet" message="Bills for the orders you place will appear here." />
      ) : (
        <div className="page page--narrow stack-md">
          <FadeIn className="row" style={{ gap: 12 }}>
            <Card className="grow col">
              <span className="t-caption">Paid</span>
              <AnimatedMoney value={paid} className="t-headline t-success" />
            </Card>
            <Card className="grow col">
              <span className="t-caption">Balance due</span>
              <AnimatedMoney value={due} className={`t-headline ${due ? 't-primary' : 't-muted'}`} />
            </Card>
          </FadeIn>
          {bills.map((bill, index) => {
            const last = bill.latestSuccessfulPayment;
            return (
              <FadeIn key={bill.id} index={index + 1}>
                <Card role="link" tabIndex={0} onClick={() => navigate(paths.bill(bill.id))} onKeyDown={(e) => e.key === 'Enter' && navigate(paths.bill(bill.id))} style={{ cursor: 'pointer' }}>
                  <div className="row-top">
                    <div className="grow col">
                      <span className="t-card-title">{bill.billNumber}</span>
                      <span className="t-caption">
                        Order {AppFormat.orderNumber(bill.orderId)} · {AppFormat.dateTime(bill.createdAt)}
                      </span>
                      {(bill.isDemoSample || bill.isSimulated) && (
                        <span className="row" style={{ gap: 6, marginTop: 4 }}>
                          {bill.isDemoSample && <DemoTag label="SAMPLE" />}
                          {bill.isSimulated && <DemoTag label="DEMO PAYMENT" />}
                        </span>
                      )}
                    </div>
                    <PaymentStatusBadge status={bill.status} />
                  </div>
                  <hr className="dashed" style={{ margin: '12px 0' }} />
                  <Fact label="Total" value={Currency.format(bill.total)} />
                  <Fact label="Paid" value={Currency.format(bill.amountPaid)} />
                  {bill.amountRefunded > 0 && <Fact label="Refunded" value={Currency.format(bill.amountRefunded)} />}
                  <Fact label="Balance due" value={Currency.format(bill.outstanding)} />
                  {last && <Fact label="Method" value={[last.methodLabel, ...(last.reference ? [last.reference] : [])].join(' · ')} />}
                  <div className="row" style={{ gap: 12, marginTop: 12 }} onClick={(e) => e.stopPropagation()}>
                    <Button variant="secondary" compact className="grow" icon={<Download size={iconSize.md} />} onClick={() => navigate(paths.receipt(bill.id))}>
                      Receipt
                    </Button>
                    <Button compact className="grow" icon={bill.outstanding === 0 ? <ReceiptText size={iconSize.md} /> : last ? methodIcon(last.method, 18) : <Lock size={iconSize.md} />} onClick={() => navigate(paths.bill(bill.id))}>
                      {bill.outstanding === 0 ? 'View Bill' : 'Pay'}
                    </Button>
                  </div>
                </Card>
              </FadeIn>
            );
          })}
        </div>
      )}
    </div>
  );
}
