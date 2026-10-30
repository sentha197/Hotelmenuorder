import { ArrowDownRight, ArrowRight, BadgeCheck, Banknote, Check, ChefHat, ConciergeBell, Flame, Printer, QrCode as QrIcon, ReceiptText, ScanLine, ShieldCheck, ShoppingBag, Smartphone, Split, Store, Tag, UtensilsCrossed } from 'lucide-react';
import { useRef, type CSSProperties, type ReactNode } from 'react';
import { Link } from 'react-router';
import { Lockup } from '../components/brand';
import { DineQrMark } from '../components/DineQrMark';
import { QrCode } from '../components/QrCode';
import { imageUrl } from '../config';
import { Currency } from '../core/money';
import { BillBreakdown } from '../core/pricing';
import { tiltHandlers, useCinematics } from '../hooks/useCinematics';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import '../styles/landing.css';

/** Dishes and prices from the restaurant's seed catalogue (initial-catalog.json). */
const dish = {
  butterChicken: { name: 'Butter Chicken', price: 28000, image: 'assets/images/butter_chicken.jpg', veg: false },
  biryani: { name: 'Chicken Biryani', price: 26000, image: 'assets/images/chicken_biryani.jpg', veg: false },
  dosa: { name: 'Masala Dosa', price: 10000, image: 'assets/images/masala_dosa.jpg', veg: true },
  naan: { name: 'Butter Naan', price: 4500, image: 'assets/images/butter_naan.jpg', veg: true },
  coffee: { name: 'Cold Coffee', price: 12000, image: 'assets/images/cold_coffee.jpg', veg: true },
  jamun: { name: 'Gulab Jamun', price: 9000, image: 'assets/images/gulab_jamun.jpg', veg: true },
  paneer: { name: 'Paneer Tikka', image: 'assets/images/paneer_tikka.jpg' },
  tandoori: { name: 'Tandoori Chicken', image: 'assets/images/tandoori_chicken.jpg' },
  samosa: { name: 'Punjabi Samosa', image: 'assets/images/samosa.jpg' },
  lassi: { name: 'Lassi', image: 'assets/images/lassi.jpg' },
};

const cart = [
  { ...dish.butterChicken, qty: 1, note: 'Spice: Mild' },
  { ...dish.naan, qty: 2, note: '' },
  { ...dish.coffee, qty: 1, note: '' },
];
// The same bill formula the app and server use (5% tax, no service charge).
const cartBill = BillBreakdown.fromSubtotal(
  cart.reduce((sum, line) => sum + line.price * line.qty, 0),
  { taxRateBasisPoints: 500, taxName: 'Taxes', serviceChargeBasisPoints: 0 },
);

const Img = ({ src, alt = '', className }: { src: string; alt?: string; className?: string }) => (
  <img className={className} src={imageUrl(src)} alt={alt} loading="lazy" decoding="async" draggable={false} />
);

const Veg = ({ veg }: { veg: boolean }) => <span className={`lx-veg ${veg ? 'is-veg' : ''}`} aria-hidden />;

/** Text split into words, each in its own span (word-by-word reveals). */
function Words({ text, accent = [] }: { text: string; accent?: string[] }) {
  return (
    <>
      {text.split(' ').map((word, i) => (
        <span key={i} className={`word ${accent.includes(word.replace(/[^\w]/g, '').toLowerCase()) ? 'word--accent' : ''}`}>
          {word}{' '}
        </span>
      ))}
    </>
  );
}

/**
 * `/about`: DineQR's story, told as one long cinematic page. The guest app
 * itself starts at the scanner (`/`); every call to action here leads there.
 */
