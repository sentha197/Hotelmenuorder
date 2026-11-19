import { BadgePercent, Check } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { useNavigate } from 'react-router';
import { Button } from '@/components/ui/Button';
import { InfoRow, SectionCard } from '@/components/ui/Card';
import { Select, SwitchRow, TextField } from '@/components/ui/Form';
import { PageSkeleton } from '@/components/ui/Feedback';
import { Page } from '@/components/ui/Page';
import { ValidationError } from '@/core/access';
import { currencyLabel, formatRate, parsePercent, supportedCurrencies } from '@/core/money';
import type { RestaurantSettings } from '@/core/settings';
import { formatOffset, utcOffsets } from '@/core/time';
import { updateSettings } from '@/state/actions';
import { useSettings } from '@/state/data';
import { useAction } from '@/state/run';
import { GpsRestrictionCard, WifiRestrictionCard } from './RestrictionCards';

interface SettingsForm {
  name: string;
  phone: string;
  email: string;
  address: string;
  taxReg: string;
  taxName: string;
  taxRate: string;
  service: string;
  footer: string;
  buffer: string;
}

const formOf = (s: RestaurantSettings): SettingsForm => ({
  name: s.name,
  phone: s.phone,
  email: s.email,
  address: s.address,
  taxReg: s.taxRegistration,
  taxName: s.taxName,
  taxRate: formatRate(s.taxRateBasisPoints).replace('%', ''),
  service: formatRate(s.serviceChargeBasisPoints).replace('%', ''),
  footer: s.receiptFooter,
  buffer: String(s.prepBufferMinutes),
});

/** Restaurant details, taxes, payments, restrictions, time zone and menu rules (AdminSettingsScreen). */
export function SettingsPage() {
  const query = useSettings();
  if (query.isPending) return <Page title="Settings" width="medium"><PageSkeleton /></Page>;
  return <SettingsEditor settings={query.settings} />;
}

