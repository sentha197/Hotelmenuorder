import { act, screen, waitFor } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { parseLegalText } from '../core/legal';
import { FakeApi } from '../test/fakeApi';
import { pathOf, renderApp } from '../test/render';

const terms = 'I have read and accept the Terms & Conditions.';
const privacy = 'I have read and acknowledge the Privacy Policy.';

/** Seated at table 5 with Paneer Tikka in the cart, on the order summary. */
async function atCheckout(api: FakeApi) {
  const rendered = renderApp('/t/05', { api });
  const { user, router } = rendered;
  // The welcome screen links both documents.
  expect(await screen.findByRole('link', { name: 'Terms & Conditions' })).toHaveAttribute('href', '/legal/terms');
  expect(screen.getByRole('link', { name: 'Privacy Policy' })).toHaveAttribute('href', '/legal/privacy');
  await user.click(await screen.findByTestId('start-ordering'));
  await waitFor(() => expect(pathOf(router)).toBe('/home'));
  await user.click((await screen.findAllByRole('button', { name: 'Add Paneer Tikka to cart' }))[0]!);
  await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
  await user.click(await screen.findByTestId('proceed'));
  await waitFor(() => expect(pathOf(router)).toBe('/checkout'));
  return rendered;
}

describe('terms and privacy', () => {
  it('a guest ticks both boxes before their first order, and the server records it', async () => {
    const api = new FakeApi();
    api.legal = { terms: { version: 2 }, privacy: { version: 1 } };
    const { user, router } = await atCheckout(api);

    const termsBox = await screen.findByRole('checkbox', { name: terms });
    const privacyBox = screen.getByRole('checkbox', { name: privacy });
    expect(termsBox).not.toBeChecked();
    expect(privacyBox).not.toBeChecked();
    expect(screen.getByText('Tick both boxes above to place your order.')).toBeInTheDocument();
    expect(screen.getByTestId('place-order')).toBeDisabled();

    await user.click(termsBox);
    expect(screen.getByTestId('place-order')).toBeDisabled();
    await user.click(privacyBox);
    expect(screen.getByTestId('place-order')).toBeEnabled();

    await user.click(screen.getByTestId('place-order'));
    await waitFor(() => expect(pathOf(router)).toMatch(/placed$/));
    const accept = api.requests.find((r) => r.method === 'POST' && r.path === '/guest/legal/acceptances');
    expect(accept?.body).toEqual({
      documents: [
        { kind: 'terms', version: 2 },
        { kind: 'privacy', version: 1 },
      ],
    });
    // Accepted before the order was sent.
    const paths = api.requests.filter((r) => r.method === 'POST').map((r) => r.path);
    expect(paths.indexOf('/guest/legal/acceptances')).toBeLessThan(paths.indexOf('/orders'));
  });

  it('the server refuses an order without acceptance, whatever the app does', async () => {
    const api = new FakeApi();
    // Published only after the guest opened the summary.
    const { user } = await atCheckout(api);
    await waitFor(() => expect(api.requests.some((r) => r.path === '/guest/legal')).toBe(true));
    api.legal = { terms: { version: 1 } };
    await user.click(screen.getByTestId('place-order'));
    expect(await screen.findByText(/Please accept the Terms & Conditions and Privacy Policy/)).toBeInTheDocument();
    expect(api.orders).toHaveLength(0);
    // The newly published version is now asked for.
    expect(await screen.findByRole('checkbox', { name: terms })).not.toBeChecked();
    expect(screen.getByTestId('place-order')).toBeDisabled();
  });

  it('a returning guest is asked again only for a material update', async () => {
    const api = new FakeApi();
    api.legal = { terms: { version: 1 }, privacy: { version: 1 } };
    const { user, router } = await atCheckout(api);
    await user.click(await screen.findByRole('checkbox', { name: terms }));
    await user.click(screen.getByRole('checkbox', { name: privacy }));
    await user.click(screen.getByTestId('place-order'));
    await screen.findByText(/Order Placed/);

    // Minor update to the privacy policy, material update to the terms.
    api.legal = {
      terms: { version: 2, mustAcceptFrom: 2, changeSummary: 'New refund rules' },
      privacy: { version: 2, mustAcceptFrom: 1 },
    };
    // Back to the menu for another dish, and review again.
    await act(() => router.navigate('/menu'));
    await user.click((await screen.findAllByRole('button', { name: 'Add Sweet Lassi to cart' }))[0]!);
    await user.click(screen.getByRole('link', { name: 'Cart, 1' }));
    await user.click(await screen.findByTestId('proceed'));
    await waitFor(() => expect(pathOf(router)).toBe('/checkout'));
    expect(await screen.findByText('We have updated our terms')).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: terms })).toBeInTheDocument();
    expect(screen.queryByRole('checkbox', { name: privacy })).not.toBeInTheDocument();
    expect(screen.getByText('What changed: New refund rules')).toBeInTheDocument();
    expect(screen.getByText('Tick the box above to place your order.')).toBeInTheDocument();
  });

  it('opens the full document from its link, as the server published it', async () => {
    const api = new FakeApi();
    api.legal = { terms: { version: 3, changeSummary: 'Clearer payment section' }, privacy: { version: 1 } };
    renderApp('/legal/terms', { api });
    expect(await screen.findByRole('heading', { name: 'Terms & Conditions', level: 1 })).toBeInTheDocument();
    expect(screen.getByText('Version 3 · Effective 1 Nov 2026')).toBeInTheDocument();
    expect(screen.getByText('What changed: Clearer payment section')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: '1. About this terms document' })).toBeInTheDocument();
    expect(screen.getByText('Test Bistro').tagName).toBe('STRONG');
  });

  it('says so when a document is not published', async () => {
    renderApp('/legal/privacy', { api: new FakeApi() });
    expect(await screen.findByText('Not published')).toBeInTheDocument();
  });
});

describe('parseLegalText', () => {
  it('reads headings, paragraphs, bullets and bold, and nothing else', () => {
    expect(parseLegalText('## Title\n\nOne\nline.\n\n- **A:** first\n* second\n\n<b>x</b>')).toEqual([
      { type: 'heading', level: 2, spans: [{ text: 'Title', bold: false }] },
      { type: 'paragraph', spans: [{ text: 'One line.', bold: false }] },
      {
        type: 'bullets',
        items: [
          [
            { text: 'A:', bold: true },
            { text: ' first', bold: false },
          ],
          [{ text: 'second', bold: false }],
        ],
      },
      { type: 'paragraph', spans: [{ text: '<b>x</b>', bold: false }] },
    ]);
  });
});
