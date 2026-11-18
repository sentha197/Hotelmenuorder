import { Archive, ArchiveRestore, ArrowDown, ArrowUp, Check, GripVertical, LayoutList, Pencil, Plus, Shapes, SearchX, Trash2, UtensilsCrossed, X } from 'lucide-react';
import { motion, Reorder, useDragControls } from 'motion/react';
import { useEffect, useMemo, useState } from 'react';
import { useFieldArray, useForm, type UseFormRegisterReturn } from 'react-hook-form';
import { useNavigate, useParams } from 'react-router';
import { FoodImage, VegMark } from '@/components/domain/Domain';
import { Badge } from '@/components/ui/Badge';
import { Button, IconButton } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { Dialog, confirmDialog } from '@/components/ui/Dialog';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { FilterChips, SearchField, Segmented, Select, Switch, SwitchRow, TextArea, TextField } from '@/components/ui/Form';
import { ActionMenu } from '@/components/ui/Menu';
import { Page } from '@/components/ui/Page';
import { ValidationError } from '@/core/access';
import { spiceLabel, spiceLevels, uniqueId, type AddOn, type MenuCategory, type MenuItem, type PortionOption, type SpiceLevel } from '@/core/menu';
import { Currency, parseRupees } from '@/core/money';
import { deleteCategory, reorderCategories, saveCategory, saveMenuItem, setCategoryActive, setDishArchived, setDishAvailable, uploadDishPhoto } from '@/state/actions';
import { useMenu } from '@/state/data';
import { runAction, useAction } from '@/state/run';
import { useAccess } from '@/state/session';
import { PhotoField, PhotoPicker } from './PhotoField';

type DishFilter = 'all' | 'available' | 'soldOut' | 'archived';
const dishFilterLabel: Record<DishFilter, string> = { all: 'All', available: 'Available', soldOut: 'Sold out', archived: 'Archived' };
const matchesDish = (f: DishFilter, i: MenuItem) =>
  f === 'all' ? !i.isArchived : f === 'available' ? !i.isArchived && i.isAvailable : f === 'soldOut' ? !i.isArchived && !i.isAvailable : i.isArchived;

/** Dishes and categories (MenuAdminScreen). */
export function MenuPage() {
  const navigate = useNavigate();
  const { can } = useAccess();
  const query = useMenu();
  const items = query.data?.items ?? [];
  const categories = useMemo(() => [...(query.data?.categories ?? [])].sort((a, b) => a.sortOrder - b.sortOrder), [query.data]);
  const [tab, setTab] = useState<'dishes' | 'categories'>('dishes');
  const [editing, setEditing] = useState<MenuCategory | 'new' | null>(null);
  const canEdit = can('manageMenu');
  const canEditCategories = can('manageCategories');

  return (
    <Page
      title="Menu"
      subtitle={`${items.filter((i) => !i.isArchived).length} dishes · ${categories.length} categories`}
      actions={
        tab === 'dishes'
          ? canEdit && (
              <Button variant="primary" icon={Plus} onClick={() => navigate('/menu/dishes/new')}>
                Add dish
              </Button>
            )
          : canEditCategories && (
              <Button variant="primary" icon={Plus} onClick={() => setEditing('new')}>
                Add category
              </Button>
            )
      }
    >
      <Segmented
        name="menu-tab"
        value={tab}
        onChange={setTab}
        options={[
          { value: 'dishes', label: 'Dishes', icon: <UtensilsCrossed size={16} aria-hidden /> },
          { value: 'categories', label: 'Categories', icon: <Shapes size={16} aria-hidden /> },
        ]}
      />
      {query.isPending ? (
        <PageSkeleton />
      ) : tab === 'dishes' ? (
        <Dishes items={items} categories={categories} canEdit={canEdit} />
      ) : (
        <Categories categories={categories} items={items} canEdit={canEditCategories} onEdit={setEditing} />
      )}
      <CategoryDialog category={editing} categories={categories} onClose={() => setEditing(null)} />
    </Page>
  );
}

