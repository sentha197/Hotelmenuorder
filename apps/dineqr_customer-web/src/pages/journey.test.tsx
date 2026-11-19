import { screen, waitFor } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { PAY_AT_COUNTER } from '../core/payAtCounter';
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

describe('paying at the billing counter', () => {
  /** Orders one Paneer Tikka (₹252 with GST) and waits for the confirmation. */
  async function placeOrder(api = new FakeApi()) {
    const rendered = await seated(api);
    const { user, router } = rendered;
    await user.click(screen.getAllByRole('button', { name: 'Add Paneer Tikka to cart' })[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    // No payment is asked for before the order is placed.
    expect(await screen.findByText(PAY_AT_COUNTER.beforeOrdering)).toBeInTheDocument();
    await user.click(await screen.findByTestId('place-order'));
    await waitFor(() => expect(pathOf(router)).toMatch(/^\/orders\/OD00001\/placed$/));
    return rendered;
  }

  it('confirms the order with the counter message, its number, dishes and total', async () => {
    const { api } = await placeOrder();
    expect(await screen.findByText(PAY_AT_COUNTER.placedMessage)).toBeInTheDocument();
    expect(screen.getByText('#OD00001')).toBeInTheDocument();
    expect(screen.getByText(/1 × Paneer Tikka/)).toBeInTheDocument();
    expect(screen.getAllByText('₹252').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Total bill').length).toBeGreaterThan(0);
    // Nothing to pay in the app.
    expect(screen.queryByRole('button', { name: /View Bill|Pay/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/UPI/)).not.toBeInTheDocument();
    expect(api.requests.some((r) => r.path.startsWith('/payments') || r.path.startsWith('/bills'))).toBe(false);
  });

  it('tracks the order and reminds the guest where to pay', async () => {
    const { user, router } = await placeOrder();
    await user.click(await screen.findByRole('button', { name: /Track Order/ }));
    await waitFor(() => expect(pathOf(router)).toMatch(/track$/));
    expect(await screen.findByText(PAY_AT_COUNTER.reminder)).toBeInTheDocument();
    expect(screen.getAllByText('₹252').length).toBeGreaterThan(0);
  });

  it('has no payment pages', async () => {
    const { user, router } = await placeOrder();
    for (const path of ['/payments', '/bills/INVOD00001', '/bills/INVOD00001/pay']) {
      await router.navigate(path);
      expect(await screen.findByText(/not found|could not find|doesn’t exist|does not exist/i)).toBeInTheDocument();
    }
    void user;
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
