import { BadgePercent, Check, Layers, Pencil, Plus, SearchX, Tag as TagIcon, Ticket, Trash2, X } from 'lucide-react';
import { motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router';
import { FoodImage, OfferStatusChip, QuantityStepper, VegMark } from '@/components/domain/Domain';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { Dialog, confirmDialog } from '@/components/ui/Dialog';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { Field, SearchField, Segmented, Switch, SwitchRow, TextArea, TextField } from '@/components/ui/Form';
import { ActionMenu } from '@/components/ui/Menu';
import { Page } from '@/components/ui/Page';
import { ValidationError } from '@/core/access';
import { defaultUnitPrice, uniqueId, type MenuItem } from '@/core/menu';
import { Currency, formatRate, parsePercent, parseRupees } from '@/core/money';
import {
  Combos,
  comboViewOf,
  Coupons,
  discountTypeLabel,
  MAX_COMBO_QUANTITY,
  OfferRules,
  promotionKindLabel,
  Promotions,
  usageText,
  validateDates,
  type DiscountOffer,
  type DiscountType,
  type Promotion,
  type PromotionKind,
} from '@/core/offers';
import { deleteCoupon, deletePromotion, saveCoupon, savePromotion, setCouponActive, setPromotionActive, uploadOfferPhoto } from '@/state/actions';
import { useMenu, useSettings } from '@/state/data';
import { runAction, useAction } from '@/state/run';
import { PhotoField } from '../menu/PhotoField';

type Tab = 'specials' | 'combos' | 'coupons';
const tabInfo: Record<Tab, { label: string; newLabel: string; help: string }> = {
  specials: {
    label: 'Special offers',
    newLabel: 'New offer',
    help: 'A discount on chosen dishes, applied by itself: guests see the offer price on the menu. A dish gets one special offer (the best); a coupon applies on top.',
  },
  combos: {
    label: 'Combos',
    newLabel: 'New combo',
    help: 'Dishes sold together for one price, added to the cart as one item. Guests see what the dishes cost separately and what they save.',
  },
  coupons: {
    label: 'Coupons',
    newLabel: 'New coupon',
    help: 'Codes guests enter in their cart. A coupon applies after any special offer or combo saving, and its minimum order counts what is left.',
  },
};

/** Special offers, combos and coupons (OffersScreen). */
export function OffersPage() {
  const navigate = useNavigate();
  const menuQuery = useMenu();
  const { settings } = useSettings();
  const [tab, setTab] = useState<Tab>('specials');
  const [coupon, setCoupon] = useState<DiscountOffer | 'new' | null>(null);
  const promotions = useMemo(() => [...(menuQuery.data?.promotions ?? [])].sort(Promotions.byOrder), [menuQuery.data]);
  const today = OfferRules.today();
  const live = promotions.filter((p) => Promotions.isLiveOn(p, today)).length + settings.offers.filter((o) => Coupons.isLiveOn(o, today)).length;

  const create = () => (tab === 'coupons' ? setCoupon('new') : navigate(`/offers/new/${tab === 'combos' ? 'combo' : 'special'}`));

  return (
    <Page
      title="Offers"
      subtitle={`${live} live now · special offers, combos and coupons`}
      actions={
        <Button variant="primary" icon={Plus} onClick={create}>
          {tabInfo[tab].newLabel}
        </Button>
      }
    >
      <Segmented
        name="offers-tab"
        value={tab}
        onChange={setTab}
        options={[
          { value: 'specials', label: 'Special offers', icon: <BadgePercent size={16} aria-hidden /> },
          { value: 'combos', label: 'Combos', icon: <Layers size={16} aria-hidden /> },
          { value: 'coupons', label: 'Coupons', icon: <Ticket size={16} aria-hidden /> },
        ]}
      />
      <p className="-mt-2 max-w-3xl text-[12.5px] leading-relaxed text-muted">{tabInfo[tab].help}</p>
      {menuQuery.isPending ? (
        <PageSkeleton />
      ) : tab === 'coupons' ? (
        <CouponList offers={settings.offers} today={today} onEdit={setCoupon} />
      ) : (
        <PromotionList promotions={promotions.filter((p) => p.kind === (tab === 'combos' ? 'combo' : 'special'))} items={menuQuery.data?.items ?? []} today={today} kind={tab === 'combos' ? 'combo' : 'special'} />
      )}
      <CouponDialog offer={coupon} onClose={() => setCoupon(null)} />
    </Page>
  );
}

function PromotionList({ promotions, items, today, kind }: { promotions: Promotion[]; items: MenuItem[]; today: Date; kind: PromotionKind }) {
  const navigate = useNavigate();
  const menu = new Map(items.map((i) => [i.id, i]));
  if (promotions.length === 0) {
    return kind === 'combo' ? (
      <Empty icon={Layers} title="No combos" message="Create one, e.g. a biryani, a starter and a drink." />
    ) : (
      <Empty icon={BadgePercent} title="No special offers" message="Create one, e.g. 20% off starters this weekend." />
    );
  }
  const remove = async (p: Promotion) => {
    const ok = await confirmDialog({ title: `Delete ${p.title}?`, message: 'Guests will no longer see it. Orders that used it keep what they were charged.', confirmLabel: 'Delete', icon: Trash2, danger: true });
    if (ok) await runAction(() => deletePromotion(p), { success: `${p.title} deleted` });
  };
  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {promotions.map((p, i) => {
        const view = p.kind === 'combo' ? comboViewOf(p, menu) : null;
        const dishes = p.items.map((it) => menu.get(it.itemId)).filter((d): d is MenuItem => d != null && !d.isArchived);
        const image = p.image || (view ? Combos.image(view) : (dishes[0]?.image ?? ''));
        const what =
          p.kind === 'combo'
            ? [view ? Combos.partLabels(view).join(' + ') : '', [Currency.format(p.comboPrice ?? 0), ...(view && Combos.saving(view) ? [`saves ${Currency.format(Combos.saving(view))}`] : [])].join(' · ')].filter(Boolean).join('\n')
            : `${Promotions.badge(p)} · ${dishes.map((d) => d.name).join(', ')}`;
        const edit = () => navigate(`/offers/edit/${encodeURIComponent(p.id)}`);
        return (
          <motion.div key={p.id} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: Math.min(i, 12) * 0.03 }} className="panel flex items-start gap-3 p-4">
            <button type="button" onClick={edit} className="shrink-0" aria-label={`Edit ${p.title}`}>
              <FoodImage src={image} size={64} />
            </button>
            <button type="button" onClick={edit} className="min-w-0 flex-1 text-left">
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-[14.5px] font-semibold text-ink">{p.title}</span>
                <OfferStatusChip status={Promotions.status(p, today)} />
              </div>
              <p className="mt-1 line-clamp-3 whitespace-pre-line text-[12.5px] text-muted">{what}</p>
              <p className="mt-1 text-[11.5px] text-faint">
                {OfferRules.validity(p.startsOn, p.endsOn)} · {usageText(p.usedCount, p.usageLimit)}
              </p>
            </button>
            <div className="flex shrink-0 flex-col items-end gap-2">
              <Switch checked={p.isActive} label={`${p.title} active`} onChange={(on) => void runAction(() => setPromotionActive(p, on))} />
              <ActionMenu
                actions={[
                  { label: 'Edit', icon: Pencil, onSelect: edit },
                  { label: 'Delete', icon: Trash2, danger: true, onSelect: () => void remove(p) },
                ]}
              />
            </div>
          </motion.div>
        );
      })}
    </div>
  );
}

