import { ArrowRight, Check, CloudOff, Search, SearchX, ShoppingBag, Store as StoreIcon, Tag, UtensilsCrossed, UtensilsIcon, X } from 'lucide-react';
import { motion } from 'motion/react';
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router';
import { tap } from '../animations/variants';
import { CategoryCards, type CategoryCard } from '../components/CategoryCards';
import { DishRing } from '../components/DishRing';
import { FeaturedCarousel } from '../components/FeaturedCarousel';
import { FoodImage } from '../components/food';
import { Lockup } from '../components/brand';
import { AddToCartControl, FoodCard, FoodListTile } from '../components/menuItems';
import { Button, EmptyState, Eyebrow, FadeIn, IconButton, MaskedText, RatingBadge, Skeleton, VegIndicator } from '../components/ui';
import { defaultFilter, type MenuItem } from '../core/menu';
import { Currency } from '../core/money';
import type { DiscountOffer } from '../core/pricing';
import { greetingAt, nextGreetingChange } from '../core/time';
import { useDebounced } from '../hooks/useDebounced';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useSelect, useStore } from '../state/store';
import { iconSize, lockupHeight } from '../components/sizes';

export function HomePage() {
  const { catalog, settings } = useApp();
  useStore(catalog);
  useStore(settings);
  const [query, setQuery] = useState('');
  const search = useDebounced(query, 250).trim();

  return (
    <div className="home">
      <HomeHeader query={query} onQuery={setQuery} />
      <div className="home__body">
        {catalog.state === 'loading' || catalog.state === 'idle' ? (
          <HomeSkeleton />
        ) : catalog.state === 'error' ? (
          <EmptyState
            icon={<CloudOff size={iconSize.hero} />}
            title="Menu unavailable"
            message="We could not load the menu. Please try again."
            action={<Button onClick={() => void catalog.load(true)}>Retry</Button>}
          />
        ) : search ? (
          <SearchResults query={search} onClear={() => setQuery('')} />
        ) : (
          <Sections />
        )}
      </div>
    </div>
  );
}

function HomeHeader({ query, onQuery }: { query: string; onQuery: (value: string) => void }) {
  const { session, settings } = useApp();
  useStore(session);
  const navigate = useNavigate();
  const restaurant = useSelect(settings, (s) => s.settings.name);
  const offset = useSelect(settings, (s) => s.settings.utcOffsetMinutes);
  const greeting = useGreeting(offset);
  return (
    <section className="home-hero">
      <div className="home-hero__inner">
        <div className="home-hero__top">
          <div className="home-hero__brand grow">
            <Lockup height={lockupHeight.lg} />
          </div>
          {session.tableNumber != null && (
            <motion.button
              type="button"
              className="table-pill"
              whileTap={tap}
              onClick={() => navigate(paths.more)}
              aria-label={`Ordering at ${session.tableLabel}. Open table options.`}
            >
              {session.isTakeaway ? <ShoppingBag size={iconSize.sm} /> : <UtensilsIcon size={iconSize.sm} />}
              {session.tableLabel}
            </motion.button>
          )}
        </div>
        <Eyebrow icon={<StoreIcon size={iconSize.sm} />} className="home-hero__eyebrow">
          {restaurant}
        </Eyebrow>
        <p className="home-hero__greeting">{greeting}!</p>
        <h1 className="home-hero__title">
          <MaskedText delay={0.1}>What are you craving today?</MaskedText>
        </h1>
        <div className="input-wrap home__search">
          <Search size={iconSize.lg} aria-hidden />
          <input
            className="input"
            type="search"
            value={query}
            onChange={(e) => onQuery(e.target.value)}
            placeholder="Search for dishes..."
            aria-label="Search for dishes"
            enterKeyHint="search"
          />
          {query && (
            <IconButton label="Clear search" className="input-wrap__clear" onClick={() => onQuery('')}>
              <X size={iconSize.md} />
            </IconButton>
          )}
        </div>
      </div>
    </section>
  );
}

/** Morning/afternoon/evening in restaurant time, refreshed at the boundary. */
function useGreeting(offsetMinutes: number) {
  const [greeting, setGreeting] = useState(() => greetingAt(new Date()));
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const schedule = () => {
      setGreeting(greetingAt(new Date()));
      const due = nextGreetingChange(new Date()).getTime() - Date.now() + 1000;
      timer = setTimeout(schedule, due > 0 ? due : 60_000);
    };
    schedule();
    const onVisible = () => document.visibilityState === 'visible' && setGreeting(greetingAt(new Date()));
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [offsetMinutes]);
  return greeting;
}

