import { Currency, type Paise } from './money';

type Json = Record<string, unknown>;

/** A menu category (restaurant data, edited in Menu › Categories). */
export interface MenuCategory {
  id: string;
  label: string;
  coverImage: string;
  /** Position in menus (lower first). */
  sortOrder: number;
  /** Inactive categories (and their dishes) are hidden from guests. */
  isActive: boolean;
}

export function categoryFromJson(json: Json): MenuCategory {
  return {
    id: String(json.id),
    label: String(json.label ?? ''),
    coverImage: (json.cover as string | undefined) ?? '',
    sortOrder: (json.sort as number | undefined) ?? 0,
    isActive: (json.active as boolean | undefined) ?? true,
  };
}

export const categoryToJson = (c: MenuCategory) => ({
  id: c.id,
  label: c.label,
  cover: c.coverImage,
  sort: c.sortOrder,
  active: c.isActive,
});

export type SpiceLevel = 'mild' | 'medium' | 'spicy';
export const spiceLevels: readonly SpiceLevel[] = ['mild', 'medium', 'spicy'];
export const spiceLabel: Record<SpiceLevel, string> = { mild: 'Mild', medium: 'Medium', spicy: 'Spicy' };

/** A paid extra that can be added to a dish (e.g. extra cheese). */
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

export interface MenuItem {
  id: string;
  name: string;
  /** The category id; [category] resolves it. */
  category: MenuCategory;
  description: string;
  shortDescription: string;
  price: Paise;
  image: string;
  gallery: string[];
  isVeg: boolean;
  rating: number;
  reviewCount: number;
  isPopular: boolean;
  isChefSpecial: boolean;
  /** Shown as a banner in the guest home screen carousel. */
  isFeatured: boolean;
  hasSpiceLevel: boolean;
  defaultSpice: SpiceLevel;
  portions: PortionOption[];
  addOns: AddOn[];
  prepMinutes: number;
  /** Temporarily sold out (still listed, cannot be ordered). */
  isAvailable: boolean;
  /** Removed from the menu but kept for history and possible restore. */
  isArchived: boolean;
}

/** [categories] resolves the stored category id; unknown ids get a placeholder so a dish is never lost. */
export function itemFromJson(json: Json, categories: Map<string, MenuCategory>): MenuItem {
  const categoryId = String(json.category);
  return {
    id: String(json.id),
    name: String(json.name ?? ''),
    category: categories.get(categoryId) ?? { id: categoryId, label: categoryId, coverImage: '', sortOrder: 0, isActive: true },
    description: (json.description as string | undefined) ?? '',
    shortDescription: (json.short as string | undefined) ?? '',
    price: json.price as number,
    image: (json.image as string | undefined) ?? '',
    gallery: ((json.gallery as unknown[] | undefined) ?? []).filter((p): p is string => typeof p === 'string' && p.length > 0),
    isVeg: (json.veg as boolean | undefined) ?? false,
    rating: Number(json.rating ?? 0),
    reviewCount: (json.reviews as number | undefined) ?? 0,
    isPopular: (json.popular as boolean | undefined) ?? false,
    isChefSpecial: (json.special as boolean | undefined) ?? false,
    isFeatured: (json.featured as boolean | undefined) ?? false,
    hasSpiceLevel: (json.spicy as boolean | undefined) ?? false,
    defaultSpice: spiceLevels.includes(json.defaultSpice as SpiceLevel) ? (json.defaultSpice as SpiceLevel) : 'medium',
    portions: ((json.portions as Json[] | undefined) ?? []).map((p) => ({
      id: String(p.id),
      label: String(p.label ?? ''),
      extraPrice: (p.extra as number | undefined) ?? 0,
      detail: (p.detail as string | undefined) ?? null,
    })),
    addOns: ((json.addOns as Json[] | undefined) ?? []).map((a) => ({ id: String(a.id), name: String(a.name ?? ''), price: a.price as number })),
    prepMinutes: (json.prep as number | undefined) ?? 15,
    isAvailable: (json.available as boolean | undefined) ?? true,
    isArchived: (json.archived as boolean | undefined) ?? false,
  };
}

