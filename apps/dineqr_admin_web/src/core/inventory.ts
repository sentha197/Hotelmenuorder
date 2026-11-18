import { parseInstant } from './time';

type Json = Record<string, unknown>;

/** A stocked ingredient or supply. Quantities change only through recorded adjustments. */
export interface InventoryItem {
  id: string;
  name: string;
  /** e.g. `kg`, `L`, `pcs`. */
  unit: string;
  quantity: number;
  /** At or below this level the item is flagged as low stock. */
  reorderLevel: number;
  updatedAt: Date;
  supplier: string;
  /** Dishes that cannot be served without this item. */
  linkedDishIds: string[];
  isDemoSample: boolean;
}

export const inventoryItemFromJson = (json: Json): InventoryItem => ({
  id: String(json.id),
  name: String(json.name ?? ''),
  unit: String(json.unit ?? ''),
  quantity: Number(json.qty ?? 0),
  reorderLevel: Number(json.reorder ?? 0),
  updatedAt: parseInstant(json.updated),
  supplier: (json.supplier as string | undefined) ?? '',
  linkedDishIds: ((json.dishes as unknown[] | undefined) ?? []).map(String),
  isDemoSample: (json.demo as boolean | undefined) ?? false,
});

/** One change to an item's stock level. */
export interface StockMovement {
  id: string;
  itemId: string;
  /** Positive for stock received, negative for usage or waste. */
  change: number;
  /** Quantity after the change. */
  balance: number;
  reason: string;
  at: Date;
  by: string;
}

export const movementFromJson = (json: Json): StockMovement => ({
  id: String(json.id),
  itemId: String(json.item),
  change: Number(json.change ?? 0),
  balance: Number(json.balance ?? 0),
  reason: (json.reason as string | undefined) ?? '',
  at: parseInstant(json.at),
  by: (json.by as string | undefined) ?? '',
});

export const Stock = {
  isOut: (i: InventoryItem) => i.quantity <= 0,
  isLow: (i: InventoryItem) => i.quantity > 0 && i.quantity <= i.reorderLevel,
  units: ['kg', 'g', 'L', 'ml', 'pcs', 'packs'] as const,
  /** `2`, `2.5`, `2.25` (InventoryController.format). */
  format(value: number): string {
    if (value === Math.round(value)) return value.toFixed(0);
    return value.toFixed(value * 10 === Math.round(value * 10) ? 1 : 2);
  },
  addReasons: ['Delivery received', 'Count correction'] as const,
  removeReasons: ['Used in kitchen', 'Wasted', 'Count correction'] as const,
};

/** InventoryController.validate. */
export function validateInventoryItem(item: InventoryItem, items: readonly InventoryItem[]): string | null {
  const name = item.name.trim();
  if (name.length < 2 || name.length > 40) return 'Item name must be 2 to 40 characters.';
  if (items.some((i) => i.id !== item.id && i.name.toLowerCase() === name.toLowerCase())) return `"${name}" is already in the inventory.`;
  if (!(Stock.units as readonly string[]).includes(item.unit)) return 'Choose a unit.';
  if (item.quantity < 0 || item.quantity > 100000) return 'Quantity must be between 0 and 100000.';
  if (item.reorderLevel < 0 || item.reorderLevel > 100000) return 'Reorder level must be between 0 and 100000.';
  if (item.supplier.length > 40) return 'Supplier can be at most 40 characters.';
  return null;
}

/** InventoryController.newItemId. */
export function newInventoryId(name: string, items: readonly InventoryItem[]): string {
  const base = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  let id = `inv_${base || 'item'}`;
  let n = 2;
  while (items.some((i) => i.id === id)) id = `inv_${base}_${n++}`;
  return id;
}
