import { screen, waitFor } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { LocationProvider, LocationReading } from '../services/locationService';
import { FakeApi } from '../test/fakeApi';
import { pathOf, renderApp } from '../test/render';

const OUTSIDE = "You are outside the restaurant's permitted location. Please move closer to the restaurant to place your order.";

/** The phone's GPS: [metres] north of the restaurant, or a failure. */
class Device implements LocationProvider {
  next: LocationReading = Device.at(5);

  static at(metres: number): LocationReading {
    return { position: { latitude: 13.0827 + metres / 111195, longitude: 80.2707, accuracy: 5, capturedAt: new Date() } };
  }

  current(): Promise<LocationReading> {
    return Promise.resolve(this.next);
  }
}

async function seated(api: FakeApi, device: Device) {
  const rendered = renderApp('/t/05', { api, locationProvider: device });
  await rendered.user.click(await screen.findByTestId('start-ordering'));
  await waitFor(() => expect(pathOf(rendered.router)).toBe('/home'));
  return rendered;
}

describe('GPS ordering area', () => {
  it('inside the radius the guest orders, with the position sent to the server', async () => {
    const api = new FakeApi();
    api.geofence.enabled = true;
    const device = new Device();
    const { user, router } = await seated(api, device);
    await user.click((await screen.findAllByRole('button', { name: 'Add Paneer Tikka to cart' }))[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    await user.click(await screen.findByTestId('place-order'));
    await waitFor(() => expect(pathOf(router)).toMatch(/placed$/));
    const order = api.requests.find((r) => r.method === 'POST' && r.path === '/orders');
    expect(order?.body?.location).toMatchObject({ latitude: expect.any(Number), longitude: 80.2707, accuracy: 5, mocked: false });
  });

  it('outside the radius, without permission or with GPS off, ordering is locked', async () => {
    const api = new FakeApi();
    api.geofence.enabled = true;
    const device = new Device();
    device.next = Device.at(80);
    const { user } = await seated(api, device);

    expect(await screen.findByText('You are too far from the restaurant')).toBeInTheDocument();
    expect(screen.getByText(OUTSIDE)).toBeInTheDocument();
    expect(screen.getByText(/Ordering within 20 m of the restaurant/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Add Paneer Tikka to cart' })).not.toBeInTheDocument();

    device.next = { failure: 'permissionDenied' };
    await user.click(screen.getByTestId('location-retry'));
    expect(await screen.findByText('Allow location to order')).toBeInTheDocument();

    device.next = { failure: 'serviceDisabled' };
    await user.click(screen.getByTestId('location-retry'));
    expect(await screen.findByText('Turn on location')).toBeInTheDocument();

    // Back at the restaurant: the menu opens again.
    device.next = Device.at(2);
    await user.click(screen.getByTestId('location-retry'));
    expect((await screen.findAllByRole('button', { name: 'Add Paneer Tikka to cart' })).length).toBeGreaterThan(0);
  });

  it('checkout measures again and stops when the guest has walked away', async () => {
    const api = new FakeApi();
    api.geofence.enabled = true;
    const device = new Device();
    const { user, router } = await seated(api, device);
    await user.click((await screen.findAllByRole('button', { name: 'Add Paneer Tikka to cart' }))[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    await waitFor(() => expect(pathOf(router)).toBe('/checkout'));
    device.next = Device.at(150);
    await user.click(await screen.findByTestId('place-order'));
    expect((await screen.findAllByText(OUTSIDE)).length).toBeGreaterThan(0);
    expect(api.orders).toHaveLength(0);
    expect(api.requests.some((r) => r.method === 'POST' && r.path === '/orders')).toBe(false);
  });

  it('the server refuses a direct order without a position or from outside', async () => {
    const api = new FakeApi();
    api.geofence.enabled = true;
    const { app } = await seated(api, new Device());
    // The app bypassed: the guest's own token, straight to the API.
    const post = (location?: object) =>
      api.fetch('http://api.test/api/v1/orders', {
        method: 'POST',
        headers: { Authorization: `Bearer ${app.guest.currentToken()}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ lines: [{ itemId: 'lassi', quantity: 1 }], idempotencyKey: 'direct-123456', location }),
      });
    const missing = await post();
    expect(missing.status).toBe(403);
    expect((await missing.json()).code).toBe('locationRequired');
    const far = await post({ latitude: 13.1, longitude: 80.2707, accuracy: 5 });
    expect((await far.json()).code).toBe('outsideRestaurantArea');
    expect(api.orders).toHaveLength(0);
  });

  it('switched off, nothing is asked', async () => {
    const api = new FakeApi();
    const device = new Device();
    device.next = { failure: 'permissionDenied' };
    await seated(api, device);
    expect((await screen.findAllByText('Paneer Tikka')).length).toBeGreaterThan(0);
    expect(api.requests.some((r) => r.path === '/guest/location-check')).toBe(false);
  });
});