/** Exactly the keys `MenuItem.toJson` sends (`PUT /admin/menu/items/{id}`). */
export function itemToJson(item: MenuItem): Json {
  return {
    id: item.id,
    name: item.name,
    category: item.category.id,
    description: item.description,
    short: item.shortDescription,
    price: item.price,
    image: item.image,
    ...(item.gallery.length ? { gallery: item.gallery } : {}),
    veg: item.isVeg,
    rating: item.rating,
    reviews: item.reviewCount,
    ...(item.isPopular ? { popular: true } : {}),
    ...(item.isChefSpecial ? { special: true } : {}),
    ...(item.isFeatured ? { featured: true } : {}),
    ...(item.hasSpiceLevel ? { spicy: true } : {}),
    defaultSpice: item.defaultSpice,
    ...(item.portions.length
      ? {
          portions: item.portions.map((p) => ({
            id: p.id,
            label: p.label,
            ...(p.extraPrice !== 0 ? { extra: p.extraPrice } : {}),
            ...(p.detail != null ? { detail: p.detail } : {}),
          })),
        }
      : {}),
    ...(item.addOns.length ? { addOns: item.addOns.map((a) => ({ id: a.id, name: a.name, price: a.price })) } : {}),
    prep: item.prepMinutes,
    ...(!item.isAvailable ? { available: false } : {}),
    ...(item.isArchived ? { archived: true } : {}),
  };
}

/** Whether guests can order it right now. */
export const isOrderable = (item: MenuItem) => item.isAvailable && !item.isArchived && item.category.isActive;

/** What one of [item] costs as ordered without extras (its default portion). */
export const defaultUnitPrice = (item: MenuItem): Paise => item.price + (item.portions[0]?.extraPrice ?? 0);

/** The photos that ship with the app (also on the server's public menu). */
export const bundledImages: readonly string[] = [
  'assets/images/affogato.jpg',
  'assets/images/butter_chicken.jpg',
  'assets/images/butter_naan.jpg',
  'assets/images/chicken_65.jpg',
  'assets/images/chicken_biryani.jpg',
  'assets/images/chilli_chicken.jpg',
  'assets/images/cold_coffee.jpg',
  'assets/images/dal_makhani.jpg',
  'assets/images/french_fries.jpg',
  'assets/images/fresh_lime_soda.jpg',
  'assets/images/gulab_jamun.jpg',
  'assets/images/lassi.jpg',
  'assets/images/masala_dosa.jpg',
  'assets/images/paneer_butter_masala.jpg',
  'assets/images/paneer_tikka.jpg',
  'assets/images/rasmalai.jpg',
  'assets/images/samosa.jpg',
  'assets/images/spring_roll.jpg',
  'assets/images/tandoori_chicken.jpg',
  'assets/images/veg_biryani.jpg',
  'assets/images/veg_manchurian.jpg',
];

export const isNetworkImage = (path: string) => path.startsWith('https://') || path.startsWith('http://');

/** A dish or offer photo must be blank, a bundled photo, or a URL the server returned from an upload. */
export const isAllowedImage = (image: string) => image === '' || bundledImages.includes(image) || isNetworkImage(image);

/** A unique id derived from [name], e.g. `paneer_roll` (`_2`, `_3` when taken). */
export function uniqueId(name: string, taken: Set<string>, fallback: string): string {
  let base = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!base) base = fallback;
  let id = base;
  let n = 2;
  while (taken.has(id)) id = `${base}_${n++}`;
  return id;
}

export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

/**
 * A file extension for [bytes] from their leading bytes, or null. Only used
 * to name the upload; which formats are accepted is the server's call.
 */