function Dishes({ items, categories, canEdit }: { items: MenuItem[]; categories: MenuCategory[]; canEdit: boolean }) {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<DishFilter>('all');
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const q = search.trim().toLowerCase();
  const dishes = items
    .filter((i) => matchesDish(filter, i) && (categoryId == null || i.category.id === categoryId) && (!q || i.name.toLowerCase().includes(q)))
    .sort((a, b) => a.category.sortOrder - b.category.sortOrder || a.name.localeCompare(b.name));
  return (
    <>
      <SearchField value={search} onChange={setSearch} placeholder="Search dishes" />
      <div className="flex flex-col gap-2.5">
        <FilterChips name="dish-filter" values={['all', 'available', 'soldOut', 'archived'] as DishFilter[]} selected={filter} labelOf={(f) => dishFilterLabel[f]} countOf={(f) => items.filter((i) => matchesDish(f, i)).length} onSelect={setFilter} />
        <FilterChips name="dish-category" values={[null, ...categories.map((c) => c.id)]} selected={categoryId} labelOf={(id) => (id == null ? 'All categories' : (categories.find((c) => c.id === id)?.label ?? id))} onSelect={setCategoryId} />
      </div>
      {dishes.length === 0 ? (
        <Empty icon={SearchX} title="No dishes here" message="Try another filter, or add a dish." />
      ) : (
        <div className="grid gap-3 md:grid-cols-2 2xl:grid-cols-3">
          {dishes.map((item, i) => (
            <motion.div
              key={item.id}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: Math.min(i, 18) * 0.02 }}
              className={cn('panel flex items-center gap-3 p-3 pr-4', canEdit && 'cursor-pointer hover:border-line-strong')}
              onClick={canEdit ? () => navigate(`/menu/dishes/${encodeURIComponent(item.id)}`) : undefined}
            >
              <div className={cn('shrink-0', (item.isArchived || !item.isAvailable) && 'opacity-50')}>
                <FoodImage src={item.image} size={60} />
              </div>
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1.5 text-[14px] font-semibold text-ink">
                  <VegMark veg={item.isVeg} size={11} />
                  <span className="truncate">{item.name}</span>
                </p>
                <p className="truncate text-[12px] text-muted">
                  {item.category.label} · <span className="tabular">{Currency.format(item.price)}</span>
                </p>
                <div className="mt-1 flex flex-wrap gap-1">
                  {item.isArchived && <Badge tone="muted">Archived</Badge>}
                  {!item.isArchived && !item.isAvailable && <Badge tone="warning">Sold out</Badge>}
                  {item.isPopular && <Badge tone="ember">Popular</Badge>}
                  {item.isChefSpecial && <Badge tone="brand">Chef's special</Badge>}
                </div>
              </div>
              <div onClick={(e) => e.stopPropagation()}>
                {!item.isArchived ? (
                  <Switch
                    checked={item.isAvailable}
                    tone="success"
                    disabled={!canEdit}
                    label={`${item.name} available`}
                    onChange={(on) => void runAction(() => setDishAvailable(item, on), { success: on ? `${item.name} is available` : `${item.name} marked sold out` })}
                  />
                ) : (
                  canEdit && (
                    <Button size="sm" icon={ArchiveRestore} onClick={() => void runAction(() => setDishArchived(item, false), { success: `${item.name} restored` })}>
                      Restore
                    </Button>
                  )
                )}
              </div>
            </motion.div>
          ))}
        </div>
      )}
    </>
  );
}

function Categories({ categories, items, canEdit, onEdit }: { categories: MenuCategory[]; items: MenuItem[]; canEdit: boolean; onEdit: (c: MenuCategory) => void }) {
  const [order, setOrder] = useState(categories.map((c) => c.id));
  useEffect(() => setOrder(categories.map((c) => c.id)), [categories]);
  const byId = new Map(categories.map((c) => [c.id, c]));
  const dishCount = (id: string) => items.filter((i) => !i.isArchived && i.category.id === id).length;
  const commit = (ids: string[]) => {
    if (ids.join() === categories.map((c) => c.id).join()) return;
    void runAction(() => reorderCategories(ids));
  };
  const move = (index: number, delta: number) => {
    const ids = [...order];
    const target = index + delta;
    if (target < 0 || target >= ids.length) return;
    [ids[index], ids[target]] = [ids[target]!, ids[index]!];
    setOrder(ids);
    commit(ids);
  };
  return (
    <>
      {canEdit && <p className="text-[12.5px] text-muted">Drag (or use the arrows) to change the order guests see. Hidden categories and their dishes are not shown to guests.</p>}
      <SectionCard bodyClassName="!p-2">
        <Reorder.Group axis="y" values={order} onReorder={canEdit ? setOrder : () => undefined} className="flex flex-col">
          {order.map((id, index) => {
            const c = byId.get(id);
            if (!c) return null;
            return <CategoryRow key={id} category={c} index={index} count={order.length} dishes={dishCount(id)} canEdit={canEdit} onEdit={() => onEdit(c)} onMove={move} onDrop={() => commit(order)} />;
          })}
        </Reorder.Group>
      </SectionCard>
    </>
  );
}