export function AboutPage() {
  const root = useRef<HTMLDivElement>(null);
  useCinematics(root);
  const { session } = useApp();
  const tilt = tiltHandlers();
  const origin = typeof window === 'undefined' ? '' : window.location.origin;

  return (
    <div className="landing" ref={root}>
      <a className="lx-skip" href="#lx-main">
        Skip to content
      </a>
      <header className="lx-nav">
        <div className="lx-nav__inner">
          <Link to={paths.about} className="lx-nav__brand" aria-label="DineQR">
            <Lockup height={30} onDark />
          </Link>
          <nav className="lx-nav__links" aria-label="Sections">
            <a href="#experience">Experience</a>
            <a href="#features">Features</a>
            <a href="#promise">Promise</a>
          </nav>
          <Link to={paths.scan} className="lx-cta lx-cta--small">
            <ScanLine size={16} /> Scan to order
          </Link>
        </div>
      </header>

      <main id="lx-main">
        {/* ------------------------------------------------------------ hero */}
        <section className="lx-hero" aria-labelledby="lx-title">
          <div className="lx-hero__glow" aria-hidden />
          <div className="lx-grid-bg" aria-hidden />
          <div className="lx-hero__inner">
            <div className="lx-hero__copy">
              <div className="lx-hero__mark" aria-hidden>
                <DineQrMark size={72} draw />
              </div>
              <p className="lx-eyebrow lx-hero__eyebrow">
                <span className="lx-dot" /> QR table ordering
              </p>
              <h1 id="lx-title" className="lx-hero__title" aria-label="Scan. Order. Enjoy.">
                <span className="lx-line">
                  <span style={{ '--d': '0.9s' } as CSSProperties}>Scan.</span>
                </span>
                <span className="lx-line">
                  <span className="lx-gradient-text" style={{ '--d': '1.05s' } as CSSProperties}>
                    Order.
                  </span>
                </span>
                <span className="lx-line">
                  <span style={{ '--d': '1.2s' } as CSSProperties}>Enjoy.</span>
                </span>
              </h1>
              <p className="lx-hero__lede">
                Point any phone camera at the code on your table. The menu opens in the browser, your order goes straight to the kitchen, and you pay when you’re
                ready. There’s no app to install.
              </p>
              <div className="lx-hero__actions">
                <Link to={paths.scan} className="lx-cta">
                  <ScanLine size={20} /> Scan your table <ArrowRight size={18} className="lx-cta__arrow" />
                </Link>
                <a href="#story" className="lx-ghost">
                  See how it works <ArrowDownRight size={18} />
                </a>
              </div>
              <ul className="lx-hero__facts">
                <li>Opens from Google Lens</li>
                <li>Dine-in &amp; takeaway</li>
                <li>UPI, cash or the counter</li>
              </ul>
            </div>

            <div className="lx-stage" aria-hidden data-live>
              <div className="lx-stage__table" data-parallax="-0.06">
                <Img src="assets/images/splash_bg.jpg" />
              </div>
              <div className="lx-tent" data-parallax="-0.03">
                <span className="lx-tent__brand">
                  <DineQrMark size={34} />
                </span>
                <div className="lx-tent__qr">
                  <QrCode payload={`${origin}${paths.about}`} size={118} label="" branded />
                  <span className="lx-beam" />
                </div>
                <span className="lx-tent__label">Table 05 · Scan to order</span>
              </div>
              <div className="lx-phone lx-stage__phone" data-parallax="0.05">
                <div className="lx-phone__screen lx-scan-ui">
                  <span className="lx-scan-ui__title">Scan QR Code</span>
                  <div className="lx-scan-ui__frame">
                    <i />
                    <i />
                    <i />
                    <i />
                    <span className="lx-beam lx-beam--phone" />
                    <span className="lx-scan-ui__qr">
                      <QrIcon size={54} strokeWidth={1.4} />
                    </span>
                  </div>
                  <span className="lx-scan-ui__found">
                    <Check size={14} /> Table 05 detected
                  </span>
                </div>
              </div>
              <div className="lx-float lx-float--dish" data-parallax="0.1">
                <Img src={dish.butterChicken.image} />
                <div>
                  <strong>{dish.butterChicken.name}</strong>
                  <span>{Currency.format(dish.butterChicken.price)} · Chef’s pick</span>
                </div>
              </div>
              <div className="lx-float lx-float--status" data-parallax="0.14">
                <span className="lx-pulse" /> Sent to the kitchen
              </div>
              <div className="lx-float lx-float--paid" data-parallax="0.08">
                <BadgeCheck size={18} /> Bill paid · verified
              </div>
            </div>
          </div>
          <a href="#story" className="lx-scroll" aria-label="Scroll to the story">
            <span>Scroll</span>
            <i />
          </a>
        </section>

        {/* ------------------------------------------------------- manifesto */}
        <section id="story" className="lx-manifesto" aria-label="The idea">
          <p className="lx-eyebrow" data-reveal>
            01 — The idea
          </p>
          <p className="lx-manifesto__text" data-words>
            <Words
              text="A table. A phone. A code. Nothing to download, nobody to wave down. You scan, the menu opens, the kitchen sees your order the moment you send it, and your bill is settled only when the payment is verified."
              accent={['scan', 'kitchen', 'verified']}
            />
          </p>
        </section>

        {/* ------------------------------------------------------ experience */}
        <section id="experience" className="lx-experience" aria-labelledby="lx-exp-title">
          <header className="lx-section-head" data-reveal>
            <p className="lx-eyebrow">02 — The experience</p>
            <h2 id="lx-exp-title" className="lx-h2">
              From scan <br />
              <span className="lx-gradient-text">to settled.</span>
            </h2>
          </header>

          <Chapter
            index="01"
            title="Scan"
            text="The code on your table opens DineQR in the browser. Google Lens, the camera app or the scanner on this site all lead to your table, and the restaurant checks it before you order."
            visual={<ScanVisual origin={origin} />}
          />
          <Chapter
            index="02"
            title="Discover"
            text="Browse by category, filter veg or non-veg, choose the spice level, portion and add-ons. Sold-out dishes say so before you order them."
            visual={<MenuVisual />}
            flip
          />
          <Chapter
            index="03"
            title="Order"
            text="The cart totals every add-on, offer and tax as you go. The restaurant’s server prices the order again, so the total you approve is the total the kitchen receives."
            visual={<CartVisual />}
          />
          <Chapter
            index="04"
            title="Pay"
            text="Pay by UPI, in cash or at the counter, or split the bill across several. The bill turns paid only when the payment is confirmed, never on a tap."
            visual={<PayVisual />}
            flip
          />
          <Chapter
            index="05"
            title="Run the floor"
            text="In the DineQR Admin app, staff watch orders arrive, move them from kitchen to table, and confirm payments at the counter."
            visual={<DashboardVisual />}
          />
        </section>

        {/* -------------------------------------------------------- features */}
        <section id="features" className="lx-features" aria-labelledby="lx-feat-title">
          <header className="lx-section-head" data-reveal>
            <p className="lx-eyebrow">03 — Features</p>
            <h2 id="lx-feat-title" className="lx-h2">
              Everything <br />
              the table needs.
            </h2>
          </header>
          <div className="lx-bento">
            <Tile className="lx-tile--hero" tilt={tilt} d={0}>
              <Img src="assets/images/splash_bg.jpg" className="lx-tile__img" />
              <div className="lx-tile__qr" aria-hidden>
                <QrCode payload={`${origin}${paths.about}`} size={96} label="" branded />
                <span className="lx-beam" />
              </div>
              <TileText icon={<Smartphone size={20} />} title="Any camera opens the menu" text="Codes open straight in the browser. No app, no sign-up." />
            </Tile>
            <Tile className="lx-tile--wide" tilt={tilt} d={0.08}>
              <ol className="lx-track" aria-hidden data-live>
                {['Placed', 'Preparing', 'Ready', 'Served'].map((step, i) => (
                  <li key={step} style={{ '--i': i } as CSSProperties}>
                    <span />
                    {step}
                  </li>
                ))}
              </ol>
              <TileText icon={<ChefHat size={20} />} title="Live order tracking" text="Every step the kitchen takes shows up on your phone as it happens." />
            </Tile>
            <Tile tilt={tilt} d={0.16}>
              <div className="lx-split" aria-hidden>
                <span style={{ '--s': '55%' } as CSSProperties}>UPI</span>
                <span style={{ '--s': '45%' } as CSSProperties}>Cash</span>
              </div>
              <TileText icon={<Split size={20} />} title="Split the bill" text="Part online, part at the counter, across up to four parts." />
            </Tile>
            <Tile className="lx-tile--tall" tilt={tilt} d={0.04}>
              <Img src={dish.paneer.image} className="lx-tile__img lx-tile__img--zoom" />
              <TileText icon={<Flame size={20} />} title="Spice, portions, add-ons" text="Every dish the way you like it, priced as you choose." />
            </Tile>
            <Tile tilt={tilt} d={0.12}>
              <div className="lx-modes" aria-hidden>
                <span>
                  <UtensilsCrossed size={16} /> Dine-in
                </span>
                <span>
                  <ShoppingBag size={16} /> Takeaway
                </span>
              </div>
              <TileText icon={<Store size={20} />} title="Dine-in or takeaway" text="The counter’s takeaway code orders without a table." />
            </Tile>
            <Tile tilt={tilt} d={0.2}>
              <div className="lx-coupon" aria-hidden>
                <Tag size={18} />
                <span>Offer applied</span>
              </div>
              <TileText icon={<Tag size={20} />} title="Offers at checkout" text="Coupons apply once the cart reaches their minimum." />
            </Tile>
            <Tile className="lx-tile--wide lx-tile--receipts" tilt={tilt} d={0.1}>
              <div className="lx-receipt" aria-hidden>
                <DineQrMark size={30} />
                <span className="lx-receipt__line" />
                <span className="lx-receipt__line lx-receipt__line--short" />
                <span className="lx-receipt__total">
                  Total <b>{Currency.format(cartBill.total)}</b>
                </span>
              </div>
              <TileText icon={<Printer size={20} />} title="Receipts to print or share" text="Every bill lists its payments, refunds and the restaurant’s details." />
            </Tile>
          </div>
        </section>

        {/* --------------------------------------------------------- promise */}
        <section id="promise" className="lx-promise" aria-labelledby="lx-promise-title">
          <div className="lx-promise__frame">
            <div className="lx-orbit" aria-hidden data-live>
              <div className="lx-orbit__ring" />
              <div className="lx-orbit__ring lx-orbit__ring--inner" />
              <div className="lx-orbit__center">
                <DineQrMark size={120} />
              </div>
              <div className="lx-orbit__spin">
                {[dish.biryani, dish.tandoori, dish.dosa, dish.lassi, dish.samosa, dish.jamun].map((d, i) => (
                  <span key={d.image} className="lx-orbit__item" style={{ '--a': `${i * 60}deg` } as CSSProperties}>
                    <Img src={d.image} />
                  </span>
                ))}
              </div>
            </div>
            <div className="lx-promise__copy">
              <p className="lx-eyebrow" data-reveal>
                04 — Our promise
              </p>
              <h2 id="lx-promise-title" className="lx-h2" data-reveal>
                Honest <span className="lx-gradient-text">by design.</span>
              </h2>
              <ul className="lx-promises">
                {[
                  ['Priced by the restaurant', 'Your order is priced again on the restaurant’s server. If a price changed, you’re told before anything reaches the kitchen.'],
                  ['Paid means verified', 'A bill shows as paid only when the payment provider or the cashier confirms the money arrived.'],
                  ['A code is just a table', 'Scanning tells the restaurant where you’re sitting. It never signs you in or opens anything else.'],
                  ['Demo stays demo', 'Demo payments are labelled as demo wherever they appear. No money moves.'],
                ].map(([title, text], i) => (
                  <li key={title} data-reveal style={{ '--d': `${i * 0.08}s` } as CSSProperties}>
                    <span className="lx-promises__n">{String(i + 1).padStart(2, '0')}</span>
                    <div>
                      <h3>{title}</h3>
                      <p>{text}</p>
                    </div>
                  </li>
                ))}
              </ul>
              <p className="lx-credit">
                Food photography from Wikimedia Commons. <Link to={paths.credits}>Photo credits</Link>
              </p>
            </div>
          </div>
        </section>

        {/* ------------------------------------------------------------ cta */}
        <section className="lx-final" aria-labelledby="lx-final-title" data-live>
          <div className="lx-final__light" aria-hidden />
          <div className="lx-grid-bg lx-grid-bg--light" aria-hidden />
          <div className="lx-final__inner">
            <div data-reveal>
              <DineQrMark size={84} tone="inverted" />
            </div>
            <h2 id="lx-final-title" className="lx-final__title" data-reveal>
              Your table <br />
              is waiting.
            </h2>
            <p className="lx-final__lede" data-reveal>
              Scan the code in front of you, or open the scanner here.
            </p>
            <div className="lx-hero__actions lx-final__actions" data-reveal>
              <Link to={paths.scan} className="lx-cta lx-cta--light">
                <ScanLine size={20} /> Scan to order <ArrowRight size={18} className="lx-cta__arrow" />
              </Link>
              {session.canOrder && (
                <Link to={paths.home} className="lx-ghost lx-ghost--light">
                  Back to the menu <ArrowRight size={18} />
                </Link>
              )}
            </div>
          </div>
        </section>
      </main>

      <footer className="lx-footer">
        <Lockup height={28} onDark />
        <span className="lx-footer__tag">SCAN • ORDER • ENJOY</span>
        <nav aria-label="Footer">
          <Link to={paths.scan}>Scanner</Link>
          <Link to={paths.credits}>Photo credits</Link>
        </nav>
      </footer>
    </div>
  );
}