function SettingsEditor({ settings }: { settings: RestaurantSettings }) {
  const navigate = useNavigate();
  const [draft, setDraft] = useState(settings);
  const { register, handleSubmit, reset, watch } = useForm<SettingsForm>({ defaultValues: formOf(settings) });
  const { pending, run } = useAction();
  const v = watch();

  // Saved elsewhere (another device, live update): show what is in force.
  useEffect(() => {
    setDraft(settings);
    reset(formOf(settings));
  }, [settings, reset]);

  const save = handleSubmit(async (f) => {
    await run(async () => {
      const tax = parsePercent(f.taxRate);
      const service = parsePercent(f.service.trim() ? f.service : '0');
      const buffer = /^\d+$/.test(f.buffer.trim()) ? Number(f.buffer.trim()) : null;
      if (tax == null || service == null || buffer == null) throw new ValidationError('Check the tax rate, service charge and preparation buffer.');
      await updateSettings({
        ...draft,
        name: f.name,
        phone: f.phone,
        email: f.email,
        address: f.address,
        taxRegistration: f.taxReg,
        taxName: f.taxName,
        taxRateBasisPoints: tax,
        serviceChargeBasisPoints: service,
        receiptFooter: f.footer,
        prepBufferMinutes: buffer,
      });
    }, { success: 'Settings saved' });
  });

  return (
    <Page title="Settings" subtitle="Changes apply to new orders and bills" width="medium">
      <form onSubmit={save} className="flex flex-col gap-5" noValidate>
        <SectionCard title="Restaurant" subtitle="Contact details and the tax registration are printed on bills only when filled in." index={0}>
          <div className="grid gap-4 sm:grid-cols-2">
            <TextField label="Restaurant name" maxLength={60} showCount value={v.name} wrapperClassName="sm:col-span-2" {...register('name')} />
            <TextField label="Phone (optional)" type="tel" maxLength={20} {...register('phone')} />
            <TextField label="Email (optional)" type="email" {...register('email')} />
            <TextField label="Address (optional)" maxLength={160} showCount value={v.address} wrapperClassName="sm:col-span-2" {...register('address')} />
            <TextField label="Tax registration number (optional)" maxLength={20} placeholder="e.g. a GSTIN" {...register('taxReg')} />
          </div>
        </SectionCard>

        <SectionCard title="Taxes & charges" index={1}>
          <div className="grid gap-4 sm:grid-cols-3">
            <TextField label="Tax name" maxLength={20} placeholder="e.g. GST" {...register('taxName')} />
            <TextField label="Tax rate" inputMode="decimal" suffix="%" {...register('taxRate')} />
            <TextField label="Service charge (0 for none)" inputMode="decimal" suffix="%" {...register('service')} />
            <div className="sm:col-span-3">
              <Select label="Currency" value={draft.currencyCode} onChange={(e) => setDraft((d) => ({ ...d, currencyCode: e.target.value }))} hint="Fixed once the first bill exists, so earlier bills keep their currency.">
                {supportedCurrencies.map((c) => (
                  <option key={c.code} value={c.code}>
                    {currencyLabel(c)}
                  </option>
                ))}
              </Select>
            </div>
          </div>
        </SectionCard>
      </form>

      {/* Saved on their own: they decide who can order. */}
      <WifiRestrictionCard />
      <GpsRestrictionCard />

      <form onSubmit={save} className="flex flex-col gap-5" noValidate>
        <SectionCard title="Billing counter" subtitle="Guests order in DineQR and pay at the billing counter. Staff record each payment (cash, card or UPI) on the bill in Bills." index={2}>
          <InfoRow label="Receipt printer" value="No thermal printer connected" />
        </SectionCard>

        <SectionCard title="Time zone & receipts" index={3}>
          <div className="flex flex-col gap-4">
            <Select label="Restaurant time zone" value={utcOffsets.includes(draft.utcOffsetMinutes) ? draft.utcOffsetMinutes : ''} onChange={(e) => setDraft((d) => ({ ...d, utcOffsetMinutes: Number(e.target.value) }))} hint='Used for bills, reports and "today".'>
              {!utcOffsets.includes(draft.utcOffsetMinutes) && <option value="">{formatOffset(draft.utcOffsetMinutes)}</option>}
              {utcOffsets.map((m) => (
                <option key={m} value={m}>
                  {formatOffset(m)}
                  {m === 330 ? ' · India' : ''}
                </option>
              ))}
            </Select>
            <TextField label="Note on receipts" maxLength={120} showCount value={v.footer} {...register('footer')} />
          </div>
        </SectionCard>

        <SectionCard title="Menu & stock" index={4}>
          <div className="divide-y divide-line">
            <SwitchRow title="Show sold-out dishes" description="Off hides them from guests instead of greying them out." checked={draft.showSoldOutDishes} onChange={(on) => setDraft((d) => ({ ...d, showSoldOutDishes: on }))} />
            <SwitchRow title="Sold out when stock runs out" description="Dishes linked to an inventory item follow its stock." checked={draft.autoUnavailableWhenOutOfStock} onChange={(on) => setDraft((d) => ({ ...d, autoUnavailableWhenOutOfStock: on }))} />
          </div>
          <div className="mt-3 max-w-xs">
            <TextField label="Preparation buffer" inputMode="numeric" suffix="min" hint="Added to the longest dish time for estimates." {...register('buffer')} />
          </div>
        </SectionCard>

        <div className="sticky bottom-[calc(76px+env(safe-area-inset-bottom))] z-10 md:bottom-4">
          <div className="panel-solid flex flex-wrap items-center gap-3 rounded-2xl p-3">
            <p className="min-w-0 flex-1 px-1 text-[12.5px] text-muted">Restaurant, taxes, payments, time zone and menu rules are saved together.</p>
            <Button type="submit" variant="primary" icon={Check} loading={pending}>
              Save settings
            </Button>
          </div>
        </div>
      </form>

      <SectionCard title="Offers" subtitle="Coupons, special offers and combos have their own section.">
        <Button icon={BadgePercent} onClick={() => navigate('/offers')}>
          Open Offers
        </Button>
      </SectionCard>
    </Page>
  );
}