function SearchResults({ query, onClear }: { query: string; onClear: () => void }) {
  const { catalog } = useApp();
  const results = catalog.filter({ ...defaultFilter, query });
  return (
    <section className="page" aria-live="polite">
      <p className="t-label t-secondary" style={{ padding: '12px 0 6px' }}>
        {results.length ? `${results.length} ${results.length === 1 ? 'dish' : 'dishes'} for "${query}"` : 'No results'}
      </p>
      {results.length === 0 ? (
        <EmptyState
          icon={<SearchX size={iconSize.hero} />}
          title="No dishes found"
          message='Try another dish name, like "biryani" or "paneer".'
          action={<Button variant="secondary" onClick={onClear}>Clear search</Button>}
        />
      ) : (
        <div className="food-grid">
          {results.map((item, index) => (
            <FadeIn key={item.id} index={index}>
              <FoodListTile item={item} />
            </FadeIn>
          ))}
        </div>
      )}
    </section>
  );
}

function Sections() {
  const { catalog, settings } = useApp();
  const navigate = useNavigate();
  if (catalog.items.length === 0) {
    return <EmptyState icon={<UtensilsCrossed size={iconSize.hero} />} title="Menu coming soon" message="The restaurant has not published any dishes yet." />;
  }
  const offers = settings.settings.offers.filter((o) => o.isActive);
  const mains = catalog.categories.find((c) => c.id === 'mainCourse');
  const popular = catalog.popular;
  const recommended = catalog.recommended;
  const specials = catalog.chefSpecials;
  return (
    <>
      {/* The featured banner overlaps the ring's lower third. */}
      <DishRing items={catalog.items} />
      {catalog.banners.length > 0 && <FeaturedCarousel items={catalog.banners} />}
      <CategoryRow />
      {popular.length > 0 && (
        <section>
          <SectionHeader title="Popular Dishes" action="View All" onAction={() => navigate(paths.menu)} />
          <div className="h-scroll" role="list">
            {popular.map((item, index) => (
              <FadeIn key={item.id} index={index} axis="x" role="listitem">
                <FoodCard item={item} />
              </FadeIn>
            ))}
          </div>
        </section>
      )}
      {offers.length > 0 && <OffersStrip offers={offers} />}
      {recommended.length > 0 && (
        <section>
          <SectionHeader title="Recommended" />
          <div className="h-scroll" role="list">
            {recommended.map((item, index) => (
              <FadeIn key={item.id} index={index} axis="x" role="listitem">
                <RecommendedCard item={item} />
              </FadeIn>
            ))}
          </div>
        </section>
      )}
      {specials.length > 0 && (
        <section style={{ paddingBottom: 24 }}>
          <SectionHeader
            title="Chef's Specials"
            action={mains?.label}
            onAction={mains ? () => navigate(paths.category(mains.id)) : undefined}
          />
          <div className="food-grid page" style={{ paddingTop: 0 }}>
            {specials.map((item, index) => (
              <FadeIn key={item.id} index={index}>
                <FoodListTile item={item} />
              </FadeIn>
            ))}
          </div>
        </section>
      )}
    </>
  );
}

