import type { Paise } from './money';

type Json = Record<string, unknown>;

export interface MenuCategory {
  id: string;
  label: string;
  coverImage: string;
  sortOrder: number;
  /** Inactive categories (and their dishes) are hidden from guests. */
  isActive: boolean;
}

export function categoryFromJson(json: Json): MenuCategory {
  return {
    id: json.id as string,
    label: json.label as string,
    coverImage: (json.cover as string | undefined) ?? '',
    sortOrder: (json.sort as number | undefined) ?? 0,
    isActive: (json.active as boolean | undefined) ?? true,
  };
}

export type SpiceLevel = 'mild' | 'medium' | 'spicy';

export const spiceLevels: SpiceLevel[] = ['mild', 'medium', 'spicy'];

export const spiceLabel: Record<SpiceLevel, string> = { mild: 'Mild', medium: 'Medium', spicy: 'Spicy' };

const parseSpice = (name: unknown): SpiceLevel | null =>
  spiceLevels.includes(name as SpiceLevel) ? (name as SpiceLevel) : null;

export interface AddOn {
  id: string;
  name: string;
  price: Paise;
}

/** A portion size. The first option of a dish is its default. */
export interface PortionOption {
  id: string;
  label: string;
  extraPrice: Paise;
  detail: string | null;
}

export class MenuItem {
  constructor(
    readonly id: string,
    readonly name: string,
    readonly category: MenuCategory,
    readonly description: string,
    readonly shortDescription: string,
    readonly price: Paise,
    readonly image: string,
    readonly gallery: string[],
    readonly isVeg: boolean,
    readonly rating: number,
    readonly reviewCount: number,
    readonly isPopular: boolean,
    readonly isChefSpecial: boolean,
    readonly isFeatured: boolean,
    readonly hasSpiceLevel: boolean,
    readonly defaultSpice: SpiceLevel,
    readonly portions: PortionOption[],
    readonly addOns: AddOn[],
    readonly prepMinutes: number,
    /** Temporarily sold out (still listed, cannot be ordered). */
    readonly isAvailable: boolean,
    readonly isArchived: boolean,
  ) {}

  /** Unknown category ids fall back to a placeholder so a dish is never lost. */
  static fromJson(json: Json, categories: Map<string, MenuCategory>): MenuItem {
    const categoryId = json.category as string;
    return new MenuItem(
      json.id as string,
      json.name as string,
      categories.get(categoryId) ?? { id: categoryId, label: categoryId, coverImage: '', sortOrder: 0, isActive: true },
      (json.description as string | undefined) ?? '',
      (json.short as string | undefined) ?? '',
      json.price as number,
      (json.image as string | undefined) ?? '',
      ((json.gallery as unknown[] | undefined) ?? []).filter((p): p is string => typeof p === 'string' && p !== ''),
      (json.veg as boolean | undefined) ?? false,
      (json.rating as number | undefined) ?? 0,
      (json.reviews as number | undefined) ?? 0,
      (json.popular as boolean | undefined) ?? false,
      (json.special as boolean | undefined) ?? false,
      (json.featured as boolean | undefined) ?? false,
      (json.spicy as boolean | undefined) ?? false,
      parseSpice(json.defaultSpice) ?? 'medium',
      ((json.portions as Json[] | undefined) ?? []).map((p) => ({
        id: p.id as string,
        label: p.label as string,
        extraPrice: (p.extra as number | undefined) ?? 0,
        detail: (p.detail as string | undefined) ?? null,
      })),
      ((json.addOns as Json[] | undefined) ?? []).map((a) => ({
        id: a.id as string,
        name: a.name as string,
        price: a.price as number,
      })),
      (json.prep as number | undefined) ?? 15,
      (json.available as boolean | undefined) ?? true,
      (json.archived as boolean | undefined) ?? false,
    );
  }

  /** [image] followed by the gallery, without blanks or repeats. */
  get photos(): string[] {
    return [...new Set([...(this.image ? [this.image] : []), ...this.gallery])];
  }

  get defaultPortion(): PortionOption | null {
    return this.portions[0] ?? null;
  }

  get isCustomizable(): boolean {
    return this.hasSpiceLevel || this.portions.length > 1 || this.addOns.length > 0;
  }

  /** Whether guests can order it right now. */
  get isOrderable(): boolean {
    return this.isAvailable && !this.isArchived && this.category.isActive;
  }

  portionById(id: string | null): PortionOption | null {
    return this.portions.find((p) => p.id === id) ?? null;
  }

  addOnById(id: string): AddOn | null {
    return this.addOns.find((a) => a.id === id) ?? null;
  }
}

/** The options picked for a dish. Equal [key]s merge into one cart line. */
export class DishCustomization {
  readonly addOnIds: string[];

  constructor(
    readonly spice: SpiceLevel | null = null,
    readonly portionId: string | null = null,
    addOnIds: Iterable<string> = [],
  ) {
    // Sorted like Dart's String.compareTo (code units), so keys match.
    this.addOnIds = [...new Set(addOnIds)].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  }

  static defaultsFor(item: MenuItem): DishCustomization {
    return new DishCustomization(item.hasSpiceLevel ? item.defaultSpice : null, item.defaultPortion?.id ?? null);
  }