function CouponList({ offers, today, onEdit }: { offers: DiscountOffer[]; today: Date; onEdit: (o: DiscountOffer) => void }) {
  if (offers.length === 0) return <Empty icon={Ticket} title="No coupons" message="Add a code such as WELCOME10." />;
  const remove = async (o: DiscountOffer) => {
    const ok = await confirmDialog({ title: `Delete ${o.code}?`, message: 'Guests will no longer be able to use this code.', confirmLabel: 'Delete', icon: Trash2, danger: true });
    if (ok) await runAction(() => deleteCoupon(o.code), { success: `${o.code} deleted` });
  };
  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {offers.map((o, i) => (
        <motion.div key={o.code} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: Math.min(i, 12) * 0.03 }} className="panel relative flex items-start gap-3 overflow-hidden p-4">
          <span className="absolute inset-y-0 left-0 w-1 bg-[linear-gradient(180deg,#ff8a00,#d62828)]" aria-hidden />
          <span className="ml-1 grid h-11 w-11 shrink-0 place-items-center rounded-xl border border-dashed border-ember-text/50 text-ember-text">
            <TagIcon size={18} aria-hidden />
          </span>
          <button type="button" onClick={() => onEdit(o)} className="min-w-0 flex-1 text-left">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-mono text-[14px] font-bold tracking-wider text-ink">{o.code}</span>
              <span className="text-[13px] text-muted">· {o.title}</span>
              <OfferStatusChip status={Coupons.status(o, today)} />
            </div>
            <p className="mt-1 text-[12.5px] text-muted">{Coupons.summary(o)}</p>
            <p className="text-[11.5px] text-faint">
              {OfferRules.validity(o.startsOn, o.endsOn)} · {usageText(o.usedCount, o.usageLimit)}
            </p>
          </button>
          <div className="flex shrink-0 flex-col items-end gap-2">
            <Switch checked={o.isActive} label={`${o.code} active`} onChange={(on) => void runAction(() => setCouponActive(o.code, on))} />
            <ActionMenu
              actions={[
                { label: 'Edit', icon: Pencil, onSelect: () => onEdit(o) },
                { label: 'Delete', icon: Trash2, danger: true, onSelect: () => void remove(o) },
              ]}
            />
          </div>
        </motion.div>
      ))}
    </div>
  );
}

