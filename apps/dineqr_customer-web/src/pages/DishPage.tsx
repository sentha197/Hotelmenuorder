import { Award, ArrowLeft, Ban, CheckCircle2, Clock, Heart, ShoppingBag, UtensilsCrossed, X } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate, useParams } from 'react-router';
import { FoodImage } from '../components/food';
import { AnimatedMoney } from '../components/money';
import { QuantitySelector } from '../components/QuantitySelector';
import { AppBar, Button, EmptyState, FadeIn, IconButton, MaskedText, RatingBadge, VegIndicator } from '../components/ui';
import { DishCustomization, spiceLabel, spiceLevels, type MenuItem, type SpiceLevel } from '../core/menu';
import { Currency } from '../core/money';
import { imageUrl } from '../config';
import { paths } from '../routes/paths';
import { CartStore } from '../state/cartStore';
import { useApp } from '../state/app';
import { useSelect, useStore } from '../state/store';
import { iconSize } from '../components/sizes';

export function DishPage() {
  const { catalog } = useApp();
  useStore(catalog);
  const { itemId = '' } = useParams();
  const navigate = useNavigate();
  // Only dishes guests may see (not archived, not in a hidden category).
  const item = catalog.visibleById(itemId);
  if (catalog.state === 'ready' && !item) {
    return (
      <div>
        <AppBar />
        <EmptyState
          icon={<UtensilsCrossed size={iconSize.hero} />}
          title="Dish not available"
          message="This dish is not on the menu right now."
          action={<Button onClick={() => navigate(paths.menu)}>Back to menu</Button>}
        />
      </div>
    );
  }
  if (!item) return <DishSkeleton />;
  return <DishDetails key={item.id} item={item} />;
}

function DishSkeleton() {
  return (
    <div aria-hidden>
      <div className="skeleton" style={{ height: 330, borderRadius: 0 }} />
    </div>
  );
}