function CategoryRow({ category: c, index, count, dishes, canEdit, onEdit, onMove, onDrop }: { category: MenuCategory; index: number; count: number; dishes: number; canEdit: boolean; onEdit: () => void; onMove: (index: number, delta: number) => void; onDrop: () => void }) {
  const controls = useDragControls();
  const remove = async () => {
    const ok = await confirmDialog({ title: `Delete ${c.label}?`, message: 'Only empty categories can be deleted. This cannot be undone.', confirmLabel: 'Delete', icon: Trash2, danger: true });
    if (ok) await runAction(() => deleteCategory(c), { success: `${c.label} deleted` });
  };
  return (
    <Reorder.Item value={c.id} dragListener={false} dragControls={controls} onDragEnd={onDrop} className="flex items-center gap-3 rounded-xl bg-panel-solid/0 px-2 py-2.5 hover:bg-panel-2/60" whileDrag={{ scale: 1.02, boxShadow: 'var(--shadow-lg)' }}>
      {canEdit && (
        <button type="button" aria-label={`Drag ${c.label}`} onPointerDown={(e) => controls.start(e)} className="grid h-9 w-7 cursor-grab touch-none place-items-center text-faint active:cursor-grabbing">
          <GripVertical size={18} aria-hidden />
        </button>
      )}
      <FoodImage src={c.coverImage} size={44} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[14px] font-semibold text-ink">{c.label}</p>
        <p className="text-[12px] text-muted">
          {dishes} dishes{c.isActive ? '' : ' · hidden from guests'}
        </p>
      </div>
      {canEdit && (
        <div className="hidden gap-0.5 sm:flex">
          <IconButton icon={ArrowUp} label={`Move ${c.label} up`} size="sm" disabled={index === 0} onClick={() => onMove(index, -1)} />
          <IconButton icon={ArrowDown} label={`Move ${c.label} down`} size="sm" disabled={index === count - 1} onClick={() => onMove(index, 1)} />
        </div>
      )}
      <Switch checked={c.isActive} disabled={!canEdit} label={`${c.label} shown to guests`} onChange={(on) => void runAction(() => setCategoryActive(c, on))} />
      {canEdit && (
        <ActionMenu
          label="Category actions"
          actions={[
            { label: 'Edit', icon: Pencil, onSelect: onEdit },
            { label: 'Delete', icon: Trash2, danger: true, onSelect: () => void remove() },
          ]}
        />
      )}
    </Reorder.Item>
  );
}

