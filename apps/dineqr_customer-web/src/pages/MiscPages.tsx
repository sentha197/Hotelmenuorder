import { ChevronRight, CircleAlert, Compass, Heart, Images, Info, Moon, QrCode as QrIcon, ReceiptText, Smartphone, Sun, SunMoon, Wallet } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router';
import { tap } from '../animations/variants';
import { Lockup, Mark } from '../components/brand';
import { FoodImage } from '../components/food';
import { AppBar, BrandPanel, Button, Card, EmptyState, FadeIn } from '../components/ui';
import type { ConfigIssue } from '../config';
import { imageCredits } from '../core/imageCredits';
import { Currency, sum } from '../core/money';
import { OrderTables } from '../core/orders';
import { AppFormat } from '../core/time';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useSelect, useStore } from '../state/store';
import { iconSize, lockupHeight } from '../components/sizes';
import { useTheme, type ThemePreference } from '../theme';

/** "More": the table session, favourites, bills, credits and about. */
export function MorePage() {
  const { session, catalog, orders, billing, settings } = useApp();
  useStore(session);
  useStore(orders);
  useStore(billing);
  const navigate = useNavigate();
  const favorites = useSelect(catalog, (c) => c.favorites.size);
  const restaurant = useSelect(settings, (s) => s.settings.name);
  const bills = billing.forOrders(orders.guestOrders);
  const due = sum(bills.map((b) => b.outstanding));
  const table = session.tableNumber;

  const tiles: { icon: ReactNode; title: string; subtitle: string; onTap: () => void }[] = [
    {
      icon: <Heart size={iconSize.lg} />,
      title: 'My Favorites',
      subtitle: favorites === 0 ? 'Tap the heart on a dish to save it' : `${favorites} saved ${favorites === 1 ? 'dish' : 'dishes'}`,
      onTap: () => navigate(paths.favorites),
    },
    {
      icon: <ReceiptText size={iconSize.lg} />,
      title: 'My Orders',
      subtitle: `${orders.currentOrders.length} active · ${orders.pastOrders.length} past`,
      onTap: () => navigate(paths.orders),
    },
    {
      icon: <Wallet size={iconSize.lg} />,
      title: 'Bills & Payments',
      subtitle: bills.length === 0 ? 'Your bills and receipts appear here' : due === 0 ? `${bills.length} ${bills.length === 1 ? 'bill' : 'bills'} · nothing due` : `${Currency.format(due)} due across your bills`,
      onTap: () => navigate(paths.payments),
    },
    { icon: <Images size={iconSize.lg} />, title: 'Photo Credits', subtitle: 'Licenses for the food photography', onTap: () => navigate(paths.credits) },
    { icon: <Info size={iconSize.lg} />, title: 'About DineQR', subtitle: 'How DineQR works', onTap: () => navigate(paths.about) },
  ];

  return (
    <div>
      <AppBar title="More" onBack={() => navigate(paths.home)} />
      <div className="page page--narrow stack-md more-grid">
        <FadeIn>
          <BrandPanel className="session-card">
            <Mark size={60} onDark />
            <div className="grow col">
              <span className="t-section">
                {table == null ? 'No table selected' : OrderTables.isTakeaway(table) ? 'Takeaway order' : `Dining at Table ${AppFormat.table(table)}`}
              </span>
              <span className="t-caption ellipsis" style={{ color: 'rgb(255 255 255 / 80%)' }}>
                {restaurant}
              </span>
              <motion.button type="button" className="session-card__scan" whileTap={tap} onClick={() => navigate(paths.scan)}>
                <QrIcon size={iconSize.sm} />
                {table == null ? 'Scan table QR' : OrderTables.isTakeaway(table) ? 'Switch to a table' : 'Change table'}
              </motion.button>
            </div>
          </BrandPanel>
        </FadeIn>
        <FadeIn index={1}>
          <AppearanceCard />
        </FadeIn>
        {tiles.map((tile, index) => (
          <FadeIn key={tile.title} index={index + 2}>
            <motion.button type="button" className="more-tile" whileTap={{ scale: 0.98 }} onClick={tile.onTap}>
              <span className="more-tile__icon">{tile.icon}</span>
              <span className="grow col" style={{ textAlign: 'left' }}>
                <span className="t-card-title">{tile.title}</span>
                <span className="t-caption">{tile.subtitle}</span>
              </span>
              <ChevronRight size={iconSize.lg} color="var(--text-muted)" />
            </motion.button>
          </FadeIn>
        ))}
      </div>
    </div>
  );
}

