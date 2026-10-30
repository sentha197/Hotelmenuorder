// A real-browser run of the customer journey, with a fake camera that
// shows a printed table QR code. Needs the built app served (vite preview)
// and a DineQR API with a throwaway database. Usage:
//   node e2e/browser-smoke.mjs <web base url> <qr video .y4m> <screenshot dir>
// It places a real order (demo payment) on that API.
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const [base, video, outDir] = process.argv.slice(2);
if (!base || !video || !outDir) {
  console.error('usage: node e2e/browser-smoke.mjs <base> <video.y4m> <outDir>');
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });

const results = [];
const errors = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};
const shot = (page, name) => page.screenshot({ path: `${outDir}/${name}.png`, fullPage: false });
const noOverflow = async (page, name) => {
  const { scroll, width } = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, width: window.innerWidth }));
  check(`no horizontal overflow: ${name}`, scroll <= width, `${scroll} <= ${width}`);
};
const watch = (page, label) => {
  page.on('console', (m) => m.type() === 'error' && errors.push(`${label}: ${m.text()}`));
  page.on('pageerror', (e) => errors.push(`${label}: ${e.message}`));
};

const phone = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true };

// 1. Camera allowed, showing the table's code.
const browser = await chromium.launch({
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-video-capture=${video}`],
});
try {
  const context = await browser.newContext({ ...phone, permissions: ['camera'] });
  const page = await context.newPage();
  watch(page, 'journey');

  await page.goto(`${base}/`);
  await page.getByRole('heading', { name: 'Scan QR Code' }).waitFor();
  check('root URL shows the scanner first', true);
  await page.waitForTimeout(600);
  await shot(page, '01-scanner');
  await noOverflow(page, 'scanner');

  await page.waitForURL(/\/t\/05$/, { timeout: 20_000 });
  check('in-page camera decoded the printed link and opened /t/05', true);
  await page.getByText('Welcome to').waitFor();
  await page.waitForTimeout(900);
  await shot(page, '02-welcome');
  await noOverflow(page, 'welcome');

  await page.getByTestId('start-ordering').click();
  await page.waitForURL(/\/home$/);
  await page.getByRole('heading', { name: 'What are you craving today?' }).waitFor();
  await page.locator('.food-card').first().waitFor();
  await page.waitForTimeout(800);
  check('Start Ordering opened the menu (server session)', true);
  await shot(page, '03-home');
  await noOverflow(page, 'home');

  await page.locator('.food-card .add-btn').first().click();
  await page.getByText(/added to cart/).waitFor();
  await page.waitForTimeout(400);
  await shot(page, '04-added');
  await page.getByRole('link', { name: /^Menu$/ }).click();
  await page.waitForURL(/\/menu$/);
  await page.locator('.food-tile').first().waitFor();
  await page.waitForTimeout(500);
  await shot(page, '05-menu');
  await noOverflow(page, 'menu');

  await page.locator('.food-tile').nth(1).click();
  await page.waitForURL(/\/dish\//);
  await page.getByTestId('add-to-cart').waitFor();
  await page.waitForTimeout(600);
  await shot(page, '06-dish');
  await noOverflow(page, 'dish');
  await page.getByTestId('add-to-cart').click();
  await page.getByTestId('add-to-cart').getByText('Added to Cart').waitFor();
  check('dish page adds with its options', true);

  await page.goto(`${base}/cart`);
  await page.getByRole('heading', { name: 'My Cart' }).waitFor();
  check('a page reload on a nested URL keeps the session (/cart)', true);
  await page.waitForTimeout(500);
  await shot(page, '07-cart');
  await noOverflow(page, 'cart');

  await page.getByTestId('proceed').click();
  await page.waitForURL(/\/checkout$/);
  await page.waitForTimeout(500);
  await shot(page, '08-checkout');
  await page.getByTestId('place-order').click();
  await page.waitForURL(/\/orders\/[^/]+\/placed$/, { timeout: 20_000 });
  await page.getByText('Successfully!').waitFor();
  await page.waitForTimeout(1300);
  check('order placed on the server', true);
  await shot(page, '09-placed');
  await noOverflow(page, 'order placed');

  await page.getByRole('button', { name: 'Track Order' }).click();
  await page.waitForURL(/\/track$/);
  await page.waitForTimeout(700);
  await shot(page, '10-tracking');

  await page.goto(`${base}/orders`);
  await page.locator('.order-card').first().waitFor();
  await page.waitForTimeout(400);
  await shot(page, '11-orders');
  await page.getByRole('button', { name: 'View Bill' }).first().click();
  await page.waitForURL(/\/bills\/[^/]+$/);
  await page.waitForTimeout(500);
  await shot(page, '12-bill');
  await noOverflow(page, 'bill');

  await page.getByTestId('pay-now').click();
  await page.waitForURL(/\/pay$/);
  await page.getByTestId('option-card').click();
  await page.waitForTimeout(400);
  await shot(page, '13-payment');
  await noOverflow(page, 'payment');
  await page.getByTestId('pay-button').click();
  await page.getByTestId('confirm-demo').waitFor();
  await page.waitForTimeout(500);
  await shot(page, '14-demo-checkout');
  await page.getByTestId('confirm-demo').click();
  await page.getByTestId('payment-result').waitFor({ timeout: 20_000 });
  const result = await page.getByTestId('payment-result').textContent();
  check('demo payment result comes from the server', result === 'Demo payment successful', result ?? '');
  await page.waitForTimeout(900);
  await shot(page, '15-paid');

  await page.goto(`${base}/more`);
  await page.waitForTimeout(500);
  await shot(page, '16-more');

  // Scenario A: what Google Lens / the camera app does, open the link.
  const lens = await context.newPage();
  watch(lens, 'link');
  await lens.goto(`${base}/t/12`);
  await lens.getByText('Welcome to').waitFor();
  const scannerShown = await lens.getByRole('heading', { name: 'Scan QR Code' }).count();
  check('opening a table link goes straight to that table (no second scan)', scannerShown === 0);
  await lens.goto(`${base}/t/999`);
  await lens.getByTestId('entry-error').waitFor();
  await lens.waitForTimeout(400);
  await shot(lens, '17-bad-table');
  check('an unknown table link is refused clearly', true);

  // Wide screen.
  const desktop = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const wide = await desktop.newPage();
  watch(wide, 'desktop');
  await wide.goto(`${base}/t/03`);
  await wide.getByTestId('start-ordering').click();
  await wide.waitForURL(/\/home$/);
  await wide.locator('.food-card').first().waitFor();
  await wide.waitForTimeout(800);
  await shot(wide, '18-desktop-home');
  await noOverflow(wide, 'desktop home');
  await wide.goto(`${base}/menu`);
  await wide.locator('.food-tile').first().waitFor();
  await wide.waitForTimeout(600);
  await shot(wide, '19-desktop-menu');
  await desktop.close();
  await context.close();
} catch (error) {
  check('journey', false, String(error));
} finally {
  await browser.close();
}

// 2. Camera refused by the browser.
const denied = await chromium.launch();
try {
  const context = await denied.newContext({ ...phone });
  const page = await context.newPage();
  watch(page, 'denied');
  await page.goto(`${base}/`);
  await page.locator('.scanner__notice').first().waitFor({ timeout: 15_000 });
  const text = await page.locator('.scanner__notice').first().textContent();
  check('a refused camera shows guidance instead of crashing', true, text?.slice(0, 60) ?? '');
  await page.waitForTimeout(500);
  await shot(page, '20-camera-denied');
  await context.close();
} catch (error) {
  check('camera denied', false, String(error));
} finally {
  await denied.close();
}

// Expected noise: the live hub may refuse in some setups; anything else counts.
const relevant = errors.filter((e) => !/hubs\/events|WebSocket|negotiat/i.test(e));
check('no console errors', relevant.length === 0, relevant.slice(0, 5).join(' | '));
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
