import { ArrowRight, BadgeCheck, CircleAlert, CircleCheck, ChevronRight, Info, ShoppingBag, Tag, Trash2, UtensilsCrossed, XCircle } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { BillSummary } from '../components/bill';
import { FoodImage, SoldOutVeil } from '../components/food';
import { AnimatedMoney } from '../components/money';
import { QuantitySelector } from '../components/QuantitySelector';
import { ConfirmDialog, Sheet } from '../components/Sheet';
import { AppBar, Button, Card, EmptyState, IconButton, VegIndicator } from '../components/ui';
import type { CartItem } from '../core/menu';
import { Currency } from '../core/money';
import { DiscountOffer } from '../core/pricing';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { CartStore } from '../state/cartStore';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize } from '../components/sizes';

export function CartPage() {
  const { cart, session, toasts, settings } = useApp();
  useStore(cart);
  useStore(session);
  useStore(settings);
  const navigate = useNavigate();
  const [confirmClear, setConfirmClear] = useState(false);
  const [couponOpen, setCouponOpen] = useState(false);
  const unavailable = cart.unavailableLines;

  const proceed = () => {
    if (cart.isEmpty) return toasts.show('Add a dish before placing an order.');
    if (unavailable.length) return toasts.show('Remove sold-out dishes to continue.');
    navigate(paths.checkout);
  };

  const removeUnavailable = () => {
    for (const line of unavailable) cart.remove(line.id);
    toasts.show(unavailable.length === 1 ? `${unavailable[0]!.item.name} removed` : `${unavailable.length} sold-out dishes removed`);
  };

  return (
    <div className="with-bottom-bar">
      <AppBar
        title="My Cart"
        onBack={() => navigate(paths.home)}
        actions={
          !cart.isEmpty && (
            <Button variant="ghost" onClick={() => setConfirmClear(true)}>
              Clear All
            </Button>
          )
        }
      />
      {cart.isEmpty ? (
        <EmptyState
          icon={<ShoppingBag size={iconSize.hero} />}
          title="Your cart is empty"
          message="Looks like you have not added anything yet. Explore the menu and pick something delicious."
          action={<Button onClick={() => navigate(paths.menu)}>Browse Menu</Button>}
        />
      ) : (
        <div className="page page--narrow stack-md">
          {session.tableLabel && (
            <div className="table-strip">
              <span className="table-strip__bar" />
              {session.isTakeaway ? <ShoppingBag size={iconSize.md} /> : <UtensilsCrossed size={iconSize.md} />}
              <span className="grow t-label t-strong">
                {session.isTakeaway ? 'Takeaway · collect at the counter' : `Ordering for ${session.tableLabel}`}
              </span>
              <BadgeCheck size={iconSize.md} color="var(--success)" />
            </div>
          )}
          {unavailable.length > 0 && (
            <div className="notice tone-error" role="alert">
              <CircleAlert size={iconSize.lg} />
              <span className="grow t-strong">
                {unavailable.length === 1 ? 'A dish in your cart has sold out.' : `${unavailable.length} dishes in your cart have sold out.`}
              </span>
              <Button variant="ghost" onClick={removeUnavailable}>
                {unavailable.length === 1 ? 'Remove it' : 'Remove them'}
              </Button>
            </div>
          )}
          <ul className="cart-lines">
            <AnimatePresence initial={false}>
              {cart.lines.map((line) => (
                <CartLine key={line.id} line={line} />
              ))}
            </AnimatePresence>
          </ul>
          <label className="field">
            <span className="t-card-title">
              Special Instructions <span className="t-caption">(Optional)</span>
            </span>
            <textarea
              className="input"
              rows={2}
              maxLength={CartStore.maxInstructionsLength}
              value={cart.instructions}
              onChange={(e) => cart.updateInstructions(e.target.value)}
              placeholder="E.g. Less spicy, no onions..."
            />
            <span className="field__hint" style={{ textAlign: 'right' }}>
              {cart.instructions.length}/{CartStore.maxInstructionsLength}
            </span>
          </label>
          <CouponCard onOpen={() => setCouponOpen(true)} />
          <Card>
            <BillSummary bill={cart.bill} />
          </Card>
        </div>
      )}
      {!cart.isEmpty && (
        <div className="bottom-bar bottom-bar--raised">
          <div className="bottom-bar__inner">
            <div className="row" style={{ marginBottom: 12 }}>
              <div className="grow col">
                <span className="t-section">Total Amount</span>
                <span className="t-caption">{AppFormat.itemCount(cart.totalQuantity)} · incl. taxes</span>
              </div>
              <AnimatedMoney value={cart.bill.total} className="t-headline" />
            </div>
            <Button block disabled={unavailable.length > 0} trailingIcon={unavailable.length ? null : <ArrowRight size={iconSize.lg} />} onClick={proceed} data-testid="proceed">
              {unavailable.length ? 'Remove sold-out dishes first' : 'Proceed to Place Order'}
            </Button>
          </div>
        </div>
      )}
      <ConfirmDialog
        open={confirmClear}
        title="Clear your cart?"
        message={`All ${cart.totalQuantity} items will be removed from your cart.`}
        confirmLabel="Clear All"
        icon={<Trash2 size={iconSize.xl} />}
        onCancel={() => setConfirmClear(false)}
        onConfirm={() => {
          cart.clear(true);
          setConfirmClear(false);
        }}
      />
      <CouponSheet open={couponOpen} onClose={() => setCouponOpen(false)} />
    </div>
  );
}

