import { screen, waitFor, within } from '@testing-library/react';
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
  async function toPayment(outcome: 'success' | 'failure') {
    const rendered = await seated();
    const { user, router } = rendered;
    await user.click(screen.getAllByRole('button', { name: 'Add Paneer Tikka to cart' })[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    await user.click(await screen.findByTestId('place-order'));
    await user.click(await screen.findByRole('button', { name: /View Bill/ }));
    await waitFor(() => expect(pathOf(router)).toMatch(/^\/bills\//));
    await user.click(await screen.findByTestId('pay-now'));
    await user.click(await screen.findByTestId('option-card'));
    await user.click(screen.getByTestId('pay-button'));
    const sheet = await screen.findByRole('dialog');
    expect(within(sheet).getByText('DEMO PAYMENT')).toBeInTheDocument();
    if (outcome === 'success') await user.click(within(sheet).getByTestId('confirm-demo'));
    else await user.click(within(sheet).getByRole('button', { name: /Simulate failure/ }));
    return rendered;
  }

  it('shows success only after the server confirmed the demo payment', async () => {
    const { api } = await toPayment('success');
    expect(await screen.findByTestId('payment-result')).toHaveTextContent('Demo payment successful');
    const confirm = api.requests.find((r) => r.path.endsWith('/confirm'));
    expect(confirm?.body).toEqual({ simulatedOutcome: 'success' });
    expect(screen.getByText(/No money was charged or transferred/)).toBeInTheDocument();
    expect(screen.getAllByText('Paid').length).toBeGreaterThan(0);
  });

  it('reports a failed payment and leaves the bill unpaid', async () => {
    await toPayment('failure');
    expect(await screen.findByTestId('payment-result')).toHaveTextContent('Payment failed');
    expect(screen.getByText('Declined by the demo simulator. No money was taken.')).toBeInTheDocument();
    expect(screen.queryByText(/payment successful/i)).not.toBeInTheDocument();
    expect(screen.getByText('Payment failed', { selector: '.pill' })).toBeInTheDocument();
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