function Chapter({ index, title, text, visual, flip = false }: { index: string; title: string; text: string; visual: ReactNode; flip?: boolean }) {
  return (
    <article className={`lx-chapter ${flip ? 'lx-chapter--flip' : ''}`}>
      <div className="lx-chapter__copy" data-reveal>
        <span className="lx-chapter__index">{index}</span>
        <h3 className="lx-chapter__title">{title}</h3>
        <p className="lx-chapter__text">{text}</p>
      </div>
      <div className="lx-chapter__visual" data-reveal="image" aria-hidden>
        {visual}
      </div>
    </article>
  );
}

function Tile({ children, className = '', tilt, d }: { children: ReactNode; className?: string; tilt: ReturnType<typeof tiltHandlers>; d: number }) {
  return (
    <article className={`lx-tile ${className}`} data-reveal style={{ '--d': `${d}s` } as CSSProperties} {...tilt}>
      {children}
    </article>
  );
}

function TileText({ icon, title, text }: { icon: ReactNode; title: string; text: string }) {
  return (
    <div className="lx-tile__text">
      <span className="lx-tile__icon">{icon}</span>
      <h3>{title}</h3>
      <p>{text}</p>
    </div>
  );
}

// ------------------------------------------------------------- visuals

function ScanVisual({ origin }: { origin: string }) {
  return (
    <div className="lx-v lx-v--scan" data-live>
      <div className="lx-v-scan__tent">
        <QrCode payload={`${origin}${paths.about}`} size={150} label="" branded />
        <span className="lx-beam" />
        <span className="lx-v-scan__label">Table 05</span>
      </div>
      <div className="lx-phone lx-v-scan__phone" data-parallax="0.06">
        <div className="lx-phone__screen lx-welcome-ui">
          <span className="lx-welcome-ui__ring">
            <span>05</span>
          </span>
          <span className="lx-welcome-ui__to">Welcome to</span>
          <strong>
            Dine<span className="lx-gradient-text">QR</span>
          </strong>
          <span className="lx-welcome-ui__chip">
            <UtensilsCrossed size={12} /> Table 05
          </span>
          <span className="lx-welcome-ui__button">Start Ordering</span>
        </div>
      </div>
      <span className="lx-v__chip lx-v-scan__chip" data-parallax="0.12">
        <ShieldCheck size={16} /> Table checked by the restaurant
      </span>
    </div>
  );
}