function CartLine({ line }: { line: CartItem }) {
  const { cart, toasts } = useApp();
  const reduced = useReducedMotion();
  const soldOut = !line.item.isOrderable;
  const remove = () => {
    const removed = cart.remove(line.id);
    if (!removed) return;
    navigator.vibrate?.(10);
    toasts.show(`${removed.line.item.name} removed from cart`, { actionLabel: 'UNDO', onAction: () => cart.restore(removed) });
  };
  return (
    <motion.li
      layout={!reduced}
      initial={reduced ? { opacity: 0 } : { opacity: 0, x: 24 }}
      animate={{ opacity: 1, x: 0 }}
      exit={reduced ? { opacity: 0 } : { opacity: 0, height: 0, marginTop: 0, marginBottom: 0, transition: { duration: 0.22 } }}
      transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
      className="cart-line-wrap"
    >
      <div className={`cart-line ${soldOut ? 'is-sold-out' : ''}`}>
        <SoldOutVeil soldOut={soldOut} radius={12}>
          <FoodImage src={line.item.image} width="var(--img-line)" height="var(--img-line)" radius={12} />
        </SoldOutVeil>
        <div className="grow col">
          <div className="row" style={{ gap: 6 }}>
            <VegIndicator veg={line.item.isVeg} size={11} />
            <span className="t-card-title ellipsis">{line.item.name}</span>
          </div>
          {line.optionLabels.length > 0 && <span className="t-caption clamp-2">{line.optionLabels.join(' · ')}</span>}
          {soldOut && <span className="t-caption t-error t-strong">Sold out right now. Remove it to continue.</span>}
          <div className="row" style={{ marginTop: 8 }}>
            <div className="grow col">
              <AnimatedMoney value={line.lineTotal} className="t-price" />
              {line.quantity > 1 && <span className="t-caption t-2xs">{Currency.format(line.unitPrice)} each</span>}
            </div>
            <QuantitySelector
              compact
              quantity={line.quantity}
              itemName={line.item.name}
              max={soldOut ? line.quantity : CartStore.maxQuantity}
              onIncrement={() => cart.increment(line.id)}
              onDecrement={() => (line.quantity <= 1 ? remove() : cart.decrement(line.id))}
            />
          </div>
        </div>
        <IconButton label={`Remove ${line.item.name}`} onClick={remove} className="icon-btn--sm" style={{ color: 'var(--accent-text)' }}>
          <Trash2 size={iconSize.md} />
        </IconButton>
      </div>
    </motion.li>
  );
}

