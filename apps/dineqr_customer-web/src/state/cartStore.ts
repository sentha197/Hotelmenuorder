import { CartItem, DishCustomization, type MenuItem } from '../core/menu';
import { sum, type Paise } from '../core/money';
import { BillBreakdown, DiscountOffer, type OfferError, type PricingConfig } from '../core/pricing';
import { StorageKeys, type KeyValueStore } from '../services/storage';
import { Store } from './store';

export type DecrementResult = 'decremented' | 'removed' | 'ambiguous' | 'notInCart';

export interface RemovedLine {
  line: CartItem;
  index: number;
}

/** The guest's cart: lines, quantities, special instructions and totals. */
export class CartStore extends Store {
  static readonly maxQuantity = 20;
  static readonly maxInstructionsLength = 200;

  lines: CartItem[] = [];
  instructions: string;
  offerCode: string | null;
  private readonly lastCustomization = new Map<string, DishCustomization>();
  private hydrated = false;

  constructor(
    private readonly storage: KeyValueStore,
    private readonly pricing: () => PricingConfig,
    private readonly offerLookup: (code: string) => DiscountOffer | null,
  ) {
    super();
    this.instructions = storage.read(StorageKeys.instructions) ?? '';
    this.offerCode = storage.read(StorageKeys.offer);
  }

  get isEmpty(): boolean {
    return this.lines.length === 0;
  }

  get totalQuantity(): number {
    return this.lines.reduce((total, line) => total + line.quantity, 0);
  }

  get subtotal(): Paise {
    return sum(this.lines.map((l) => l.lineTotal));
  }

  /** Restaurant pricing (tax, service charge or offers) changed. */
  pricingChanged(): void {
    this.notify();
  }

  get appliedOffer(): DiscountOffer | null {
    return this.offerCode == null ? null : this.offerLookup(this.offerCode);
  }

  /** Why the applied offer does not reduce the bill now, if it doesn't. */
  get offerProblem(): OfferError | null {
    if (this.offerCode == null) return null;
    const offer = this.appliedOffer;
    return offer ? offer.check(this.subtotal) : 'unknownCode';
  }

  get discount(): Paise {
    return this.appliedOffer?.discountFor(this.subtotal) ?? 0;
  }

  get bill(): BillBreakdown {
    const offer = this.appliedOffer;
    const amount = this.discount;
    return BillBreakdown.fromSubtotal(this.subtotal, this.pricing(), amount, offer && amount ? `Offer ${offer.code}` : null);
  }

  /** An error when the code cannot be used at all; a code below its minimum is kept. */
  applyOffer(code: string): OfferError | null {
    const normalized = DiscountOffer.normalize(code);
    const offer = this.offerLookup(normalized);
    if (!offer) return 'unknownCode';
    if (!offer.isActive) return 'inactive';
    this.offerCode = normalized;
    this.storage.write(StorageKeys.offer, normalized);
    this.notify();
    return offer.check(this.subtotal);
  }

  removeOffer(): void {
    if (this.offerCode == null) return;
    this.offerCode = null;
    this.storage.delete(StorageKeys.offer);
    this.notify();
  }

  /** Lines whose dish can no longer be ordered. */
  get unavailableLines(): CartItem[] {
    return this.lines.filter((l) => !l.item.isOrderable);
  }

  /** Longest preparation time among the dishes. */
  get estimatedPrepMinutes(): number {
    return this.lines.reduce((max, l) => Math.max(max, l.item.prepMinutes), 0);
  }

  /** Restores the saved cart once the menu is known (unknown dishes dropped). */
  hydrate(menu: MenuItem[]): void {
    if (this.hydrated) return;
    this.hydrated = true;
    if (this.lines.length) return;
    const raw = this.storage.read(StorageKeys.cart);
    if (!raw) return;
    try {
      const byId = new Map(menu.map((m) => [m.id, m]));
      const restored: CartItem[] = [];
      for (const json of JSON.parse(raw) as Record<string, unknown>[]) {
        const item = byId.get(json.itemId as string);
        if (!item) continue;
        const quantity = Math.min(Math.max(Number(json.quantity) || 1, 1), CartStore.maxQuantity);
        restored.push(new CartItem(item, DishCustomization.fromJson((json.options as Record<string, unknown>) ?? {}), quantity));
      }
      this.lines = restored;
    } catch {
      this.lines = [];
    }
    this.notify();
  }

