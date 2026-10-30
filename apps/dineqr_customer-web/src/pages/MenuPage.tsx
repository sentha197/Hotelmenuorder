import { CloudOff, Heart, Search, SearchX, SlidersHorizontal, X } from 'lucide-react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { collapse } from '../animations/variants';
import { FoodListSkeleton, FoodListTile } from '../components/menuItems';
import { AppBar, Button, EmptyState, FadeIn, IconButton, VegIndicator } from '../components/ui';
import { defaultFilter, dietLabel, isDefaultFilter, sortLabel, type DietFilter, type MenuSort } from '../core/menu';
import { useDebounced } from '../hooks/useDebounced';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize } from '../components/sizes';

const diets: DietFilter[] = ['all', 'veg', 'nonVeg'];
const sorts: MenuSort[] = ['popularity', 'rating', 'priceLowToHigh', 'priceHighToLow'];

/**
 * The full menu (the Menu tab, `?category=` selects one) or the guest's
 * favourites, with category, diet, search and sort.
 */
export function MenuPage({ favoritesOnly = false }: { favoritesOnly?: boolean }) {
  const { catalog } = useApp();
  useStore(catalog);
  const navigate = useNavigate();
  const reduced = useReducedMotion();
  const [params, setParams] = useSearchParams();
  const [diet, setDiet] = useState<DietFilter>('all');
  const [sort, setSort] = useState<MenuSort>('popularity');
  const [searchOpen, setSearchOpen] = useState(false);
  const [sortOpen, setSortOpen] = useState(false);
  const [query, setQuery] = useState('');
  const search = useDebounced(query, 250);
  const searchInput = useRef<HTMLInputElement>(null);

  // A category that was switched off is no longer offered.
  const requested = favoritesOnly ? null : params.get('category');
  const categoryId = requested && (catalog.state !== 'ready' || catalog.categories.some((c) => c.id === requested)) ? requested : null;
  const filter = { ...defaultFilter, categoryId, diet, sort, query: search, favoritesOnly };
  const items = catalog.filter(filter);
  const title = favoritesOnly ? 'My Favorites' : categoryId ? (catalog.categoryById(categoryId)?.label ?? 'Our Menu') : 'Our Menu';

  useEffect(() => {
    if (searchOpen) searchInput.current?.focus();
  }, [searchOpen]);

  const selectCategory = (id: string | null) => {
    const next = new URLSearchParams(params);
    if (id) next.set('category', id);
    else next.delete('category');
    setParams(next, { replace: true });
  };

  const clearFilters = () => {
    setQuery('');
    setDiet('all');
    setSort('popularity');
  };

  return (
    <div>
      <AppBar
        title={
          <AnimatePresence mode="wait" initial={false}>
            <motion.span key={title} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.15 }}>
              {title}
            </motion.span>
          </AnimatePresence>
        }
        onBack={favoritesOnly ? undefined : () => navigate(paths.home)}
        actions={
          <>
            <IconButton label={searchOpen ? 'Close search' : 'Search dishes'} onClick={() => {
              if (searchOpen) setQuery('');
              setSearchOpen(!searchOpen);
            }}>
              <motion.span key={String(searchOpen)} initial={reduced ? false : { rotate: -90, opacity: 0 }} animate={{ rotate: 0, opacity: 1 }} style={{ display: 'grid' }}>
                {searchOpen ? <X size={iconSize.lg} /> : <Search size={iconSize.lg} />}
              </motion.span>
            </IconButton>
            <div className="sort">
              <IconButton label="Sort dishes" aria-haspopup="menu" aria-expanded={sortOpen} onClick={() => setSortOpen(!sortOpen)}>
                <SlidersHorizontal size={iconSize.lg} />
                {sort !== 'popularity' && <span className="sort__dot" aria-hidden />}
              </IconButton>
              <AnimatePresence>
                {sortOpen && (
                  <>
                    <div className="sort__scrim" onClick={() => setSortOpen(false)} />
                    <motion.ul
                      className="sort__menu"
                      role="menu"
                      initial={{ opacity: 0, scale: 0.92, y: -6 }}
                      animate={{ opacity: 1, scale: 1, y: 0 }}
                      exit={{ opacity: 0, scale: 0.95 }}
                      transition={{ duration: 0.16 }}
                    >
                      {sorts.map((option) => (
                        <li key={option}>
                          <button
                            type="button"
                            role="menuitemradio"
                            aria-checked={option === sort}
                            className={`sort__option ${option === sort ? 'is-active' : ''}`}
                            onClick={() => {
                              setSort(option);
                              setSortOpen(false);
                            }}
                          >
                            {sortLabel[option]}
                          </button>
                        </li>
                      ))}
                    </motion.ul>
                  </>
                )}
              </AnimatePresence>
            </div>
          </>
        }
      />
      <div className="menu-controls">
        <AnimatePresence initial={false}>
          {searchOpen && (
            <motion.div key="search" variants={collapse} initial="hidden" animate="shown" exit="exit" style={{ overflow: 'hidden' }}>
              <div className="input-wrap" style={{ padding: '4px 0 8px' }}>
                <Search size={iconSize.lg} aria-hidden />
                <input
                  ref={searchInput}
                  className="input"
                  type="search"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search in this menu..."
                  aria-label="Search in this menu"
                  enterKeyHint="search"
                />
              </div>
            </motion.div>
          )}
        </AnimatePresence>
        {!favoritesOnly && (
          <div className="h-scroll category-tabs" role="tablist" aria-label="Categories">
            {[null, ...catalog.categories.map((c) => c.id)].map((id) => {
              const selected = id === categoryId;
              const label = id == null ? 'All' : (catalog.categoryById(id)?.label ?? id);
              return (
                <motion.button
                  key={id ?? 'all'}
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  className={`category-tab ${selected ? 'is-selected' : ''}`}
                  whileTap={{ scale: 0.94 }}
                  onClick={() => selectCategory(id)}
                >
                  {selected && <motion.span layoutId="category-pill" className="category-tab__pill" transition={reduced ? { duration: 0 } : { type: 'spring', stiffness: 480, damping: 36 }} />}
                  <span className="category-tab__label">{label}</span>
                  <span className="category-tab__count">{catalog.countIn(id)}</span>
                </motion.button>
              );
            })}
          </div>
        )}
        <div className="row diet-row">
          <div className="row grow" role="radiogroup" aria-label="Diet">
            {diets.map((d) => (
              <motion.button
                key={d}
                type="button"
                role="radio"
                aria-checked={d === diet}
                className={`diet-chip diet-chip--${d} ${d === diet ? 'is-selected' : ''}`}
                whileTap={{ scale: 0.94 }}
                onClick={() => setDiet(d)}
              >
                {d !== 'all' && <VegIndicator veg={d === 'veg'} size={11} />}
                {dietLabel[d]}
              </motion.button>
            ))}
          </div>
          {catalog.state === 'ready' && (
            <span className="t-caption" aria-live="polite">
              {items.length} {items.length === 1 ? 'dish' : 'dishes'}
            </span>
          )}
        </div>
      </div>
      <hr className="divider" />
      <div className="page" style={{ paddingTop: 6 }}>
        {catalog.state === 'loading' || catalog.state === 'idle' ? (
          <FoodListSkeleton />
        ) : catalog.state === 'error' ? (
          <EmptyState
            icon={<CloudOff size={iconSize.hero} />}
            title="Menu unavailable"
            message="We could not load the menu. Please try again."
            action={<Button onClick={() => void catalog.load(true)}>Retry</Button>}
          />
        ) : items.length === 0 ? (
          favoritesOnly && isDefaultFilter(filter) ? (
            <EmptyState
              icon={<Heart size={iconSize.hero} />}
              title="No favorites yet"
              message="Tap the heart on any dish to save it here."
              action={<Button onClick={() => navigate(paths.menu)}>Browse Menu</Button>}
            />
          ) : (
            <EmptyState
              icon={<SearchX size={iconSize.hero} />}
              title="No dishes match"
              message="Try a different filter or search term."
              action={<Button variant="secondary" onClick={clearFilters}>Clear filters</Button>}
            />
          )
        ) : (
          <div className="food-grid" key={`${categoryId}-${diet}-${sort}-${search.trim()}`}>
            {items.map((item, index) => (
              <FadeIn key={item.id} index={index}>
                <FoodListTile item={item} />
              </FadeIn>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