function CouponCard({ onOpen }: { onOpen: () => void }) {
  const { cart, settings } = useApp();
  const offers = settings.settings.offers.filter((o) => o.isActive);
  const code = cart.offerCode;
  if (code == null && offers.length === 0) return null;
  const offer = cart.appliedOffer;
  const problem = cart.offerProblem;
  const [icon, title, subtitle, tone] =
    code == null
      ? [<Tag size={iconSize.lg} key="i" />, 'Apply a coupon', `${offers.length} ${offers.length === 1 ? 'offer' : 'offers'} available`, 'var(--accent-text)']
      : problem == null
        ? [<CircleCheck size={iconSize.lg} key="i" />, `${code} applied`, `You save ${Currency.format(cart.discount)} on this order`, 'var(--success)']
        : problem === 'belowMinimum' && offer
          ? [<Info size={iconSize.lg} key="i" />, `${code} saved`, `Add ${Currency.format(offer.shortfall(cart.subtotal))} more to get ${offer.benefit}`, 'var(--warning)']
          : [<XCircle size={iconSize.lg} key="i" />, `${code} cannot be used`, problem === 'inactive' ? 'This offer is not active right now.' : 'That code is not valid.', 'var(--error)'];
  return (
    <motion.div
      className="coupon"
      style={{ '--tone': tone } as React.CSSProperties}
      data-applied={code != null}
      layout
      transition={{ duration: 0.25 }}
    >
      <button type="button" className="coupon__main" onClick={code == null ? onOpen : undefined} disabled={code != null} aria-label={code == null ? 'Apply a coupon' : undefined}>
        <span className="coupon__icon">{icon}</span>
        <span className="grow col" style={{ textAlign: 'left' }}>
          <span className="t-card-title">{title}</span>
          <span className="t-caption">{subtitle}</span>
        </span>
        {code == null && <ChevronRight size={iconSize.lg} color="var(--text-muted)" />}
      </button>
      {code != null && (
        <Button variant="ghost" onClick={() => cart.removeOffer()}>
          Remove
        </Button>
      )}
    </motion.div>
  );
}

function CouponSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { cart, settings } = useApp();
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const offers = settings.settings.offers.filter((o) => o.isActive);
  const apply = (value: string) => {
    if (!DiscountOffer.isValidCode(value)) return setError('Enter the code shown on the offer.');
    const problem = cart.applyOffer(value);
    if (problem === 'unknownCode') return setError('That code is not valid.');
    if (problem === 'inactive') return setError('This offer is not active right now.');
    setCode('');
    setError(null);
    onClose();
  };
  return (
    <Sheet open={open} onClose={onClose} title="Apply a coupon">
      <h2 className="t-section">Apply a coupon</h2>
      <form
        className="row-top"
        style={{ marginTop: 12 }}
        onSubmit={(e) => {
          e.preventDefault();
          apply(code);
        }}
      >
        <label className="field grow">
          <span className="visually-hidden">Coupon code</span>
          <input
            className="input"
            value={code}
            maxLength={16}
            onChange={(e) => {
              setCode(e.target.value.replace(/[^A-Za-z0-9]/g, '').toUpperCase());
              setError(null);
            }}
            placeholder="Enter coupon code"
            aria-invalid={error != null}
            autoCapitalize="characters"
          />
          {error && (
            <span className="field__error" role="alert">
              {error}
            </span>
          )}
        </label>
        <Button type="submit">Apply</Button>
      </form>
      {offers.length > 0 && (
        <>
          <p className="t-label t-secondary t-strong" style={{ marginTop: 18 }}>
            Available offers
          </p>
          <ul className="offer-list">
            {offers.map((offer) => {
              const shortfall = offer.shortfall(cart.subtotal);
              return (
                <li key={offer.code} className="row">
                  <div className="grow col">
                    <span className="code-chip">{offer.code}</span>
                    <span className="t-label t-strong" style={{ marginTop: 6 }}>
                      {offer.title || offer.benefit}
                    </span>
                    <span className="t-caption">{offer.summary}</span>
                    {shortfall > 0 && <span className="t-caption t-warning">Add {Currency.format(shortfall)} more to use it</span>}
                  </div>
                  <Button variant="ghost" onClick={() => apply(offer.code)}>
                    APPLY
                  </Button>
                </li>
              );
            })}
          </ul>
        </>
      )}
    </Sheet>
  );
}