function DishDetails({ item }: { item: MenuItem }) {
  const { cart, toasts } = useApp();
  const navigate = useNavigate();
  const [spice, setSpice] = useState<SpiceLevel | null>(item.hasSpiceLevel ? item.defaultSpice : null);
  const [portionId, setPortionId] = useState<string | null>(item.defaultPortion?.id ?? null);
  const [addOns, setAddOns] = useState<Set<string>>(new Set());
  const [quantity, setQuantity] = useState(1);
  const [justAdded, setJustAdded] = useState(false);
  const addedTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => void (addedTimer.current && clearTimeout(addedTimer.current)), []);

  const customization = new DishCustomization(spice, portionId, addOns);
  const unitPrice = item.price + customization.extraFor(item);
  const total = unitPrice * quantity;

  const add = () => {
    cart.add(item, customization, quantity);
    navigator.vibrate?.(15);
    setJustAdded(true);
    if (addedTimer.current) clearTimeout(addedTimer.current);
    addedTimer.current = setTimeout(() => setJustAdded(false), 1500);
    toasts.show(`${quantity} × ${item.name} added to cart`, { tone: 'success', actionLabel: 'VIEW CART', onAction: () => navigate(paths.cart) });
  };

  return (
    <div className="dish">
      <div className="dish__hero">
        <DishGallery item={item} />
        <div className="dish__hero-bar">
          <IconButton label="Back" filled onClick={() => (window.history.state?.idx > 0 ? navigate(-1) : navigate(paths.menu))}>
            <ArrowLeft size={iconSize.lg} />
          </IconButton>
          <span className="grow" />
          <FavoriteButton itemId={item.id} />
          <CartButton />
        </div>
      </div>
      <div className="dish__sheet page page--narrow">
        <FadeIn>
          <div className="row-top">
            <h1 className="dish__title grow">
              <MaskedText by="line">{item.name}</MaskedText>
            </h1>
            <span className="t-headline layered-text layered-text--red">
              {Currency.format(item.price)}
            </span>
          </div>
          <div className="row wrap" style={{ gap: 10, marginTop: 8 }}>
            <span className="row" style={{ gap: 6 }}>
              <VegIndicator veg={item.isVeg} />
              <span className="t-caption t-strong" style={{ color: item.isVeg ? 'var(--veg)' : 'var(--non-veg)' }}>
                {item.isVeg ? 'Veg' : 'Non-veg'}
              </span>
            </span>
            <RatingBadge rating={item.rating} reviews={item.reviewCount} />
            <span className="meta-chip">
              <Clock size={iconSize.sm} /> {item.prepMinutes} min
            </span>
            <span className="meta-chip">
              <UtensilsCrossed size={iconSize.sm} /> {item.category.label}
            </span>
            {item.isChefSpecial && (
              <span className="meta-chip meta-chip--warning">
                <Award size={iconSize.sm} /> Chef&apos;s special
              </span>
            )}
          </div>
        </FadeIn>
        <FadeIn index={1}>
          <p className="t-secondary dish__description" style={{ marginTop: 10 }}>
            {item.description}
          </p>
        </FadeIn>
        {item.isCustomizable && (
          <FadeIn index={2}>
            <h2 className="t-section" style={{ marginTop: 20 }}>
              Customize
            </h2>
          </FadeIn>
        )}
        {item.hasSpiceLevel && (
          <FadeIn index={3}>
            <OptionGroup title="Spice Level">
              <div className="choice-row" role="radiogroup" aria-label="Spice level">
                {spiceLevels.map((level) => (
                  <Choice key={level} label={spiceLabel[level]} selected={spice === level} onSelect={() => setSpice(level)} />
                ))}
              </div>
            </OptionGroup>
          </FadeIn>
        )}
        {item.portions.length > 1 && (
          <FadeIn index={4}>
            <OptionGroup title="Portion">
              <div className="choice-row" role="radiogroup" aria-label="Portion">
                {item.portions.map((portion) => (
                  <Choice
                    key={portion.id}
                    label={portion.label}
                    detail={[...(portion.detail ? [portion.detail] : []), ...(portion.extraPrice ? [Currency.formatExtra(portion.extraPrice)] : [])].join(' · ')}
                    selected={portionId === portion.id}
                    onSelect={() => setPortionId(portion.id)}
                  />
                ))}
              </div>
            </OptionGroup>
          </FadeIn>
        )}
        {item.addOns.length > 0 && (
          <FadeIn index={5}>
            <OptionGroup title="Add-ons" trailing="Optional">
              <div className="stack-sm">
                {item.addOns.map((addOn) => (
                  <label key={addOn.id} className="addon">
                    <input
                      type="checkbox"
                      className="checkbox"
                      checked={addOns.has(addOn.id)}
                      onChange={(e) => {
                        const next = new Set(addOns);
                        if (e.target.checked) next.add(addOn.id);
                        else next.delete(addOn.id);
                        setAddOns(next);
                      }}
                    />
                    <span className="grow t-label">{addOn.name}</span>
                    <span className="t-label t-secondary">{Currency.formatExtra(addOn.price)}</span>
                  </label>
                ))}
              </div>
            </OptionGroup>
          </FadeIn>
        )}
        <FadeIn index={6}>
          <div className="row" style={{ marginTop: 20 }}>
            <div className="grow col">
              <h2 className="t-section">Quantity</h2>
              <span className="t-caption">{Currency.format(unitPrice)} each</span>
            </div>
            <QuantitySelector
              quantity={quantity}
              min={1}
              max={CartStore.maxQuantity}
              itemName={item.name}
              onIncrement={() => setQuantity((q) => Math.min(q + 1, CartStore.maxQuantity))}
              onDecrement={() => setQuantity((q) => Math.max(q - 1, 1))}
            />
          </div>
        </FadeIn>
      </div>
      <div className="bottom-bar">
        <div className="bottom-bar__inner">
          {item.isOrderable ? (
            <Button block success={justAdded} onClick={add} data-testid="add-to-cart">
              <AnimatePresence mode="wait" initial={false}>
                <motion.span
                  key={justAdded ? 'added' : 'add'}
                  className="row"
                  style={{ justifyContent: 'center' }}
                  initial={{ opacity: 0, scale: 0.85 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.85 }}
                  transition={{ duration: 0.16 }}
                >
                  {justAdded ? (
                    <>
                      <CheckCircle2 size={iconSize.lg} /> Added to Cart
                    </>
                  ) : (
                    <>
                      <ShoppingBag size={iconSize.lg} /> Add to Cart <span style={{ opacity: 0.7 }}>·</span> <AnimatedMoney value={total} />
                    </>
                  )}
                </motion.span>
              </AnimatePresence>
            </Button>
          ) : (
            <Button block disabled icon={<Ban size={iconSize.lg} />}>
              Sold out right now
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

function OptionGroup({ title, trailing, children }: { title: string; trailing?: string; children: React.ReactNode }) {
  return (
    <div style={{ marginTop: 16 }}>
      <div className="row" style={{ marginBottom: 8 }}>
        <h3 className="t-card-title grow">
          {title}
        </h3>
        {trailing && <span className="t-caption">{trailing}</span>}
      </div>
      {children}
    </div>
  );
}

function Choice({ label, detail, selected, onSelect }: { label: string; detail?: string; selected: boolean; onSelect: () => void }) {
  return (
    <motion.button type="button" role="radio" aria-checked={selected} className={`choice ${selected ? 'is-selected' : ''}`} whileTap={{ scale: 0.95 }} onClick={onSelect}>
      <span className="t-label t-strong ellipsis">{label}</span>
      {detail && <span className="choice__detail ellipsis">{detail}</span>}
    </motion.button>
  );
}

function FavoriteButton({ itemId }: { itemId: string }) {
  const { catalog, toasts } = useApp();
  const favorite = useSelect(catalog, (c) => c.isFavorite(itemId));
  const reduced = useReducedMotion();
  return (
    <span className="fav">
      <IconButton
        label={favorite ? 'Remove from favorites' : 'Add to favorites'}
        aria-pressed={favorite}
        filled
        onClick={() => {
          const added = catalog.toggleFavorite(itemId);
          toasts.show(added ? 'Saved to your favorites' : 'Removed from favorites', { tone: added ? 'success' : 'info', durationMs: 2000 });
        }}
      >
        <motion.span key={String(favorite)} initial={reduced ? false : { scale: 0.4 }} animate={{ scale: 1 }} transition={{ type: 'spring', stiffness: 600, damping: 14 }} style={{ display: 'grid' }}>
          <Heart size={iconSize.lg} color={favorite ? 'var(--accent-text)' : 'currentColor'} fill={favorite ? 'var(--accent-text)' : 'none'} />
        </motion.span>
      </IconButton>
      <AnimatePresence>
        {favorite && !reduced && (
          <motion.span key="burst" className="fav__burst" initial={{ scale: 0.6, opacity: 0.8 }} animate={{ scale: 1.8, opacity: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.5 }} />
        )}
      </AnimatePresence>
    </span>
  );
}

function CartButton() {
  const { cart } = useApp();
  const navigate = useNavigate();
  const count = useSelect(cart, (c) => c.totalQuantity);
  return (
    <span className="badge-anchor">
      <IconButton label={`View cart, ${count} items`} filled onClick={() => navigate(paths.cart)}>
        <ShoppingBag size={iconSize.lg} />
      </IconButton>
      {count > 0 && (
        <motion.span key={count} className="count-badge badge-anchor__badge" initial={{ scale: 1.4 }} animate={{ scale: 1 }} aria-hidden>
          {count > 99 ? '99+' : count}
        </motion.span>
      )}
    </span>
  );
}

/** Swipe between the dish's photos; tap opens them full screen. */
function DishGallery({ item }: { item: MenuItem }) {
  const photos = item.photos;
  const [index, setIndex] = useState(0);
  const [viewer, setViewer] = useState(false);
  return (
    <>
      <div
        className="gallery"
        onScroll={(e) => setIndex(Math.round(e.currentTarget.scrollLeft / Math.max(1, e.currentTarget.clientWidth)))}
      >
        {(photos.length ? photos : ['']).map((photo, i) => (
          <button key={photo || i} type="button" className="gallery__slide" onClick={() => photo && setViewer(true)} aria-label={photo ? `Open photo ${i + 1} of ${photos.length}` : 'No photo'}>
            <FoodImage src={photo} width="100%" height="100%" eager={i === 0} alt={i === 0 ? item.name : ''} />
          </button>
        ))}
      </div>
      <div className="gallery__shade" aria-hidden />
      {photos.length > 1 && (
        <div className="gallery__dots" aria-hidden>
          {photos.map((photo, i) => (
            <span key={photo} className={i === index ? 'is-active' : ''} />
          ))}
        </div>
      )}
      {viewer &&
        createPortal(
          <div className="viewer" role="dialog" aria-modal="true" aria-label={`${item.name} photos`} onKeyDown={(e) => e.key === 'Escape' && setViewer(false)}>
            <div className="viewer__track">
              {photos.map((photo) => (
                <img key={photo} src={imageUrl(photo)} alt={item.name} />
              ))}
            </div>
            <IconButton label="Close photos" className="viewer__close" autoFocus onClick={() => setViewer(false)}>
              <X size={iconSize.xl} />
            </IconButton>
          </div>,
          document.body,
        )}
    </>
  );
}