const themeOptions: { value: ThemePreference; label: string; icon: ReactNode }[] = [
  { value: 'system', label: 'Device', icon: <Smartphone size={iconSize.sm} /> },
  { value: 'light', label: 'Light', icon: <Sun size={iconSize.sm} /> },
  { value: 'dark', label: 'Dark', icon: <Moon size={iconSize.sm} /> },
];

/** Light or dark: the device's appearance by default, or the guest's pick (this device only). */
function AppearanceCard() {
  const { theme, preference, setPreference } = useTheme();
  const reduced = useReducedMotion();
  return (
    <div className="card appearance" role="group" aria-labelledby="appearance-title">
      <span className="more-tile__icon" aria-hidden>
        <SunMoon size={iconSize.lg} />
      </span>
      <span className="grow col">
        <span className="t-card-title" id="appearance-title">
          Appearance
        </span>
        <span className="t-caption">{preference === 'system' ? `Matches your device (${theme} now)` : `Always ${theme} on this device`}</span>
      </span>
      <div className="theme-switch" role="radiogroup" aria-label="Theme">
        {themeOptions.map((option) => {
          const selected = option.value === preference;
          return (
            <motion.button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={selected}
              className={`theme-switch__option ${selected ? 'is-selected' : ''}`}
              whileTap={{ scale: 0.94 }}
              onClick={() => setPreference(option.value)}
            >
              {selected && (
                <motion.span
                  layoutId="theme-switch-pill"
                  className="theme-switch__pill"
                  transition={reduced ? { duration: 0 } : { type: 'spring', stiffness: 500, damping: 38 }}
                />
              )}
              {option.icon}
              <span>{option.label}</span>
            </motion.button>
          );
        })}
      </div>
    </div>
  );
}

export function CreditsPage() {
  return (
    <div>
      <AppBar title="Photo Credits" />
      <div className="page page--narrow stack-md credits-grid">
        <p className="t-secondary">The food photos come from Wikimedia Commons. Each keeps its original license; see its source page for details.</p>
        {imageCredits.map((credit, index) => (
          <FadeIn key={credit.asset} index={index}>
            <Card className="row-top" style={{ gap: 12 }}>
              <FoodImage src={credit.asset} width={48} height={48} radius={10} />
              <div className="grow col">
                <span className="t-label t-strong" style={{ overflowWrap: 'anywhere' }}>
                  {credit.title}
                </span>
                <span className="t-caption">
                  {credit.author} · {credit.license}
                </span>
                <a className="t-caption" href={credit.source} target="_blank" rel="noopener noreferrer" style={{ overflowWrap: 'anywhere' }}>
                  {credit.source}
                </a>
              </div>
            </Card>
          </FadeIn>
        ))}
      </div>
    </div>
  );
}

export function NotFoundPage() {
  const navigate = useNavigate();
  const { session } = useApp();
  return (
    <div>
      <AppBar title="" />
      <EmptyState
        icon={<Compass size={iconSize.hero} />}
        title="This page doesn’t exist"
        message="The link may be incomplete. Scan the QR code on your table to start."
        action={<Button onClick={() => navigate(session.canOrder ? paths.home : paths.root, { replace: true })}>{session.canOrder ? 'Back to the menu' : 'Scan a QR code'}</Button>}
      />
    </div>
  );
}

/** A build without a usable API address: says what to fix instead of inventing data. */
export function NotConfiguredPage({ issue }: { issue: ConfigIssue }) {
  return (
    <div className="entry entry--center">
      <Lockup height={lockupHeight.lg} />
      <div className="empty__icon">
        <CircleAlert size={iconSize.hero} />
      </div>
      <h1 className="t-screen-title">{issue.title}</h1>
      <p className="t-secondary t-center" style={{ maxWidth: 360 }}>
        {issue.detail}
      </p>
    </div>
  );
}
