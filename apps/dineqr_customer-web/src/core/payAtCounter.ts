/**
 * DineQR takes no payment in the app: guests order here and pay at the
 * restaurant's billing counter.
 */
export const PAY_AT_COUNTER = {
  /** Shown once the order is placed. */
  placedMessage: 'Your order has been placed successfully! Please visit the billing counter to complete your payment.',
  /** Shown wherever an order's total is shown afterwards. */
  reminder: 'Pay at the billing counter.',
  /** Shown before the order is placed (checkout). */
  beforeOrdering: 'No payment is needed now. Place your order and pay at the billing counter.',
} as const;
