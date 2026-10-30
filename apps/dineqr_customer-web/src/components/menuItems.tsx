import { Award, Plus } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useNavigate } from 'react-router';
import { tap } from '../animations/variants';
import type { MenuItem } from '../core/menu';
import { Currency } from '../core/money';
import { paths } from '../routes/paths';
import { CartStore } from '../state/cartStore';
import { useApp } from '../state/app';
import { useSelect } from '../state/store';
import { FoodImage, SoldOutVeil } from './food';
import { QuantitySelector } from './QuantitySelector';
import { RatingBadge, Skeleton, VegIndicator } from './ui';
import { iconSize } from './sizes';

/** "+" that becomes a stepper once the dish is in the cart (kept in sync everywhere). */
export function AddToCartControl({ item }: { item: MenuItem }) {
  const { cart, toasts } = useApp();
  const navigate = useNavigate();
  const quantity = useSelect(cart, (c) => c.quantityOfItem(item.id));
  const orderable = item.isOrderable;

  const add = (announce: boolean) => {
    cart.quickAdd(item);
    navigator.vibrate?.(10);
    if (announce) {
      toasts.show(`${item.name} added to cart`, { tone: 'success', actionLabel: 'VIEW CART', onAction: () => navigate(paths.cart) });
    }
  };
  const remove = () => {
    if (cart.quickRemove(item) === 'ambiguous') {
      toasts.show(`${item.name} is in your cart with different options. Adjust it from the cart.`, {
        actionLabel: 'OPEN CART',
        onAction: () => navigate(paths.cart),
      });
    }
  };

  const key = quantity === 0 ? (orderable ? 'add' : 'sold-out') : 'stepper';
  return (
    <div onClick={(e) => e.stopPropagation()} onKeyDown={(e) => e.stopPropagation()} style={{ flex: 'none' }}>
      <AnimatePresence mode="popLayout" initial={false}>
        <motion.div
          key={key}
          initial={{ opacity: 0, scale: 0.6 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.6 }}
          transition={{ type: 'spring', stiffness: 500, damping: 30 }}
        >
          {key === 'add' && (
            <motion.button type="button" className="add-btn" aria-label={`Add ${item.name} to cart`} whileTap={{ scale: 0.85 }} onClick={() => add(true)}>
              <Plus size={iconSize.lg} />
            </motion.button>
          )}
          {key === 'sold-out' && (
            <span className="t-caption t-muted t-strong" aria-label={`${item.name} is sold out`}>
              Sold out
            </span>
          )}
          {key === 'stepper' && (
            <QuantitySelector
              compact
              quantity={quantity}
              itemName={item.name}
              max={orderable ? CartStore.maxQuantity : quantity}
              onIncrement={() => add(false)}
              onDecrement={remove}
            />
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}

export function ChefBadge() {
  return (
    <span className="chef-badge">
      <Award size={iconSize.xs} /> Chef&apos;s pick
    </span>
  );
}

/** Vertical card for the Popular carousel. */
export function FoodCard({ item }: { item: MenuItem }) {
  const navigate = useNavigate();
  const open = () => navigate(paths.dish(item.id));
  return (
    <motion.article
      className="food-card"
      whileTap={tap}
      onClick={open}
      onKeyDown={(e) => e.key === 'Enter' && open()}
      tabIndex={0}
      role="link"
      aria-label={`${item.name}, ${Currency.format(item.price)}`}
    >
      <div className="food-card__media">
        <SoldOutVeil soldOut={!item.isOrderable} radius={13}>
          <FoodImage src={item.image} width="100%" height="var(--img-card-h)" radius={13} />
        </SoldOutVeil>
        <span className="food-card__veg">
          <VegIndicator veg={item.isVeg} />
        </span>
        {item.isChefSpecial && (
          <span className="food-card__chef">
            <ChefBadge />
          </span>
        )}
        <span className="food-card__rating">
          <RatingBadge rating={item.rating} reviews={item.reviewCount} size={11.5} />
        </span>
      </div>
      <div className="food-card__body">
        <h3 className="t-card-title ellipsis">{item.name}</h3>
        <p className="t-caption ellipsis">{item.shortDescription}</p>
        <div className="row" style={{ marginTop: 'auto', paddingTop: 8 }}>
          <span className="t-price t-price--lg grow">
            {Currency.format(item.price)}
          </span>
          <AddToCartControl item={item} />
        </div>
      </div>
    </motion.article>
  );
}

/** Row for menus and search results. */
export function FoodListTile({ item }: { item: MenuItem }) {
  const navigate = useNavigate();
  const open = () => navigate(paths.dish(item.id));
  return (
    <motion.article
      className="food-tile"
      whileTap={{ scale: 0.985 }}
      onClick={open}
      onKeyDown={(e) => e.key === 'Enter' && open()}
      tabIndex={0}
      role="link"
      aria-label={`${item.name}, ${Currency.format(item.price)}${item.isOrderable ? '' : ', sold out'}`}
    >
      <div className="food-tile__media">
        <SoldOutVeil soldOut={!item.isOrderable} radius={14}>
          <FoodImage src={item.image} width="var(--img-tile)" height="var(--img-tile)" radius={14} />
        </SoldOutVeil>
        {item.isChefSpecial && item.isOrderable && <span className="food-tile__ribbon">CHEF&apos;S PICK</span>}
      </div>
      <div className="grow col">
        <div className="row" style={{ gap: 6 }}>
          <VegIndicator veg={item.isVeg} size={12} />
          <h3 className="t-card-title ellipsis">{item.name}</h3>
        </div>
        <p className="t-caption clamp-2" style={{ marginTop: 3 }}>
          {item.shortDescription}
        </p>
        <div className="row" style={{ marginTop: 6 }}>
          <span className="t-price">{Currency.format(item.price)}</span>
          <RatingBadge rating={item.rating} />
        </div>
      </div>
      <AddToCartControl item={item} />
    </motion.article>
  );
}

export function FoodListSkeleton({ count = 5 }: { count?: number }) {
  return (
    <div aria-hidden>
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className="food-tile">
          <Skeleton width="var(--img-tile)" height="var(--img-tile)" radius={14} />
          <div className="grow stack-sm">
            <Skeleton width={140} height={14} />
            <Skeleton width={180} height={10} />
            <Skeleton width={60} height={14} />
          </div>
          <Skeleton width={30} height={30} radius={10} />
        </div>
      ))}
    </div>
  );
}