/** First and last day (restaurant days, both included; empty = open). */
function DatesField({ startsOn, endsOn, onChange }: { startsOn: Date | null; endsOn: Date | null; onChange: (startsOn: Date | null, endsOn: Date | null) => void }) {
  const field = (label: string, value: Date | null, placeholder: string, set: (d: Date | null) => void) => (
    <Field label={label} hint={value ? undefined : placeholder}>
      <div className="relative">
        <input type="date" className="field pr-10" value={value ? OfferRules.dayJson(value) : ''} onChange={(e) => set(OfferRules.parseDay(e.target.value))} aria-label={label} />
        {value && (
          <button type="button" aria-label={`Clear ${label}`} onClick={() => set(null)} className="absolute right-2 top-1/2 grid h-7 w-7 -translate-y-1/2 place-items-center rounded-lg text-muted hover:bg-panel-3">
            <X size={14} aria-hidden />
          </button>
        )}
      </div>
    </Field>
  );
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {field('First day', startsOn, 'From now', (d) => onChange(d, endsOn))}
      {field('Last day', endsOn, 'No end date', (d) => onChange(startsOn, d))}
    </div>
  );
}

/** Empty = no limit; anything that is not a whole number is -1 (UsageLimitField.parse). */
const parseLimit = (text: string) => (text.trim() ? (/^\d+$/.test(text.trim()) ? Number(text.trim()) : -1) : null);

function UsageLimit({ value, onChange, used }: { value: string; onChange: (v: string) => void; used: number }) {
  return (
    <TextField
      label="Usage limit (optional)"
      inputMode="numeric"
      suffix="orders"
      value={value}
      onChange={(e) => onChange(e.target.value.replace(/\D/g, ''))}
      hint={used === 0 ? 'Each order that saves with it counts once. Cancelled orders give their use back.' : `${usageText(used, null)} so far. Cancelled orders give their use back.`}
    />
  );
}

