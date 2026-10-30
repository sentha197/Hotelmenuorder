const id = (value: string) => encodeURIComponent(value);

/** Every in-app URL. Ordering URLs survive a page refresh. */
export const paths = {
  root: '/',
  scan: '/scan',
  /** The link printed on a table's code (also what the in-app scanner opens). */
  table: (table: number) => `/t/${table.toString().padStart(2, '0')}`,
  takeaway: '/takeaway',
  home: '/home',
  menu: '/menu',
  cart: '/cart',
  orders: '/orders',
  more: '/more',
  favorites: '/favorites',
  category: (categoryId: string) => `/menu?category=${id(categoryId)}`,
  dish: (itemId: string) => `/dish/${id(itemId)}`,
  checkout: '/checkout',
  orderPlaced: (orderId: string) => `/orders/${id(orderId)}/placed`,
  tracking: (orderId: string) => `/orders/${id(orderId)}/track`,
  orderDetails: (orderId: string) => `/orders/${id(orderId)}`,
  bill: (invoiceId: string) => `/bills/${id(invoiceId)}`,
  pay: (invoiceId: string) => `/bills/${id(invoiceId)}/pay`,
  split: (invoiceId: string) => `/bills/${id(invoiceId)}/split`,
  receipt: (invoiceId: string) => `/bills/${id(invoiceId)}/receipt`,
  payments: '/payments',
  credits: '/credits',
  /** DineQR's story page (the guest app itself starts at the scanner). */
  about: '/about',
} as const;

export const tabPaths = [paths.home, paths.menu, paths.cart, paths.orders, paths.more] as const;