export function extensionFor(bytes: Uint8Array): string | null {
  const matches = (offset: number, signature: number[]) =>
    bytes.length >= offset + signature.length && signature.every((b, i) => bytes[offset + i] === b);
  const codes = (s: string) => Array.from(s, (c) => c.charCodeAt(0));
  const brand = (name: string) => matches(4, [0x66, 0x74, 0x79, 0x70]) && matches(8, codes(name));
  if (matches(0, [0xff, 0xd8, 0xff])) return 'jpg';
  if (matches(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
  if (matches(0, codes('GIF8'))) return 'gif';
  if (matches(0, codes('RIFF')) && matches(8, codes('WEBP'))) return 'webp';
  if (brand('avif') || brand('avis')) return 'avif';
  if (['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].some(brand)) return 'heic';
  if (matches(0, codes('BM'))) return 'bmp';
  return null;
}

/** Checks a picture before upload (size only: formats are the server's call). */
export function uploadProblem(bytes: Uint8Array, what: 'photo' | 'picture' | 'image'): string | null {
  if (bytes.length === 0) return `That ${what} file is empty.`;
  if (bytes.length > MAX_UPLOAD_BYTES) {
    return `That ${what === 'image' ? 'image' : what} is too large. The limit is ${MAX_UPLOAD_BYTES / (1024 * 1024)} MB.`;
  }
  return null;
}

/** Returns a message for the first invalid field of a dish, or null (CatalogController.validateItem). */
export function validateItem(item: MenuItem, all: readonly MenuItem[], categories: readonly MenuCategory[]): string | null {
  const name = item.name.trim();
  if (name.length < 2 || name.length > 40) return 'Dish name must be 2 to 40 characters.';
  const duplicate = all.some((o) => o.id !== item.id && !o.isArchived && o.name.trim().toLowerCase() === name.toLowerCase());
  if (duplicate) return `Another dish is already called "${name}".`;
  if (item.shortDescription.trim().length > 60) return 'Short description can be at most 60 characters.';
  if (item.description.trim().length > 400) return 'Description can be at most 400 characters.';
  if (item.price < 100 || item.price > 10_000_000) {
    return `Price must be between ${Currency.format(100)} and ${Currency.format(10_000_000)}.`;
  }
  if (item.prepMinutes < 1 || item.prepMinutes > 180) return 'Preparation time must be 1 to 180 minutes.';
  if (!categories.some((c) => c.id === item.category.id)) return 'Choose a category.';
  const portionIds = new Set<string>();
  for (const portion of item.portions) {
    if (!portion.label.trim()) return 'Every portion needs a name.';
    if (portionIds.has(portion.id)) return 'Portion names must be unique.';
    portionIds.add(portion.id);
    if (portion.extraPrice < 0) return 'Portion surcharges cannot be negative.';
  }
  const addOnIds = new Set<string>();
  for (const addOn of item.addOns) {
    if (!addOn.name.trim()) return 'Every add-on needs a name.';
    if (addOnIds.has(addOn.id)) return 'Add-on names must be unique.';
    addOnIds.add(addOn.id);
    if (addOn.price < 0 || addOn.price > 1_000_000) {
      return `Add-on prices must be between ${Currency.format(0)} and ${Currency.format(1_000_000)}.`;
    }
  }
  if (!isAllowedImage(item.image)) return 'Choose a bundled photo or upload one.';
  return null;
}

export function validateCategory(category: MenuCategory, categories: readonly MenuCategory[]): string | null {
  const label = category.label.trim();
  if (label.length < 2 || label.length > 24) return 'Category name must be 2 to 24 characters.';
  if (categories.some((c) => c.id !== category.id && c.label.trim().toLowerCase() === label.toLowerCase())) {
    return `A category called "${label}" already exists.`;
  }
  if (category.coverImage && !bundledImages.includes(category.coverImage)) return 'Choose one of the available photos.';
  return null;
}

/** The menu as staff see it: every category and dish, and every offer. */
export interface StaffMenu {
  categories: MenuCategory[];
  items: MenuItem[];
  promotions: Json[];
}