function CategoryDialog({ category, categories, onClose }: { category: MenuCategory | 'new' | null; categories: MenuCategory[]; onClose: () => void }) {
  const [name, setName] = useState('');
  const [cover, setCover] = useState('');
  const [shown, setShown] = useState<MenuCategory | 'new' | null>(null);
  const { pending, run } = useAction();
  if (category && category !== shown) {
    setShown(category);
    setName(category === 'new' ? '' : category.label);
    setCover(category === 'new' ? '' : category.coverImage);
  }
  const existing = category === 'new' || category == null ? null : category;
  const save = async () => {
    const saved: MenuCategory = existing
      ? { ...existing, label: name, coverImage: cover }
      : { id: uniqueId(name, new Set(categories.map((c) => c.id)), 'category'), label: name, coverImage: cover, sortOrder: categories.length, isActive: true };
    const ok = await run(() => saveCategory(saved), { success: `Saved ${saved.label.trim()}` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={category != null}
      onClose={onClose}
      title={existing ? 'Edit category' : 'New category'}
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void save()}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 pb-2">
        <TextField label="Name" maxLength={24} showCount value={name} onChange={(e) => setName(e.target.value)} />
        <div>
          <p className="mb-2 text-[12.5px] font-medium text-muted">Cover photo</p>
          <PhotoPicker selected={cover} onSelect={setCover} />
        </div>
      </div>
    </Dialog>
  );
}

// ----------------------------------------------------------------- editor

interface OptionRow {
  name: string;
  detail: string;
  price: string;
}

interface DishForm {
  name: string;
  categoryId: string;
  price: string;
  prep: string;
  isVeg: boolean;
  short: string;
  description: string;
  image: string;
  available: boolean;
  popular: boolean;
  special: boolean;
  featured: boolean;
  spicy: boolean;
  defaultSpice: SpiceLevel;
  portions: OptionRow[];
  addOns: OptionRow[];
}

/** Adds or edits a dish (DishEditorScreen). */
export function DishEditorPage() {
  const { itemId } = useParams();
  const query = useMenu();
  if (query.isPending) return <Page title="Dish" back="/menu"><PageSkeleton rows={3} /></Page>;
  const original = itemId ? query.data?.items.find((i) => i.id === itemId) : undefined;
  if (itemId && !original) {
    return (
      <Page title="Dish" back="/menu">
        <Empty icon={UtensilsCrossed} title="Dish not found" message="It may have been removed." />
      </Page>
    );
  }
  return <DishEditor key={itemId ?? 'new'} original={original ?? null} items={query.data?.items ?? []} categories={[...(query.data?.categories ?? [])].sort((a, b) => a.sortOrder - b.sortOrder)} />;
}

function DishEditor({ original, items, categories }: { original: MenuItem | null; items: MenuItem[]; categories: MenuCategory[] }) {
  const navigate = useNavigate();
  const { pending, run } = useAction();
  const { register, control, watch, setValue, handleSubmit } = useForm<DishForm>({
    defaultValues: {
      name: original?.name ?? '',
      categoryId: original?.category.id ?? categories[0]?.id ?? '',
      price: original ? Currency.plain(original.price) : '',
      prep: String(original?.prepMinutes ?? 15),
      isVeg: original?.isVeg ?? true,
      short: original?.shortDescription ?? '',
      description: original?.description ?? '',
      image: original?.image ?? '',
      available: original?.isAvailable ?? true,
      popular: original?.isPopular ?? false,
      special: original?.isChefSpecial ?? false,
      featured: original?.isFeatured ?? false,
      spicy: original?.hasSpiceLevel ?? false,
      defaultSpice: original?.defaultSpice ?? 'medium',
      portions: (original?.portions ?? []).map((p) => ({ name: p.label, detail: p.detail ?? '', price: p.extraPrice === 0 ? '' : Currency.plain(p.extraPrice) })),
      addOns: (original?.addOns ?? []).map((a) => ({ name: a.name, detail: '', price: Currency.plain(a.price) })),
    },
  });
  const portions = useFieldArray({ control, name: 'portions' });
  const addOns = useFieldArray({ control, name: 'addOns' });
  const v = watch();

  /** The dish from the form, or a ValidationError for fields that cannot even be parsed. */
  const build = (f: DishForm): MenuItem => {
    const price = parseRupees(f.price);
    if (price == null) throw new ValidationError('Enter a price, e.g. 180 or 180.50.');
    const prep = /^[+-]?\d+$/.test(f.prep.trim()) ? Number.parseInt(f.prep.trim(), 10) : NaN;
    if (!Number.isFinite(prep)) throw new ValidationError('Enter the preparation time in minutes.');
    const category = categories.find((c) => c.id === f.categoryId);
    if (!category) throw new ValidationError('Choose a category.');
    const portionIds = new Set<string>();
    const builtPortions: PortionOption[] = [];
    for (const row of f.portions) {
      const label = row.name.trim();
      if (!label && !row.price.trim()) continue;
      const extra = row.price.trim() ? parseRupees(row.price) : 0;
      if (extra == null) throw new ValidationError(`Check the surcharge for "${label}".`);
      const id = uniqueId(label, portionIds, 'option');
      portionIds.add(id);
      builtPortions.push({ id, label, extraPrice: extra, detail: row.detail.trim() || null });
    }
    const addOnIds = new Set<string>();
    const builtAddOns: AddOn[] = [];
    for (const row of f.addOns) {
      const name = row.name.trim();
      if (!name && !row.price.trim()) continue;
      const addOnPrice = parseRupees(row.price);
      if (addOnPrice == null) throw new ValidationError(`Enter a price for the add-on "${name}".`);
      const id = uniqueId(name, addOnIds, 'option');
      addOnIds.add(id);
      builtAddOns.push({ id, name, price: addOnPrice });
    }
    const base: MenuItem = original ?? {
      id: uniqueId(f.name, new Set(items.map((i) => i.id)), 'dish'),
      name: '',
      category,
      description: '',
      shortDescription: '',
      price,
      image: '',
      gallery: [],
      isVeg: f.isVeg,
      rating: 0,
      reviewCount: 0,
      isPopular: false,
      isChefSpecial: false,
      isFeatured: false,
      hasSpiceLevel: false,
      defaultSpice: 'medium',
      portions: [],
      addOns: [],
      prepMinutes: 15,
      isAvailable: true,
      isArchived: false,
    };
    return {
      ...base,
      name: f.name,
      category,
      description: f.description,
      shortDescription: f.short,
      price,
      image: f.image,
      isVeg: f.isVeg,
      isPopular: f.popular,
      isChefSpecial: f.special,
      isFeatured: f.featured,
      hasSpiceLevel: f.spicy,
      defaultSpice: f.defaultSpice,
      portions: builtPortions,
      addOns: builtAddOns,
      prepMinutes: prep,
      isAvailable: f.available,
    };
  };

  const save = handleSubmit(async (f) => {
    const ok = await run(() => saveMenuItem(build(f)), { success: `Saved ${f.name.trim()}` });
    if (ok) navigate('/menu');
  });

  const archive = async (archived: boolean) => {
    if (!original) return;
    if (archived) {
      const ok = await confirmDialog({
        title: `Archive ${original.name}?`,
        message: 'Guests will no longer see it. Past orders and bills keep it. You can restore it from the Archived filter.',
        confirmLabel: 'Archive',
        icon: Archive,
      });
      if (!ok) return;
    }
    const done = await runAction(() => setDishArchived(original, archived), { success: archived ? `${original.name} archived` : `${original.name} restored` });
    if (done) navigate('/menu');
  };

  return (
    <Page title={original ? `Edit ${original.name}` : 'New dish'} back="/menu" width="medium">
      <form onSubmit={save} className="flex flex-col gap-5" noValidate>
        {original && <Notice tone="info">Price changes apply to new orders only. Existing orders and bills keep the price they were placed at.</Notice>}
        <SectionCard title="Basics" index={0}>
          <div className="grid gap-4 sm:grid-cols-2">
            <TextField label="Name" maxLength={40} showCount value={v.name} wrapperClassName="sm:col-span-2" {...register('name')} />
            <Select label="Category" {...register('categoryId')}>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.isActive ? c.label : `${c.label} (hidden)`}
                </option>
              ))}
            </Select>
            <div className="grid grid-cols-2 gap-3">
              <TextField label="Price" inputMode="decimal" prefix={Currency.symbol} {...register('price')} />
              <TextField label="Prep time" inputMode="numeric" suffix="min" {...register('prep')} />
            </div>
            <Segmented
              name="dish-veg"
              className="sm:col-span-2"
              value={v.isVeg}
              onChange={(on) => setValue('isVeg', on)}
              options={[
                { value: true, label: 'Veg', icon: <VegMark veg size={12} /> },
                { value: false, label: 'Non-veg', icon: <VegMark veg={false} size={12} /> },
              ]}
            />
          </div>
        </SectionCard>

        <SectionCard title="Description" index={1}>
          <div className="flex flex-col gap-4">
            <TextField label="Short description (menu list)" maxLength={60} showCount value={v.short} {...register('short')} />
            <TextArea label="Full description (dish page)" maxLength={400} showCount rows={4} value={v.description} {...register('description')} />
          </div>
        </SectionCard>

        <SectionCard title="Photo" subtitle="Upload a photo of the dish, or pick one of the bundled sample photos." index={2}>
          <PhotoField image={v.image} onChange={(url) => setValue('image', url)} upload={uploadDishPhoto} />
        </SectionCard>

        <SectionCard title="Visibility" index={3}>
          <div className="divide-y divide-line">
            <SwitchRow title="Available to order" description="Turn off to show it as sold out." checked={v.available} onChange={(on) => setValue('available', on)} tone="success" />
            <SwitchRow title="Popular" description="Shown in Popular Dishes on the home screen." checked={v.popular} onChange={(on) => setValue('popular', on)} />
            <SwitchRow title="Chef's special" description="Shown in Chef's Specials with a badge." checked={v.special} onChange={(on) => setValue('special', on)} />
            <SwitchRow title="Home banner" description="Shown as a banner at the top of the home screen. Turn off to remove it." checked={v.featured} onChange={(on) => setValue('featured', on)} />
          </div>
        </SectionCard>

        <SectionCard title="Customisation" index={4}>
          <SwitchRow title="Spice level choice" description="Guests pick mild, medium or spicy." checked={v.spicy} onChange={(on) => setValue('spicy', on)} />
          {v.spicy && (
            <div className="mt-2 max-w-xs">
              <Select label="Default spice level" {...register('defaultSpice')}>
                {spiceLevels.map((s) => (
                  <option key={s} value={s}>
                    {spiceLabel[s]}
                  </option>
                ))}
              </Select>
            </div>
          )}
          <OptionEditor
            title="Portions"
            hint="The first portion is the default. Leave empty for a single size."
            priceLabel="Surcharge"
            withDetail
            rows={portions.fields}
            register={(i, key) => register(`portions.${i}.${key}`)}
            onAdd={() => portions.append({ name: '', detail: '', price: '' })}
            onRemove={(i) => portions.remove(i)}
          />
          <OptionEditor
            title="Paid add-ons"
            hint="Optional extras guests can tick."
            priceLabel="Price"
            rows={addOns.fields}
            register={(i, key) => register(`addOns.${i}.${key}`)}
            onAdd={() => addOns.append({ name: '', detail: '', price: '' })}
            onRemove={(i) => addOns.remove(i)}
          />
        </SectionCard>

        <div className="flex flex-col gap-3 sm:flex-row">
          <Button type="submit" variant="primary" size="lg" icon={Check} loading={pending} className="sm:flex-1">
            {original ? 'Save changes' : 'Add dish'}
          </Button>
          {original && (
            <Button size="lg" icon={original.isArchived ? ArchiveRestore : Archive} onClick={() => void archive(!original.isArchived)}>
              {original.isArchived ? 'Restore dish' : 'Archive dish'}
            </Button>
          )}
        </div>
      </form>
    </Page>
  );
}