  static fromJson(json: Json): DishCustomization {
    return new DishCustomization(
      parseSpice(json.spice),
      (json.portion as string | undefined) ?? null,
      (json.addOns as string[] | undefined) ?? [],
    );
  }

  get key(): string {
    return `${this.spice ?? '-'}|${this.portionId ?? '-'}|${this.addOnIds.join(',')}`;
  }

  /** Extra cost on top of the dish's base price. */
  extraFor(item: MenuItem): Paise {
    let extra = item.portionById(this.portionId)?.extraPrice ?? 0;
    for (const id of this.addOnIds) extra += item.addOnById(id)?.price ?? 0;
    return extra;
  }

  /** e.g. `['Spice: Spicy', 'Large', 'Extra Cheese']`. */
  describe(item: MenuItem): string[] {
    const portion = item.portionById(this.portionId);
    return [
      ...(this.spice ? [`Spice: ${spiceLabel[this.spice]}`] : []),
      ...(portion && item.portions.length > 1 ? [portion.label] : []),
      ...this.addOnIds.flatMap((id) => {
        const addOn = item.addOnById(id);
        return addOn ? [addOn.name] : [];
      }),
    ];
  }

  toJson(): Json {
    return {
      ...(this.spice ? { spice: this.spice } : {}),
      ...(this.portionId ? { portion: this.portionId } : {}),
      ...(this.addOnIds.length ? { addOns: this.addOnIds } : {}),
    };
  }
}

/** One cart line: a dish, its customization and a quantity. */
export class CartItem {
  constructor(
    readonly item: MenuItem,
    readonly customization: DishCustomization,
    readonly quantity: number,
  ) {}

  static lineIdFor(item: MenuItem, customization: DishCustomization): string {
    return `${item.id}::${customization.key}`;
  }

  get id(): string {
    return CartItem.lineIdFor(this.item, this.customization);
  }

  get unitPrice(): Paise {
    return this.item.price + this.customization.extraFor(this.item);
  }

  get lineTotal(): Paise {
    return this.unitPrice * this.quantity;
  }

  get optionLabels(): string[] {
    return this.customization.describe(this.item);
  }

  withQuantity(quantity: number): CartItem {
    return new CartItem(this.item, this.customization, quantity);
  }

  /** `{itemId, quantity, options}`: what the server prices itself. */
  toJson(): Json {
    return { itemId: this.item.id, quantity: this.quantity, options: this.customization.toJson() };
  }
}

export type DietFilter = 'all' | 'veg' | 'nonVeg';

export const dietLabel: Record<DietFilter, string> = { all: 'All', veg: 'Veg', nonVeg: 'Non Veg' };

export type MenuSort = 'popularity' | 'rating' | 'priceLowToHigh' | 'priceHighToLow';

export const sortLabel: Record<MenuSort, string> = {
  popularity: 'Popularity',
  rating: 'Top rated',
  priceLowToHigh: 'Price: low to high',
  priceHighToLow: 'Price: high to low',
};

export interface MenuFilter {
  /** Null means every category. */
  categoryId: string | null;
  diet: DietFilter;
  query: string;
  sort: MenuSort;
  favoritesOnly: boolean;
}

export const defaultFilter: MenuFilter = {
  categoryId: null,
  diet: 'all',
  query: '',
  sort: 'popularity',
  favoritesOnly: false,
};

export const isDefaultFilter = (f: MenuFilter): boolean =>
  f.diet === 'all' && f.query.trim() === '' && f.sort === 'popularity';

function matches(filter: MenuFilter, item: MenuItem, favorites: ReadonlySet<string>): boolean {
  if (filter.categoryId != null && item.category.id !== filter.categoryId) return false;
  if (filter.diet === 'veg' && !item.isVeg) return false;
  if (filter.diet === 'nonVeg' && item.isVeg) return false;
  if (filter.favoritesOnly && !favorites.has(item.id)) return false;
  const q = filter.query.trim().toLowerCase();
  if (!q) return true;
  return (
    item.name.toLowerCase().includes(q) ||
    item.shortDescription.toLowerCase().includes(q) ||
    item.category.label.toLowerCase().includes(q)
  );
}

/** Category, diet, search and sort together; sold-out dishes go last. */
export function applyFilter(filter: MenuFilter, items: MenuItem[], favorites: ReadonlySet<string> = new Set()): MenuItem[] {
  const q = filter.query.trim().toLowerCase();
  const result = items.filter((item) => matches(filter, item, favorites));
  const byPopularity = (a: MenuItem, b: MenuItem) => {
    if (q) {
      const aName = a.name.toLowerCase().includes(q) ? 0 : 1;
      const bName = b.name.toLowerCase().includes(q) ? 0 : 1;
      if (aName !== bName) return aName - bName;
    }
    return b.reviewCount - a.reviewCount;
  };
  const sorters: Record<MenuSort, (a: MenuItem, b: MenuItem) => number> = {
    popularity: byPopularity,
    rating: (a, b) => b.rating - a.rating,
    priceLowToHigh: (a, b) => a.price - b.price,
    priceHighToLow: (a, b) => b.price - a.price,
  };
  result.sort(sorters[filter.sort]);
  return [...result.filter((i) => i.isOrderable), ...result.filter((i) => !i.isOrderable)];
}
