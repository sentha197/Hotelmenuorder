import { BadgeCheck, Info, NotebookPen, ReceiptText, ShoppingBag, Tag, UtensilsCrossed } from 'lucide-react';
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { BillSummary } from '../components/bill';
import { FoodImage } from '../components/food';
import { AppBar, BrandPanel, Button, Card, EmptyState, FadeIn, QrLoader, VegIndicator } from '../components/ui';
import { Currency } from '../core/money';
import { CheckoutException, OrderTables } from '../core/orders';
import { offerErrorMessage } from '../core/pricing';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize } from '../components/sizes';

/** Review before placing the order. Only the server's answer places it. */
export function CheckoutPage() {
  const { cart, orders, session, settings, catalog, toasts } = useApp();
  useStore(cart);
  useStore(orders);
  const navigate = useNavigate();
  const [submitted, setSubmitted] = useState(false);
  const table = session.tableNumber;

  const place = async () => {
    try {
      const order = await orders.placeOrder(cart, table);
      setSubmitted(true);
      navigator.vibrate?.(30);
      navigate(paths.orderPlaced(order.id), { replace: true });
    } catch (error) {
      if (!(error instanceof CheckoutException) || error.reason === 'alreadyPlacing') return;
      toasts.show(error.message, { tone: 'error', durationMs: 6000 });
      if (error.detail != null) {
        // Prices or the menu changed on the server: show the current ones.
        void catalog.refresh().catch(() => undefined);
        void settings.load().catch(() => undefined);
      }
      switch (error.reason) {
        case 'tableUnavailable':
        case 'takeawayUnavailable':
          void settings.load().catch(() => undefined);
          navigate(paths.scan);
          break;
        case 'missingTable':
        case 'sessionExpired':
          navigate(paths.scan);
          break;
        case 'itemsUnavailable':
          navigate(paths.cart);
          break;
        default:
          break;
      }
    }
  };

  if (cart.isEmpty) {
    return (
      <div>
        <AppBar title="Order Summary" />
        {submitted || orders.isPlacing ? (
          <div className="entry entry--center" role="status">
            <QrLoader size={30} label="Placing your order" />
            <p className="t-label">Placing your order…</p>
          </div>
        ) : (
          <EmptyState
            icon={<ReceiptText size={iconSize.hero} />}
            title="Nothing to review"
            message="Your cart is empty. Add a few dishes to place an order."
            action={<Button onClick={() => navigate(paths.menu)}>Browse Menu</Button>}
          />
        )}
      </div>
    );
  }

  const bill = cart.bill;
  const instructions = cart.instructions.trim();
  const offer = cart.appliedOffer;
  const problem = cart.offerProblem;
  const offerNote =
    problem == null
      ? null
      : problem === 'belowMinimum' && offer
        ? `${offer.code} is not applied: add ${Currency.format(offer.shortfall(cart.subtotal))} more to get ${offer.benefit}.`
        : `${cart.offerCode}: ${offerErrorMessage[problem]}`;
  const takeaway = table != null && OrderTables.isTakeaway(table);

  return (
    <div className="with-bottom-bar">
      <AppBar title="Order Summary" onBack={orders.isPlacing ? () => undefined : undefined} />
      <div className="page page--narrow stack-lg">
        <FadeIn>
          <BrandPanel lifted className="summary-table">
            <span className="summary-table__icon">{takeaway ? <ShoppingBag size={iconSize.xl} /> : <UtensilsCrossed size={iconSize.xl} />}</span>
            <div className="grow col">
              <span className="t-caption" style={{ color: 'rgb(255 255 255 / 80%)' }}>
                {takeaway ? 'Takeaway' : 'Serving to table'}
              </span>
              {takeaway ? (
                <span className="t-section" style={{ fontWeight: 700 }}>
                  Collect at the counter
                </span>
              ) : table == null ? (
                <span className="t-section">Not selected</span>
              ) : (
                <span className="layered-text summary-table__number">
                  {AppFormat.table(table)}
                </span>
              )}
            </div>
            {table != null && (
              <span className="confirmed-pill">
                <BadgeCheck size={iconSize.sm} /> Confirmed
              </span>
            )}
          </BrandPanel>
        </FadeIn>
        <FadeIn index={1}>
          <h2 className="t-section">Your Items ({cart.totalQuantity})</h2>
        </FadeIn>
        <FadeIn index={2}>
          <Card tight>
            {cart.lines.map((line, index) => (
              <div key={line.id}>
                {index > 0 && <hr className="divider" />}
                <div className="summary-line">
                  <FoodImage src={line.item.image} width={38} height={38} radius={10} />
                  <div className="grow col">
                    <div className="row" style={{ gap: 6 }}>
                      <VegIndicator veg={line.item.isVeg} size={10} />
                      <span className="t-label t-strong">{line.item.name}</span>
                    </div>
                    {line.optionLabels.length > 0 && <span className="t-caption">{line.optionLabels.join(' · ')}</span>}
                    <span className="t-caption">{Currency.format(line.unitPrice)} each</span>
                  </div>
                  <span className="t-label t-secondary" style={{ width: 36 }}>
                    x{line.quantity}
                  </span>
                  <span className="t-label t-strong tabular" style={{ minWidth: 64, textAlign: 'right' }}>
                    {Currency.format(line.lineTotal)}
                  </span>
                </div>
              </div>
            ))}
          </Card>
        </FadeIn>
        {instructions && (
          <FadeIn index={3}>
            <Card>
              <div className="row">
                <NotebookPen size={iconSize.lg} color="var(--accent-text)" />
                <span className="t-card-title">Special Instructions</span>
              </div>
              <p className="t-secondary" style={{ marginTop: 6 }}>
                {instructions}
              </p>
            </Card>
          </FadeIn>
        )}
        <FadeIn index={4}>
          <Card>
            <BillSummary bill={bill} />
          </Card>
        </FadeIn>
        {offerNote && (
          <p className="row-top t-caption">
            <Tag size={iconSize.sm} /> {offerNote}
          </p>
        )}
        <p className="row-top t-caption">
          <Info size={iconSize.sm} /> You can pay the bill after placing the order.
        </p>
      </div>
      <div className="bottom-bar">
        <div className="bottom-bar__inner">
          <Button block loading={orders.isPlacing} onClick={place} data-testid="place-order">
            Place Order · {Currency.format(bill.total)}
          </Button>
        </div>
      </div>
    </div>
  );
}