function MenuVisual() {
  return (
    <div className="lx-v lx-v--menu">
      <div className="lx-phone lx-v-menu__back">
        <div className="lx-phone__screen lx-dish-ui">
          <Img src={dish.biryani.image} className="lx-dish-ui__photo" />
          <div className="lx-dish-ui__body">
            <strong>{dish.biryani.name}</strong>
            <span className="lx-dish-ui__price">{Currency.format(dish.biryani.price)}</span>
            <span className="lx-dish-ui__label">Spice level</span>
            <span className="lx-dish-ui__choices">
              <i>Mild</i>
              <i className="is-on">Medium</i>
              <i>Spicy</i>
            </span>
            <span className="lx-dish-ui__add">Add to Cart · {Currency.format(dish.biryani.price)}</span>
          </div>
        </div>
      </div>
      <div className="lx-phone lx-v-menu__front" data-parallax="0.05">
        <div className="lx-phone__screen lx-menu-ui">
          <span className="lx-menu-ui__title">Our Menu</span>
          <span className="lx-menu-ui__tabs">
            <i className="is-on">All</i>
            <i>Starters</i>
            <i>Main</i>
          </span>
          {[dish.butterChicken, dish.dosa, dish.coffee, dish.jamun].map((d) => (
            <span key={d.name} className="lx-menu-ui__row">
              <Img src={d.image} />
              <span className="lx-menu-ui__text">
                <span>
                  <Veg veg={d.veg} /> {d.name}
                </span>
                <b>{Currency.format(d.price)}</b>
              </span>
              <span className="lx-menu-ui__plus">+</span>
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

function CartVisual() {
  return (
    <div className="lx-v lx-v--cart">
      <div className="lx-panel lx-v-cart__panel">
        <span className="lx-panel__title">My Cart</span>
        {cart.map((line) => (
          <span key={line.name} className="lx-cart-row">
            <Img src={line.image} />
            <span className="lx-cart-row__text">
              <span>{line.name}</span>
              <small>{line.note || `${Currency.format(line.price)} each`}</small>
            </span>
            <span className="lx-cart-row__qty">× {line.qty}</span>
            <b>{Currency.format(line.price * line.qty)}</b>
          </span>
        ))}
      </div>
      <div className="lx-panel lx-panel--glass lx-v-cart__bill" data-parallax="0.08">
        <span className="lx-bill-row">
          <span>Subtotal</span>
          <span>{Currency.format(cartBill.subtotal)}</span>
        </span>
        <span className="lx-bill-row">
          <span>{cartBill.taxLabel}</span>
          <span>{Currency.format(cartBill.tax)}</span>
        </span>
        <span className="lx-bill-row lx-bill-row--total">
          <span>Total</span>
          <span>{Currency.format(cartBill.total)}</span>
        </span>
      </div>
      <div className="lx-ticket lx-v-cart__ticket" data-parallax="0.14">
        <span>Order placed</span>
        <strong>#OD12346</strong>
        <small>Table 05 · 4 items</small>
      </div>
    </div>
  );
}

function PayVisual() {
  const options: [ReactNode, string, string][] = [
    [<Smartphone size={18} key="i" />, 'UPI', 'Pay from any UPI app'],
    [<QrIcon size={18} key="i" />, 'QR Payment', 'Scan with any UPI app'],
    [<Banknote size={18} key="i" />, 'Cash', 'Pay staff or at the counter'],
    [<Store size={18} key="i" />, 'Pay at Counter', 'Any method they take'],
  ];
  return (
    <div className="lx-v lx-v--pay">
      <div className="lx-panel lx-v-pay__panel">
        <span className="lx-v-pay__amount">
          <small>AMOUNT TO PAY</small>
          {Currency.format(cartBill.total)}
        </span>
        {options.map(([icon, label, text], i) => (
          <span key={label} className={`lx-pay-row ${i === 0 ? 'is-on' : ''}`}>
            <span className="lx-pay-row__icon">{icon}</span>
            <span className="lx-pay-row__text">
              <span>{label}</span>
              <small>{text}</small>
            </span>
            <span className="lx-pay-row__radio" />
          </span>
        ))}
      </div>
      <div className="lx-panel lx-panel--glass lx-v-pay__result" data-parallax="0.1">
        <span className="lx-v-pay__check">
          <Check size={22} />
        </span>
        <span>
          <strong>Payment confirmed</strong>
          <small>Bill marked paid</small>
        </span>
      </div>
    </div>
  );
}

function DashboardVisual() {
  const columns: [string, ReactNode, [string, string, string][]][] = [
    ['New', <ReceiptText size={14} key="i" />, [['#OD12347', 'Table 12', '2 × Masala Dosa'], ['#OD12348', 'Takeaway', '1 × Cold Coffee']]],
    ['Preparing', <ChefHat size={14} key="i" />, [['#OD12346', 'Table 05', '1 × Butter Chicken']]],
    ['Ready', <ConciergeBell size={14} key="i" />, [['#OD12344', 'Table 03', '2 × Gulab Jamun']]],
  ];
  return (
    <div className="lx-v lx-v--dash" data-live>
      <div className="lx-tablet">
        <div className="lx-tablet__bar">
          <DineQrMark size={22} />
          <span>DineQR Admin · Orders</span>
          <span className="lx-tablet__live">
            <span className="lx-pulse" /> Live
          </span>
        </div>
        <div className="lx-tablet__board">
          {columns.map(([name, icon, tickets]) => (
            <div key={name} className="lx-col">
              <span className="lx-col__head">
                {icon} {name} <b>{tickets.length}</b>
              </span>
              {tickets.map(([id, where, what], i) => (
                <span key={id} className="lx-order" style={{ '--i': i } as CSSProperties}>
                  <strong>{id}</strong>
                  <small>{where}</small>
                  <span>{what}</span>
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