function OptionEditor({
  title,
  hint,
  priceLabel,
  withDetail,
  rows,
  register,
  onAdd,
  onRemove,
}: {
  title: string;
  hint: string;
  priceLabel: string;
  withDetail?: boolean;
  rows: { id: string }[];
  register: (index: number, key: keyof OptionRow) => UseFormRegisterReturn;
  onAdd: () => void;
  onRemove: (index: number) => void;
}) {
  return (
    <div className="mt-5 border-t border-line pt-4">
      <p className="text-[14px] font-semibold text-ink">{title}</p>
      <p className="text-[12.5px] text-muted">{hint}</p>
      <div className="mt-3 flex flex-col gap-2.5">
        {rows.map((row, i) => (
          <motion.div
            key={row.id}
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            className={cn('grid items-end gap-2 rounded-xl border border-line p-3 sm:border-0 sm:p-0', withDetail ? 'sm:grid-cols-[1.4fr_1fr_120px_auto]' : 'sm:grid-cols-[1fr_140px_auto]')}
          >
            <TextField label="Name" {...register(i, 'name')} />
            {withDetail && <TextField label="Detail" {...register(i, 'detail')} />}
            <TextField label={priceLabel} inputMode="decimal" prefix={Currency.symbol} {...register(i, 'price')} />
            <IconButton icon={X} label={`Remove ${title.toLowerCase()} row`} className="justify-self-end" onClick={() => onRemove(i)} />
          </motion.div>
        ))}
      </div>
      <Button size="sm" variant="ghost" icon={LayoutList} className="mt-3" onClick={onAdd}>
        Add {title.toLowerCase().replace('paid ', '')}
      </Button>
    </div>
  );
}
