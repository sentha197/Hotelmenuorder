import { applyFilter, type MenuCategory, type MenuFilter, type MenuItem } from '../core/menu';
import type { MenuService } from '../services/menuService';
import { StorageKeys, type KeyValueStore } from '../services/storage';
import type { LoadState } from './settingsStore';
import { Store } from './store';

/** The menu as guests see it, and their favourites. */
export class CatalogStore extends Store {
  state: LoadState = 'idle';
  allItems: MenuItem[] = [];
  allCategories: MenuCategory[] = [];
  favorites = new Set<string>();
  private pending: Promise<void> | null = null;

  constructor(
    private readonly service: MenuService,
    private readonly storage: KeyValueStore,
    private readonly showSoldOut: () => boolean,
  ) {
    super();
    try {
      const saved = JSON.parse(storage.read(StorageKeys.favorites) ?? '[]') as unknown;
      if (Array.isArray(saved)) this.favorites = new Set(saved.filter((v): v is string => typeof v === 'string'));
    } catch {
      this.favorites = new Set();
    }
  }

  /** Not archived, in an active category, and sold-out ones unless hidden. */
  get items(): MenuItem[] {
    const showSoldOut = this.showSoldOut();
    return this.allItems.filter((i) => !i.isArchived && i.category.isActive && (i.isAvailable || showSoldOut));
  }

  get categories(): MenuCategory[] {
    return this.allCategories.filter((c) => c.isActive);
  }

  get popular(): MenuItem[] {
    return this.items.filter((i) => i.isPopular);
  }

  get chefSpecials(): MenuItem[] {
    return this.items.filter((i) => i.isChefSpecial);
  }

  /** Home banner dishes; one that cannot be ordered right now is skipped. */
  get banners(): MenuItem[] {
    return this.items.filter((i) => i.isFeatured && i.isOrderable);
  }

  /** Highly rated dishes not already featured as popular (or specials). */
  get recommended(): MenuItem[] {
    const orderable = this.items.filter((i) => i.isOrderable && !i.isPopular);
    const fresh = orderable.filter((i) => !i.isChefSpecial);
    return [...(fresh.length >= 3 ? fresh : orderable)].sort((a, b) => b.rating - a.rating).slice(0, 6);
  }

  /** Loads once; concurrent callers share the request. */
  load(force = false): Promise<void> {
    if (!force && this.state === 'ready') return Promise.resolve();
    return (this.pending ??= (async () => {
      this.state = 'loading';
      this.notify();
      try {
        const menu = await this.service.menu();
        this.allCategories = menu.categories;
        this.allItems = menu.items;
        this.state = 'ready';
      } catch {
        this.state = 'error';
      } finally {
        this.pending = null;
        this.notify();
      }
    })());
  }

  /** Re-reads without a loading state (live updates); keeps the menu on failure. */
  async refresh(): Promise<void> {
    if (this.state !== 'ready') return this.load(true);
    const menu = await this.service.menu();
    this.allCategories = menu.categories;
    this.allItems = menu.items;
    this.notify();
  }

  /** Settings that change what guests see were updated. */
  visibilityChanged(): void {
    this.notify();
  }

  /** Only dishes guests may see. */
  visibleById(id: string): MenuItem | null {
    return this.items.find((i) => i.id === id) ?? null;
  }

  categoryById(id: string): MenuCategory | null {
    return this.allCategories.find((c) => c.id === id) ?? null;
  }

  filter(filter: MenuFilter): MenuItem[] {
    return applyFilter(filter, this.items, this.favorites);
  }

  countIn(categoryId: string | null): number {
    return categoryId == null ? this.items.length : this.items.filter((i) => i.category.id === categoryId).length;
  }

  isFavorite(id: string): boolean {
    return this.favorites.has(id);
  }

  /** Returns the new favourite state. */
  toggleFavorite(id: string): boolean {
    const next = new Set(this.favorites);
    const added = !next.delete(id);
    if (added) next.add(id);
    this.favorites = next;
    this.storage.write(StorageKeys.favorites, JSON.stringify([...next]));
    this.notify();
    return added;
  }
}