/** A coupon's code, title, discount, minimum order, cap, dates and usage limit (CouponDialog). */
function CouponDialog({ offer, onClose }: { offer: DiscountOffer | 'new' | null; onClose: () => void }) {
  const [shown, setShown] = useState<DiscountOffer | 'new' | null>(null);
  const [code, setCode] = useState('');
  const [title, setTitle] = useState('');
  const [type, setType] = useState<DiscountType>('percent');
  const [value, setValue] = useState('');
  const [min, setMin] = useState('');
  const [max, setMax] = useState('');
  const [limit, setLimit] = useState('');
  const [startsOn, setStartsOn] = useState<Date | null>(null);
  const [endsOn, setEndsOn] = useState<Date | null>(null);
  const [error, setError] = useState<string | null>(null);
  const { pending, run } = useAction();
  if (offer && offer !== shown) {
    const o = offer === 'new' ? null : offer;
    setShown(offer);
    setCode(o?.code ?? '');
    setTitle(o?.title ?? '');
    setType(o?.type ?? 'percent');
    setValue(o == null ? '' : o.type === 'percent' ? formatRate(o.value).replace('%', '') : String(Math.floor(o.value / 100)));
    setMin(o == null || o.minSubtotal === 0 ? '' : String(Math.floor(o.minSubtotal / 100)));
    setMax(o?.maxDiscount == null ? '' : String(Math.floor(o.maxDiscount / 100)));
    setLimit(o?.usageLimit == null ? '' : String(o.usageLimit));
    setStartsOn(o?.startsOn ?? null);
    setEndsOn(o?.endsOn ?? null);
    setError(null);
  }
  const existing = offer === 'new' || offer == null ? null : offer;
  const submit = async () => {
    const parsedValue = type === 'percent' ? parsePercent(value) : parseRupees(value);
    const parsedMin = min.trim() ? parseRupees(min) : 0;
    const parsedMax = max.trim() ? parseRupees(max) : null;
    const parsedLimit = parseLimit(limit);
    if (parsedValue == null || parsedMin == null || (max.trim() && parsedMax == null)) return setError('Check the amounts.');
    if (parsedLimit === -1) return setError('The usage limit is a whole number of orders.');
    const dates = validateDates(startsOn, endsOn);
    if (dates) return setError(dates);
    setError(null);
    const result: DiscountOffer = {
      code,
      title,
      type,
      value: parsedValue,
      minSubtotal: parsedMin,
      maxDiscount: type === 'percent' ? parsedMax : null,
      isActive: existing?.isActive ?? true,
      startsOn,
      endsOn,
      usageLimit: parsedLimit,
      usedCount: existing?.usedCount ?? 0,
    };
    const ok = await run(() => saveCoupon(result, existing?.code ?? null), { success: `Coupon ${result.code.toUpperCase()} saved` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={offer != null}
      onClose={onClose}
      title={existing ? `Edit ${existing.code}` : 'New coupon'}
      icon={Ticket}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4 pb-2">
        <div className="grid gap-3 sm:grid-cols-2">
          <TextField label="Code" maxLength={16} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} className="font-mono tracking-wider" />
          <TextField label="Title" maxLength={40} value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
        <Segmented
          name="coupon-type"
          value={type}
          onChange={setType}
          options={(['percent', 'flat'] as DiscountType[]).map((t) => ({ value: t, label: discountTypeLabel[t] }))}
        />
        <TextField label={type === 'percent' ? 'Discount' : 'Amount off'} inputMode="decimal" suffix={type === 'percent' ? '%' : undefined} prefix={type === 'flat' ? Currency.symbol : undefined} value={value} onChange={(e) => setValue(e.target.value)} />
        <div className="grid gap-3 sm:grid-cols-2">
          <TextField label="Minimum order (optional)" inputMode="numeric" prefix={Currency.symbol} hint="After any special offer or combo saving." value={min} onChange={(e) => setMin(e.target.value)} />
          {type === 'percent' && <TextField label="Maximum discount (optional)" inputMode="numeric" prefix={Currency.symbol} value={max} onChange={(e) => setMax(e.target.value)} />}
        </div>
        <DatesField startsOn={startsOn} endsOn={endsOn} onChange={(a, b) => (setStartsOn(a), setEndsOn(b))} />
        <UsageLimit value={limit} onChange={setLimit} used={existing?.usedCount ?? 0} />
        {error && (
          <p role="alert" className="text-[12.5px] text-danger">
            {error}
          </p>
        )}
      </div>
    </Dialog>
  );
}

/** Creates or edits a special offer or a combo (PromotionEditorScreen). */
export function PromotionEditorPage() {
  const { kind: kindParam, promotionId } = useParams();
  const query = useMenu();
  if (query.isPending) return <Page title="Offer" back="/offers"><PageSkeleton rows={3} /></Page>;
  const original = promotionId ? query.data?.promotions.find((p) => p.id === promotionId) : undefined;
  if (promotionId && !original) {
    return (
      <Page title="Offer" back="/offers">
        <Empty icon={SearchX} title="Offer not found" message="It may have been deleted on another device." />
      </Page>
    );
  }
  const kind: PromotionKind = original?.kind ?? (kindParam === 'combo' ? 'combo' : 'special');
  return <PromotionEditor key={promotionId ?? kind} kind={kind} original={original ?? null} items={query.data?.items ?? []} promotions={query.data?.promotions ?? []} />;
}

function PromotionEditor({ kind, original, items, promotions }: { kind: PromotionKind; original: Promotion | null; items: MenuItem[]; promotions: Promotion[] }) {
  const navigate = useNavigate();
  const isCombo = kind === 'combo';
  const what = isCombo ? 'combo' : 'special offer';
  const [title, setTitle] = useState(original?.title ?? '');
  const [description, setDescription] = useState(original?.description ?? '');
  const [image, setImage] = useState(original?.image ?? '');
  const [type, setType] = useState<DiscountType>(original?.discountType ?? 'percent');
  const [value, setValue] = useState(original && !isCombo ? (original.discountType === 'percent' ? formatRate(original.discountValue).replace('%', '') : Currency.plain(original.discountValue)) : '');
  const [price, setPrice] = useState(original?.comboPrice == null ? '' : Currency.plain(original.comboPrice));
  const [limit, setLimit] = useState(original?.usageLimit == null ? '' : String(original.usageLimit));
  const [startsOn, setStartsOn] = useState<Date | null>(original?.startsOn ?? null);
  const [endsOn, setEndsOn] = useState<Date | null>(original?.endsOn ?? null);
  const [active, setActive] = useState(original?.isActive ?? true);
  /** Dish id → quantity (always 1 for special offers), in display order. */
  const [dishes, setDishes] = useState<[string, number][]>(original?.items.map((i) => [i.itemId, i.quantity]) ?? []);
  const [choosing, setChoosing] = useState(false);
  const { pending, run } = useAction();
  const menu = new Map(items.map((i) => [i.id, i]));
  const original$ = dishes.reduce((sum, [id, q]) => sum + (menu.get(id) ? defaultUnitPrice(menu.get(id)!) * q : 0), 0);
  const parsedPrice = parseRupees(price);

  /** The form as an offer, or a ValidationError when a number is not one. */
  const build = (): Promotion => {
    let discountValue = 0;
    let comboPrice: number | null = null;
    if (isCombo) {
      comboPrice = parseRupees(price);
      if (comboPrice == null) throw new ValidationError('Enter the combo price.');
    } else {
      const parsed = type === 'percent' ? parsePercent(value) : parseRupees(value);
      if (parsed == null) throw new ValidationError('Enter the discount.');
      discountValue = parsed;
    }
    const usageLimit = parseLimit(limit);
    if (usageLimit === -1) throw new ValidationError('The usage limit is a whole number of orders.');
    let id = original?.id;
    if (!id) {
      let base = `${kind}_${title}`;
      if (base.length > 34) base = base.slice(0, 34);
      id = uniqueId(base, new Set([...promotions.map((p) => p.id), ...items.map((i) => i.id)]), kind);
    }
    return {
      id,
      kind,
      title,
      description,
      image,
      startsOn,
      endsOn,
      isActive: active,
      usageLimit,
      usedCount: original?.usedCount ?? 0,
      sortOrder: original?.sortOrder ?? 0,
      discountType: type,
      discountValue,
      comboPrice,
      items: dishes.map(([itemId, quantity]) => ({ itemId, quantity: isCombo ? quantity : 1 })),
    };
  };

  const save = async () => {
    const ok = await run(() => savePromotion(build()), { success: `Saved ${title.trim()}` });
    if (ok) navigate('/offers');
  };

  return (
    <Page title={original ? `Edit ${original.title}` : `New ${what}`} subtitle={promotionKindLabel[kind]} back="/offers" width="medium">
      {original && <Notice tone="info">Changes apply to new orders only. Orders already placed keep what they were charged.</Notice>}
      <SectionCard title="Basics" index={0}>
        <div className="flex flex-col gap-4">
          <TextField label="Title" placeholder={isCombo ? 'e.g. Family Feast' : 'e.g. Weekend Snack Hour'} maxLength={60} showCount value={title} onChange={(e) => setTitle(e.target.value)} />
          <TextArea label="Description (optional)" placeholder="Shown to guests with the offer." maxLength={300} showCount value={description} onChange={(e) => setDescription(e.target.value)} />
        </div>
      </SectionCard>

      {isCombo ? (
        <SectionCard title="Dishes and price" subtitle="Guests add the combo as one item. Its dishes come with their default options, and the kitchen sees each of them." index={1}>
          {dishes.length > 0 && (
            <ul className="mb-4 divide-y divide-line">
              {dishes.map(([id, quantity]) => {
                const item = menu.get(id);
                if (!item) return null;
                return (
                  <li key={id} className="flex items-center gap-3 py-2.5">
                    <FoodImage src={item.image} size={44} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13.5px] font-semibold text-ink">{item.name}</p>
                      <p className="text-[12px] text-faint">{Currency.format(defaultUnitPrice(item))} each{item.isAvailable && !item.isArchived && item.category.isActive ? '' : ' · sold out now'}</p>
                    </div>
                    <QuantityStepper
                      quantity={quantity}
                      max={MAX_COMBO_QUANTITY}
                      label={item.name}
                      onIncrement={() => setDishes((d) => d.map(([i, q]) => [i, i === id ? q + 1 : q]))}
                      onDecrement={() => setDishes((d) => (quantity <= 1 ? d.filter(([i]) => i !== id) : d.map(([i, q]) => [i, i === id ? q - 1 : q])))}
                    />
                  </li>
                );
              })}
            </ul>
          )}
          <Button icon={Plus} onClick={() => setChoosing(true)}>
            {dishes.length === 0 ? 'Add dishes' : 'Change dishes'}
          </Button>
          <div className="mt-4 max-w-xs">
            <TextField
              label="Combo price"
              inputMode="decimal"
              prefix={Currency.symbol}
              value={price}
              onChange={(e) => setPrice(e.target.value)}
              hint={dishes.length === 0 ? 'Add dishes to see what they cost separately.' : `Separately: ${Currency.format(original$)}${parsedPrice != null && original$ > parsedPrice ? ` · guests save ${Currency.format(original$ - parsedPrice)}` : ''}`}
            />
          </div>
        </SectionCard>
      ) : (
        <SectionCard title="Discount" subtitle="Taken off each of the chosen dishes, with no code. When a dish is in more than one offer, guests get the bigger saving; a coupon still applies on top." index={1}>
          <Segmented name="promo-type" value={type} onChange={setType} options={(['percent', 'flat'] as DiscountType[]).map((t) => ({ value: t, label: discountTypeLabel[t] }))} />
          <div className="mt-4 max-w-xs">
            <TextField label={type === 'percent' ? 'Discount per dish' : 'Amount off per dish'} inputMode="decimal" suffix={type === 'percent' ? '%' : undefined} prefix={type === 'flat' ? Currency.symbol : undefined} value={value} onChange={(e) => setValue(e.target.value)} />
          </div>
          <div className="mt-4">
            <p className="mb-2 text-[12.5px] font-medium text-muted">{dishes.length === 0 ? 'No dishes chosen yet' : `${dishes.length} ${dishes.length === 1 ? 'dish' : 'dishes'}`}</p>
            <div className="flex flex-wrap gap-2">
              {dishes.map(([id]) => {
                const item = menu.get(id);
                return (
                  <span key={id} className="inline-flex items-center gap-1.5 rounded-full border border-line bg-panel-2 py-1 pl-3 pr-1 text-[12.5px] text-ink">
                    {item?.name ?? id}
                    <button type="button" aria-label={`Remove ${item?.name ?? id}`} onClick={() => setDishes((d) => d.filter(([i]) => i !== id))} className="grid h-6 w-6 place-items-center rounded-full text-muted hover:bg-panel-3">
                      <X size={13} aria-hidden />
                    </button>
                  </span>
                );
              })}
            </div>
            <Button className="mt-3" icon={Plus} onClick={() => setChoosing(true)}>
              Choose dishes
            </Button>
          </div>
        </SectionCard>
      )}

      <SectionCard title="Picture" subtitle={isCombo ? "Shown on the combo card. Without one, the first dish's photo is used." : "Shown on the home banner. Without one, the first dish's photo is used."} index={2}>
        <PhotoField image={image} onChange={setImage} upload={uploadOfferPhoto} failMessage="The picture could not be uploaded. Please try again." />
      </SectionCard>

      <SectionCard title="When and how often" subtitle="Dates are restaurant days, both included. Leave them empty to run until you pause it." index={3}>
        <div className="flex flex-col gap-4">
          <DatesField startsOn={startsOn} endsOn={endsOn} onChange={(a, b) => (setStartsOn(a), setEndsOn(b))} />
          <UsageLimit value={limit} onChange={setLimit} used={original?.usedCount ?? 0} />
          <SwitchRow title="Active" description="Guests see it only while it is active and within its dates." checked={active} onChange={setActive} />
        </div>
      </SectionCard>

      <Button variant="primary" size="lg" icon={Check} loading={pending} onClick={() => void save()}>
        {original ? 'Save changes' : `Create ${what}`}
      </Button>

      <DishChooser open={choosing} items={items.filter((i) => !i.isArchived)} selected={dishes.map(([id]) => id)} onClose={() => setChoosing(false)} onDone={(ids) => {
        setDishes((current) => ids.map((id) => [id, current.find(([i]) => i === id)?.[1] ?? 1]));
        setChoosing(false);
      }} />
    </Page>
  );
}