  /** New prices and options take effect; archived dishes are removed. */
  syncWithMenu(menu: MenuItem[]): number {
    if (!this.lines.length) return 0;
    const byId = new Map(menu.map((m) => [m.id, m]));
    let removed = 0;
    let changed = false;
    const next: CartItem[] = [];
    for (const line of this.lines) {
      const latest = byId.get(line.item.id);
      if (!latest || latest.isArchived) {
        removed++;
        changed = true;
      } else if (latest !== line.item) {
        next.push(new CartItem(latest, line.customization, line.quantity));
        changed = true;
      } else {
        next.push(line);
      }
    }
    if (changed) {
      this.lines = next;
      this.changed();
    }
    return removed;
  }

  quantityOfItem(itemId: string): number {
    return this.lines.filter((l) => l.item.id === itemId).reduce((total, l) => total + l.quantity, 0);
  }

  /** Identical customizations merge into one line. */
  add(item: MenuItem, customization: DishCustomization | null = null, quantity = 1): CartItem {
    if (quantity < 1) throw new RangeError('quantity must be at least 1');
    if (!item.isOrderable) throw new Error(`${item.name} is not available right now.`);
    const options = customization ?? DishCustomization.defaultsFor(item);
    const lineId = CartItem.lineIdFor(item, options);
    const index = this.lines.findIndex((l) => l.id === lineId);
    let result: CartItem;
    if (index === -1) {
      result = new CartItem(item, options, Math.min(quantity, CartStore.maxQuantity));
      this.lines = [...this.lines, result];
    } else {
      const existing = this.lines[index]!;
      result = existing.withQuantity(Math.min(existing.quantity + quantity, CartStore.maxQuantity));
      this.lines = this.lines.map((l, i) => (i === index ? result : l));
    }
    this.lastCustomization.set(item.id, options);
    this.changed();
    return result;
  }

  /** "+" from a list: repeats the last customization chosen for this dish. */
  quickAdd(item: MenuItem): CartItem {
    return this.add(item, this.lastCustomization.get(item.id) ?? null);
  }

  /** "−" from a list. */
  quickRemove(item: MenuItem): DecrementResult {
    const matching = this.lines.filter((l) => l.item.id === item.id);
    if (!matching.length) return 'notInCart';
    if (matching.length > 1) return 'ambiguous';
    return this.decrement(matching[0]!.id);
  }

  increment(lineId: string): void {
    const line = this.lines.find((l) => l.id === lineId);
    if (!line || line.quantity >= CartStore.maxQuantity || !line.item.isOrderable) return;
    this.lines = this.lines.map((l) => (l.id === lineId ? l.withQuantity(l.quantity + 1) : l));
    this.changed();
  }

  /** A line at quantity 1 is removed. */
  decrement(lineId: string): DecrementResult {
    const line = this.lines.find((l) => l.id === lineId);
    if (!line) return 'notInCart';
    if (line.quantity <= 1) {
      this.lines = this.lines.filter((l) => l.id !== lineId);
      this.changed();
      return 'removed';
    }
    this.lines = this.lines.map((l) => (l.id === lineId ? l.withQuantity(l.quantity - 1) : l));
    this.changed();
    return 'decremented';
  }

  remove(lineId: string): RemovedLine | null {
    const index = this.lines.findIndex((l) => l.id === lineId);
    if (index === -1) return null;
    const line = this.lines[index]!;
    this.lines = this.lines.filter((_, i) => i !== index);
    this.changed();
    return { line, index };
  }

  /** Puts back a removed line (undo). */
  restore(removed: RemovedLine): void {
    if (this.lines.some((l) => l.id === removed.line.id)) {
      this.add(removed.line.item, removed.line.customization, removed.line.quantity);
      return;
    }
    const next = [...this.lines];
    next.splice(Math.min(removed.index, next.length), 0, removed.line);
    this.lines = next;
    this.changed();
  }

  /** Empties the cart; instructions and offer too unless kept. */
  clear(keepInstructions = false): void {
    this.lines = [];
    if (!keepInstructions) {
      this.instructions = '';
      this.offerCode = null;
      this.storage.delete(StorageKeys.offer);
    }
    this.changed();
  }

  updateInstructions(value: string): void {
    const text = value.slice(0, CartStore.maxInstructionsLength);
    if (text === this.instructions) return;
    this.instructions = text;
    this.storage.write(StorageKeys.instructions, text);
    this.notify();
  }

  private changed(): void {
    this.storage.write(StorageKeys.cart, JSON.stringify(this.lines.map((l) => l.toJson())));
    this.storage.write(StorageKeys.instructions, this.instructions);
    this.notify();
  }
}
