import { screen, waitFor } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { FakeApi } from '../test/fakeApi';
import { pathOf, renderApp } from '../test/render';

/** Starts at table 5 and waits for the home screen. */
async function seated(api = new FakeApi()) {
  const rendered = renderApp('/t/05', { api });
  await rendered.user.click(await screen.findByTestId('start-ordering'));
  await waitFor(() => expect(pathOf(rendered.router)).toBe('/home'));
  await screen.findAllByText('Paneer Tikka');
  return rendered;
}

describe('ordering', () => {
  it('adds dishes, prices the cart and places the order with the server', async () => {
    const { api, router, user } = await seated();
    await user.click(screen.getAllByRole('button', { name: 'Add Paneer Tikka to cart' })[0]!);
    expect(await screen.findByText('Paneer Tikka added to cart')).toBeInTheDocument();
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await waitFor(() => expect(pathOf(router)).toBe('/cart'));
    // ₹240 + 5% GST.
    expect((await screen.findAllByText('₹252')).length).toBeGreaterThan(0);
    await user.click(screen.getByRole('button', { name: 'Increase Paneer Tikka' }));
    expect((await screen.findAllByText('₹504')).length).toBeGreaterThan(0);
    await user.click(screen.getByTestId('proceed'));
    await waitFor(() => expect(pathOf(router)).toBe('/checkout'));
    await user.click(await screen.findByTestId('place-order'));
    await waitFor(() => expect(pathOf(router)).toMatch(/^\/orders\/OD00001\/placed$/));
    expect(await screen.findByText(/Order Placed/)).toBeInTheDocument();
    const order = api.requests.find((r) => r.method === 'POST' && r.path === '/orders');
    expect(order?.body).toMatchObject({
      lines: [{ itemId: 'paneer_tikka', quantity: 2, options: { spice: 'medium' } }],
      orderType: 'dineIn',
      expectedTotal: 50400,
    });
    expect(order?.auth).toMatch(/^Bearer guest-5-/);
    // The cart is emptied only after the server accepted the order.
    expect(screen.queryByRole('link', { name: /Cart, / })).not.toBeInTheDocument();
  });

  it('keeps the cart and explains when the server refuses changed prices', async () => {
    const api = new FakeApi();
    const { router, user } = await seated(api);
    await user.click(screen.getAllByRole('button', { name: 'Add Butter Chicken to cart' })[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    api.failNextOrder = { status: 409, code: 'priceChanged', title: 'Prices changed since you opened the menu. Please review your cart.' };
    await user.click(await screen.findByTestId('place-order'));
    expect(await screen.findByText('Prices changed since you opened the menu. Please review your cart.')).toBeInTheDocument();
    expect(pathOf(router)).toBe('/checkout');
    expect(api.orders).toHaveLength(0);
    // Trying again reuses the same idempotency key, so no duplicate order.
    await user.click(screen.getByTestId('place-order'));
    await waitFor(() => expect(pathOf(router)).toMatch(/placed$/));
    const keys = api.requests.filter((r) => r.method === 'POST' && r.path === '/orders').map((r) => r.body?.idempotencyKey);
    expect(keys).toHaveLength(2);
    expect(keys[0]).toBe(keys[1]);
  });

  it('does not offer sold-out dishes', async () => {
    const { user } = await seated();
    await user.click(screen.getByRole('link', { name: 'Menu' }));
    expect(await screen.findByLabelText('Gulab Jamun is sold out')).toBeInTheDocument();
  });
});

describe('paying the bill', () => {
  /** Places an order and opens its payment page. */
  async function toPayment(api = new FakeApi()) {
    const rendered = await seated(api);
    const { user, router } = rendered;
    await user.click(screen.getAllByRole('button', { name: 'Add Paneer Tikka to cart' })[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    await user.click(await screen.findByTestId('place-order'));
    await user.click(await screen.findByRole('button', { name: /View Bill/ }));
    await waitFor(() => expect(pathOf(router)).toMatch(/^\/bills\//));
    await user.click(await screen.findByTestId('pay-now'));
    await screen.findByText('Choose how to pay');
    return rendered;
  }

  it('offers only cash and the counter without a gateway, and nothing is a demo', async () => {
    const { api } = await toPayment();
    expect(screen.getByText(/Online payment is not available right now/)).toBeInTheDocument();
    for (const option of ['upi', 'scanAndPay', 'card', 'netBanking', 'wallet']) {
      expect(screen.queryByTestId(`option-${option}`)).not.toBeInTheDocument();
    }
    expect(screen.getByTestId('option-cash')).toBeInTheDocument();
    expect(screen.getByTestId('option-payAtCounter')).toBeInTheDocument();
    expect(screen.queryByText(/demo/i)).not.toBeInTheDocument();
    expect(api.requests.some((r) => r.path.endsWith('/payments/intents'))).toBe(false);
  });

  it('offers QR Code Payment without UPI from an app when only QR is switched on', async () => {
    const api = new FakeApi();
    api.upiPayee = { upiId: 'bistro@okhdfcbank', payeeName: 'Test Bistro' };
    api.settings.methods = ['qr'];
    const { user } = await toPayment(api);
    expect(await screen.findByTestId('option-scanAndPay')).toBeInTheDocument();
    expect(screen.queryByTestId('option-upi')).not.toBeInTheDocument();
    expect(screen.queryByTestId('option-card')).not.toBeInTheDocument();
    await user.click(screen.getByTestId('pay-button'));
    await waitFor(() => expect(api.requests.some((r) => r.path.endsWith('/payments/upi') && r.method === 'POST')).toBe(true));
    const start = api.requests.find((r) => r.path.endsWith('/payments/upi') && r.method === 'POST');
    expect(start?.body).toMatchObject({ channel: 'qr' });
  });

  it('offers UPI from an app without QR Code Payment when only UPI is switched on', async () => {
    const api = new FakeApi();
    api.upiPayee = { upiId: 'bistro@okhdfcbank', payeeName: 'Test Bistro' };
    api.settings.methods = ['upi'];
    await toPayment(api);
    expect(await screen.findByTestId('option-upi')).toBeInTheDocument();
    expect(screen.queryByTestId('option-scanAndPay')).not.toBeInTheDocument();
  });

  it('tells staff about a cash payment without marking anything paid', async () => {
    const { api, user, router } = await seated();
    await user.click(screen.getAllByRole('button', { name: 'Add Paneer Tikka to cart' })[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    await user.click(await screen.findByTestId('place-order'));
    await user.click(await screen.findByRole('button', { name: /View Bill/ }));
    await waitFor(() => expect(pathOf(router)).toMatch(/^\/bills\//));
    await user.click(await screen.findByTestId('pay-now'));
    await user.click(await screen.findByTestId('option-cash'));
    await user.click(screen.getByTestId('pay-button'));
    expect(await screen.findByTestId('counter-result')).toHaveTextContent('Pay ₹252 in cash');
    expect(screen.getByText(/Nothing has been paid yet/)).toBeInTheDocument();
    expect(api.requests.find((r) => r.path.endsWith('/counter-request'))?.body).toEqual({ kind: 'cash', amount: 25200 });
  });
});

describe('special offers', () => {
  it('prices a dish on offer like the server, so the order goes through', async () => {
    // The production case: 50% off Butter Chicken (₹280 → ₹140, + 5% tax = ₹147).
    const api = new FakeApi();
    api.specials = [
      { id: 'special_weekend_offers', title: 'Weekend offers', discountType: 'percent', value: 5000, items: [{ itemId: 'butter_chicken', quantity: 1 }], sort: 0 },
    ];
    const { router, user } = await seated(api);
    await user.click(screen.getAllByRole('button', { name: 'Add Butter Chicken to cart' })[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    expect(await screen.findByText('Weekend offers: −₹140')).toBeInTheDocument();
    await user.click(await screen.findByTestId('proceed'));
    await waitFor(() => expect(pathOf(router)).toBe('/checkout'));
    // The checkout's own button first: the cart page may still be leaving.
    expect(await screen.findByTestId('place-order')).toHaveTextContent('₹147');
    await waitFor(() => expect(screen.getAllByText('Weekend offers: −₹140')).toHaveLength(1));
    await user.click(screen.getByTestId('place-order'));
    await waitFor(() => expect(pathOf(router)).toMatch(/placed$/));
    const order = api.requests.find((r) => r.method === 'POST' && r.path === '/orders');
    expect(order?.body?.expectedTotal).toBe(14700);
  });

  it('applies the coupon to what is left after the offer, like the server', async () => {
    const api = new FakeApi();
    api.specials = [
      { id: 'flat', title: 'Flat ₹40', discountType: 'flat', value: 4000, items: [{ itemId: 'paneer_tikka', quantity: 1 }], sort: 0 },
      { id: 'pct', title: 'Ten percent', discountType: 'percent', value: 1000, items: [{ itemId: 'paneer_tikka', quantity: 1 }], sort: 1 },
    ];
    const { app } = await seated(api);
    const paneer = app.catalog.allItems.find((i) => i.id === 'paneer_tikka')!;
    app.cart.add(paneer);
    app.cart.add(paneer);
    // ₹240 each: the best is ₹40 off (not 10% = ₹24), ×2 = ₹80; ₹400 left.
    expect(app.cart.itemSavings).toBe(8000);
    app.cart.applyOffer('WELCOME10');
    // WELCOME10: 10% of ₹400 (min ₹300) = ₹40.
    expect(app.cart.discount).toBe(12000);
    expect(app.cart.bill.total).toBe(Math.floor(((48000 - 12000) * 10500 + 5000) / 10000));
    expect(app.cart.bill.discountLabel).toBe('Offers & savings');
  });
});