function DishChooser({ open, items, selected, onClose, onDone }: { open: boolean; items: MenuItem[]; selected: string[]; onClose: () => void; onDone: (ids: string[]) => void }) {
  const [picked, setPicked] = useState<string[]>(selected);
  const [search, setSearch] = useState('');
  const [wasOpen, setWasOpen] = useState(false);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) {
      setPicked(selected);
      setSearch('');
    }
  }
  const q = search.trim().toLowerCase();
  const shown = [...items].sort((a, b) => a.name.localeCompare(b.name)).filter((d) => !q || d.name.toLowerCase().includes(q));
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Choose dishes"
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={() => onDone(picked)}>
            Done ({picked.length})
          </Button>
        </>
      }
    >
      <SearchField value={search} onChange={setSearch} placeholder="Search dishes" className="mb-3" />
      <ul className="flex flex-col gap-1 pb-3">
        {shown.map((dish) => {
          const on = picked.includes(dish.id);
          return (
            <li key={dish.id}>
              <button
                type="button"
                aria-pressed={on}
                onClick={() => setPicked((p) => (on ? p.filter((id) => id !== dish.id) : [...p, dish.id]))}
                className={cn('flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left', on ? 'bg-brand/10' : 'hover:bg-panel-2')}
              >
                <span className={cn('grid h-5 w-5 shrink-0 place-items-center rounded-md border', on ? 'border-transparent brand-fill' : 'border-line-strong')}>{on && <Check size={13} strokeWidth={3} className="text-white" aria-hidden />}</span>
                <FoodImage src={dish.image} size={36} />
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-1.5 truncate text-[13.5px] font-medium text-ink">
                    <VegMark veg={dish.isVeg} size={10} />
                    {dish.name}
                  </span>
                  <span className="block text-[12px] text-faint">
                    {dish.category.label} · {Currency.format(dish.price)}
                    {!dish.isAvailable ? ' · sold out' : ''}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </Dialog>
  );
}