function SectionHeader({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return (
    <div className="section-header">
      <h2 className="t-section">{title}</h2>
      {action && onAction && (
        <button type="button" className="section-header__action" onClick={onAction}>
          {action} <ArrowRight size={iconSize.sm} />
        </button>
      )}
    </div>
  );
}

/** "All" and every category with dishes; a card opens that part of the menu. */
function CategoryRow() {
  const { catalog } = useApp();
  const navigate = useNavigate();
  const cards: CategoryCard[] = [
    { id: null, label: 'All', image: '', count: catalog.countIn(null) },
    ...catalog.categories
      .filter((c) => catalog.countIn(c.id) > 0)
      .map((c) => ({ id: c.id, label: c.label, image: c.coverImage, count: catalog.countIn(c.id) })),
  ];
  return (
    <section className="home__categories" aria-label="Categories">
      <SectionHeader title="Categories" action="Full menu" onAction={() => navigate(paths.menu)} />
      <CategoryCards
        categories={cards}
        selected={null}
        ringId="home-category-ring"
        onSelect={(id) => navigate(id == null ? paths.menu : paths.category(id))}
      />
    </section>
  );
}

function RecommendedCard({ item }: { item: MenuItem }) {
  const navigate = useNavigate();
  return (
    <motion.article
      className="rec-card"
      whileTap={tap}
      onClick={() => navigate(paths.dish(item.id))}
      onKeyDown={(e) => e.key === 'Enter' && navigate(paths.dish(item.id))}
      tabIndex={0}
      role="link"
      aria-label={`${item.name}, ${Currency.format(item.price)}`}
    >
      <FoodImage src={item.image} width="var(--img-rec)" height="var(--img-rec)" radius={14} />
      <div className="grow col">
        <div className="row" style={{ gap: 6 }}>
          <VegIndicator veg={item.isVeg} size={11} />
          <h3 className="t-card-title ellipsis">{item.name}</h3>
        </div>
        <div style={{ marginTop: 4 }}>
          <RatingBadge rating={item.rating} reviews={item.reviewCount} />
        </div>
        <div className="row" style={{ marginTop: 8 }}>
          <span className="t-price grow">{Currency.format(item.price)}</span>
          <AddToCartControl item={item} />
        </div>
      </div>
    </motion.article>
  );
}

/** Active coupons; "Apply" saves the code to the cart. */
function OffersStrip({ offers }: { offers: DiscountOffer[] }) {
  const { cart, toasts } = useApp();
  const applied = useSelect(cart, (c) => c.offerCode);
  const apply = (offer: DiscountOffer) => {
    const problem = cart.applyOffer(offer.code);
    toasts.show(
      problem == null
        ? `${offer.code} applied to your cart`
        : problem === 'belowMinimum'
          ? `${offer.code} saved. Add ${Currency.format(offer.shortfall(cart.subtotal))} more to use it.`
          : problem === 'inactive'
            ? 'This offer is not active right now.'
            : 'That code is not valid.',
      { tone: problem == null ? 'success' : 'info' },
    );
  };
  return (
    <section>
      <SectionHeader title="Offers for You" />
      <div className="h-scroll" role="list">
        {offers.map((offer, index) => {
          const isApplied = offer.code === applied;
          return (
            <FadeIn key={offer.code} index={index} axis="x" role="listitem">
              <motion.button
                type="button"
                className={`offer-ticket ${isApplied ? 'is-applied' : ''}`}
                whileTap={isApplied ? undefined : tap}
                onClick={() => !isApplied && apply(offer)}
                aria-label={`${offer.title || offer.code}. ${offer.summary}. Code ${offer.code}${isApplied ? ', applied' : ''}`}
              >
                <span className="offer-ticket__stub">{isApplied ? <Check size={iconSize.lg} /> : <Tag size={iconSize.lg} />}</span>
                <span className="offer-ticket__body">
                  <span className="t-card-title ellipsis">
                    {[offer.benefit, ...(offer.maxDiscount != null ? [`up to ${Currency.format(offer.maxDiscount)}`] : [])].join(' ')}
                  </span>
                  <span className="t-caption ellipsis">
                    {[...(offer.minSubtotal ? [`Above ${Currency.format(offer.minSubtotal)}`] : []), ...(offer.title ? [offer.title] : [])].join(' · ')}
                  </span>
                  <span className="offer-ticket__code">{isApplied ? `APPLIED · ${offer.code}` : offer.code}</span>
                </span>
                {!isApplied && <span className="offer-ticket__apply">APPLY</span>}
              </motion.button>
            </FadeIn>
          );
        })}
      </div>
    </section>
  );
}

function HomeSkeleton() {
  return (
    <div className="page home-skeleton" aria-hidden>
      <Skeleton height="var(--feature-h)" radius={22} />
      <div className="row" style={{ gap: 12, padding: '22px 0 18px', overflow: 'hidden' }}>
        {[0, 1, 2, 3, 4].map((i) => (
          <div key={i} className="col" style={{ alignItems: 'center', gap: 8 }}>
            <Skeleton width="var(--cat-size)" height="var(--cat-size)" radius={20} />
            <Skeleton width={52} height={10} />
          </div>
        ))}
      </div>
      <Skeleton width={140} height={16} />
      <div className="row" style={{ marginTop: 12, gap: 12 }}>
        {[0, 1].map((i) => (
          <div key={i} className="grow stack-sm">
            <Skeleton height={120} radius={16} />
            <Skeleton width={110} height={12} />
            <Skeleton width={56} height={14} />
          </div>
        ))}
      </div>
    </div>
  );
}
