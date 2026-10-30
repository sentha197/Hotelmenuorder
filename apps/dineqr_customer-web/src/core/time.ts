/**
 * The restaurant's time zone as a fixed offset from UTC. Every date shown
 * goes through here so all screens agree with the restaurant's clock, not
 * the guest's phone.
 */
let offsetMinutes = -new Date().getTimezoneOffset();

export const RestaurantTime = {
  configure(utcOffsetMinutes: number): void {
    offsetMinutes = utcOffsetMinutes;
  },
  get offsetMinutes(): number {
    return offsetMinutes;
  },
  /** [instant] as wall-clock fields: read them with the getUTC* methods. */
  wall(instant: Date): Date {
    return new Date(instant.getTime() + offsetMinutes * 60_000);
  },
};

export type DayGreeting = 'Good morning' | 'Good afternoon' | 'Good evening';

/** 05:00–11:59 morning, 12:00–16:59 afternoon, 17:00–04:59 evening. */
export function greetingAt(instant: Date): DayGreeting {
  const hour = RestaurantTime.wall(instant).getUTCHours();
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/** The first instant after [instant] at which [greetingAt] changes. */
export function nextGreetingChange(instant: Date): Date {
  const wall = RestaurantTime.wall(instant);
  for (const hour of [5, 12, 17]) {
    const candidate = Date.UTC(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate(), hour);
    if (candidate > wall.getTime()) return new Date(candidate - offsetMinutes * 60_000);
  }
  const next = Date.UTC(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate() + 1, 5);
  return new Date(next - offsetMinutes * 60_000);
}

const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const pad2 = (value: number) => value.toString().padStart(2, '0');

/** The single place where dates, times and identifiers become text. */
export const AppFormat = {
  /** `12:30 PM` */
  time(value: Date): string {
    const wall = RestaurantTime.wall(value);
    const hours = wall.getUTCHours();
    const h12 = hours % 12 === 0 ? 12 : hours % 12;
    return `${h12}:${pad2(wall.getUTCMinutes())} ${hours < 12 ? 'AM' : 'PM'}`;
  },
  /** `17 Oct 2026` */
  date(value: Date): string {
    const wall = RestaurantTime.wall(value);
    return `${wall.getUTCDate()} ${months[wall.getUTCMonth()]} ${wall.getUTCFullYear()}`;
  },
  /** `17 Oct 2026, 12:30 PM` */
  dateTime(value: Date): string {
    return `${AppFormat.date(value)}, ${AppFormat.time(value)}`;
  },
  /** Table numbers always have two digits: `05`. */
  table(number: number): string {
    return pad2(number);
  },
  /** `#OD12345` */
  orderNumber(id: string): string {
    return `#${id}`;
  },
  /** `1 item`, `3 items` */
  itemCount(count: number): string {
    return count === 1 ? '1 item' : `${count} items`;
  },
};

const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Random, unambiguous tokens (idempotency keys). */
export function randomId(length = 16): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  let out = '';
  for (const byte of bytes) out += alphabet[byte % alphabet.length];
  return out;
}
