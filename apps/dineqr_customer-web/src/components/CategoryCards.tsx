import { UtensilsCrossed } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { FoodImage } from './food';
import { iconSize } from './sizes';
import { FadeIn } from './ui';

export interface CategoryCard {
  /** null is "All". */
  id: string | null;
  label: string;
  image: string;
  count: number;
}

/**
 * The menu's categories as photo cards in a sideways row. The selected one
 * wears a glowing ring that slides to the next selection; on the home page
 * "All" leads the row. Large on the home page, where a card opens that
 * part of the menu; [compact] on the menu, where the row is its tabs.
 */
export function CategoryCards({
  categories,
  selected,
  onSelect,
  compact = false,
  ringId,
}: {
  categories: CategoryCard[];
  selected: string | null;
  onSelect: (id: string | null) => void;
  compact?: boolean;
  /** Shared-layout id of the ring, unique per row on screen. */
  ringId: string;
}) {
  const reduced = useReducedMotion();
  const tabs = compact;
  return (
    <div className={`h-scroll cat-cards ${compact ? 'cat-cards--compact' : ''}`} role={tabs ? 'tablist' : 'list'} aria-label="Categories">
      {categories.map((category, index) => {
        const isSelected = category.id === selected;
        return (
          <FadeIn key={category.id ?? 'all'} index={index} axis="x" className="cat-cards__item" role={tabs ? undefined : 'listitem'}>
            <motion.button
              type="button"
              role={tabs ? 'tab' : undefined}
              aria-selected={tabs ? isSelected : undefined}
              aria-label={`${category.label}, ${category.count} ${category.count === 1 ? 'dish' : 'dishes'}`}
              className={`cat-card ${isSelected ? 'is-active' : ''}`}
              whileTap={{ scale: 0.94 }}
              onClick={() => onSelect(category.id)}
            >
              <span className="cat-card__media">
                {category.id == null ? (
                  <span className="cat-card__all">
                    <UtensilsCrossed size={compact ? iconSize.lg : iconSize.xl} />
                  </span>
                ) : (
                  <FoodImage src={category.image} width="100%" height="100%" eager={index < 6} />
                )}
                {isSelected && (
                  <motion.span
                    layoutId={ringId}
                    className="cat-card__ring"
                    transition={reduced ? { duration: 0 } : { type: 'spring', stiffness: 460, damping: 36 }}
                  />
                )}
              </span>
              <span className="cat-card__label">{category.label}</span>
              {!compact && <span className="cat-card__count">{category.count} {category.count === 1 ? 'dish' : 'dishes'}</span>}
            </motion.button>
          </FadeIn>
        );
      })}
    </div>
  );
}
