import { BadgePercent, History, LogIn, Package, ReceiptText, RefreshCw, Scale, Settings, Armchair, IdCard, UtensilsCrossed, Wallet, type LucideIcon } from 'lucide-react';
import { motion } from 'motion/react';
import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { Empty, PageSkeleton } from '@/components/ui/Feedback';
import { FilterChips, SearchField } from '@/components/ui/Form';
import { Page } from '@/components/ui/Page';
import type { AuditEvent } from '@/core/access';
import { AppFormat } from '@/core/time';
import { keys, queryClient, useAudit } from '@/state/data';
import { runAction } from '@/state/run';

type Area = 'all' | 'orders' | 'payments' | 'menu' | 'stock' | 'tables' | 'staff' | 'settings' | 'access';
const areas: Record<Area, { label: string; prefixes: string[] }> = {
  all: { label: 'All', prefixes: [] },
  orders: { label: 'Orders', prefixes: ['order.'] },
  payments: { label: 'Payments', prefixes: ['payment.'] },
  menu: { label: 'Menu', prefixes: ['menu.', 'category.'] },
  stock: { label: 'Stock', prefixes: ['inventory.'] },
  tables: { label: 'Tables', prefixes: ['table.'] },
  staff: { label: 'Staff', prefixes: ['staff.'] },
  settings: { label: 'Settings', prefixes: ['settings.', 'offer.', 'legal.'] },
  access: { label: 'Sign-ins', prefixes: ['auth.'] },
};
const matches = (a: Area, e: AuditEvent) => areas[a].prefixes.length === 0 || areas[a].prefixes.some((p) => e.action.startsWith(p));

const icons: Record<string, LucideIcon> = {
  order: ReceiptText,
  payment: Wallet,
  menu: UtensilsCrossed,
  category: UtensilsCrossed,
  inventory: Package,
  table: Armchair,
  staff: IdCard,
  settings: Settings,
  offer: BadgePercent,
  promotion: BadgePercent,
  legal: Scale,
  auth: LogIn,
};

const PAGE = 200;

/** Who did what, and when (ActivityScreen). Written by the server for every privileged request. */
export function ActivityPage() {
  const query = useAudit();
  const events = useMemo(() => [...(query.data ?? [])].sort((a, b) => b.at.getTime() - a.at.getTime()), [query.data]);
  const [search, setSearch] = useState('');
  const [area, setArea] = useState<Area>('all');
  const [limit, setLimit] = useState(PAGE);
  const q = search.trim().toLowerCase();
  const shown = events.filter((e) => matches(area, e) && (!q || e.summary.toLowerCase().includes(q) || e.actorName.toLowerCase().includes(q) || e.targetId.toLowerCase().includes(q)));
  const refresh = () => runAction(() => queryClient.refetchQueries({ queryKey: keys.audit }));
  return (
    <Page
      title="Activity log"
      subtitle={events.length === 0 ? 'Nothing recorded yet' : `${events.length} recorded ${events.length === 1 ? 'action' : 'actions'}${events.length >= 500 ? ' (latest kept)' : ''}`}
      actions={
        <Button icon={RefreshCw} loading={query.isFetching} onClick={() => void refresh()}>
          Refresh
        </Button>
      }
    >
      <SearchField value={search} onChange={setSearch} placeholder="Search by person, order, bill or text" />
      <FilterChips name="activity-area" values={Object.keys(areas) as Area[]} selected={area} labelOf={(a) => areas[a].label} countOf={(a) => events.filter((e) => matches(a, e)).length} onSelect={setArea} />
      {query.isPending ? (
        <PageSkeleton rows={5} />
      ) : shown.length === 0 ? (
        <Empty icon={History} title="Nothing recorded" message="Sensitive changes such as refunds, price edits and role changes appear here." />
      ) : (
        <SectionCard>
          <ol className="relative flex flex-col before:absolute before:bottom-4 before:left-[19px] before:top-4 before:w-px before:bg-line">
            {shown.slice(0, limit).map((event, i) => {
              const Icon = icons[event.action.split('.')[0] ?? ''] ?? History;
              return (
                <motion.li key={event.id} initial={{ opacity: 0, x: -6 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: Math.min(i, 20) * 0.015 }} className="relative flex gap-3.5 py-2.5">
                  <span className="relative grid h-10 w-10 shrink-0 place-items-center rounded-full border border-line bg-panel-solid text-brand-text">
                    <Icon size={17} aria-hidden />
                  </span>
                  <div className="min-w-0 pt-0.5">
                    <p className="text-[13.5px] leading-snug text-ink">{event.summary}</p>
                    <p className="mt-0.5 text-[12px] text-faint">
                      {event.actorName} ({event.actorRole}) · {AppFormat.dateTime(event.at)}
                    </p>
                  </div>
                </motion.li>
              );
            })}
          </ol>
          {shown.length > limit && (
            <div className="mt-3 flex justify-center">
              <Button size="sm" onClick={() => setLimit((l) => l + PAGE)}>
                Show more
              </Button>
            </div>
          )}
        </SectionCard>
      )}
    </Page>
  );
}
