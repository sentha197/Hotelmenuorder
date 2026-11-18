/**
 * The restaurant's time zone, as a fixed offset from UTC. Every date shown or
 * grouped (bills, reports, kitchen timers) goes through here so all screens
 * agree on what "today" means. Configured from the restaurant settings.
 */
const MINUTE = 60_000;
const DAY = 86_400_000;

let offsetMinutes = -new Date().getTimezoneOffset();

export const RestaurantTime = {
  configure(utcOffsetMinutes: number): void {
    offsetMinutes = utcOffsetMinutes;
  },
  get offsetMinutes(): number {
    return offsetMinutes;
  },
  /** [instant] as wall-clock fields in restaurant time (read with getUTC*). */
  wall(instant: Date): Date {
    return new Date(instant.getTime() + offsetMinutes * MINUTE);
  },
  /** The instant at which the restaurant day containing [instant] starts. */
  startOfDay(instant: Date): Date {
    const w = RestaurantTime.wall(instant);
    return RestaurantTime.dayStart(w.getUTCFullYear(), w.getUTCMonth() + 1, w.getUTCDate());
  },
  /** Instant of midnight (restaurant time) on the given calendar day. */
  dayStart(year: number, month: number, day: number): Date {
    return new Date(Date.UTC(year, month - 1, day) - offsetMinutes * MINUTE);
  },
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const pad2 = (n: number) => String(n).padStart(2, '0');

function clock(w: Date): string {
  const h = w.getUTCHours();
  return `${h % 12 === 0 ? 12 : h % 12}:${pad2(w.getUTCMinutes())} ${h < 12 ? 'AM' : 'PM'}`;
}

const dateOf = (w: Date) => `${w.getUTCDate()} ${MONTHS[w.getUTCMonth()]} ${w.getUTCFullYear()}`;
const shortOf = (w: Date) => `${w.getUTCDate()} ${MONTHS[w.getUTCMonth()]}`;

/** A half-open time range `[start, end)` aligned to restaurant days. */
export type RangePreset = 'today' | 'yesterday' | 'last7' | 'last30' | 'custom';

export const rangePresetLabel: Record<RangePreset, string> = {
  today: 'Today',
  yesterday: 'Yesterday',
  last7: 'Last 7 days',
  last30: 'Last 30 days',
  custom: 'Custom',
};

export interface DateRange {
  start: Date;
  end: Date;
  preset: RangePreset;
}

export const DateRanges = {
  preset(preset: RangePreset, now: Date): DateRange {
    const today = RestaurantTime.startOfDay(now).getTime();
    const at = (ms: number) => new Date(ms);
    switch (preset) {
      case 'today':
        return { start: at(today), end: at(today + DAY), preset };
      case 'yesterday':
        return { start: at(today - DAY), end: at(today), preset };
      case 'last7':
        return { start: at(today - 6 * DAY), end: at(today + DAY), preset };
      case 'last30':
        return { start: at(today - 29 * DAY), end: at(today + DAY), preset };
      case 'custom':
        return { start: at(today), end: at(today + DAY), preset };
    }
  },
  /** Whole restaurant days from [first] to [last] (inclusive), as `yyyy-mm-dd`. */
  days(first: string, last: string): DateRange {
    const parse = (s: string) => {
      const [y, m, d] = s.split('-').map(Number);
      return RestaurantTime.dayStart(y!, m!, d!).getTime();
    };
    const a = parse(first);
    const b = parse(last);
    return { start: new Date(Math.min(a, b)), end: new Date(Math.max(a, b) + DAY), preset: 'custom' };
  },
  contains(range: DateRange, instant: Date): boolean {
    const t = instant.getTime();
    return t >= range.start.getTime() && t < range.end.getTime();
  },
  dayCount(range: DateRange): number {
    return Math.max(1, Math.round((range.end.getTime() - range.start.getTime()) / 3_600_000 / 24));
  },
  /** Start instant of each restaurant day in the range. */
  dayStarts(range: DateRange): Date[] {
    return Array.from({ length: DateRanges.dayCount(range) }, (_, i) => new Date(range.start.getTime() + i * DAY));
  },
  /** The range of the same length immediately before this one. */
  previous(range: DateRange): DateRange {
    const length = range.end.getTime() - range.start.getTime();
    return { start: new Date(range.start.getTime() - length), end: range.start, preset: 'custom' };
  },
};

/**
 * The single place where dates, times and identifiers become text. Dates are
 * shown in restaurant time.
 */
export const AppFormat = {
  /** `12:30 PM` */
  time: (value: Date) => clock(RestaurantTime.wall(value)),
  /** `17 Oct 2026, 12:30 PM` */
  dateTime: (value: Date) => {
    const w = RestaurantTime.wall(value);
    return `${dateOf(w)}, ${clock(w)}`;
  },
  /** `17 Oct 2026` */
  date: (value: Date) => dateOf(RestaurantTime.wall(value)),
  /** `17 Oct` */
  shortDate: (value: Date) => shortOf(RestaurantTime.wall(value)),
  /** `17 Oct 2026` for a calendar day (a UTC midnight), never converted. */
  day: (value: Date) => dateOf(value),
  /** `17 Oct` for a calendar day. */
  shortDay: (value: Date) => shortOf(value),
  /** `Sat` */
  weekday: (value: Date) => WEEKDAYS[RestaurantTime.wall(value).getUTCDay()]!,
  /** Day of month in restaurant time, e.g. `17`. */
  dayOfMonth: (value: Date) => String(RestaurantTime.wall(value).getUTCDate()),
  /** `20261017`, for export file names. */
  fileStamp: (value: Date) => {
    const w = RestaurantTime.wall(value);
    return `${w.getUTCFullYear()}${pad2(w.getUTCMonth() + 1)}${pad2(w.getUTCDate())}`;
  },
  /** `17 Oct – 23 Oct 2026` (end is exclusive). */
  range: (range: DateRange) => {
    const last = new Date(range.end.getTime() - 1);
    if (DateRanges.dayCount(range) === 1) return AppFormat.date(range.start);
    return `${AppFormat.shortDate(range.start)} – ${AppFormat.date(last)}`;
  },
  /** Table numbers are always shown with two digits: `05`. */
  table: (n: number) => String(n).padStart(2, '0'),
  /** `#OD12345` */
  orderNumber: (id: string) => `#${id}`,
  /** `1 item`, `3 items` */
  itemCount: (count: number) => (count === 1 ? '1 item' : `${count} items`),
  /** `5 min`, `1 h 05 min` */
  minutes: (value: number) => (value < 60 ? `${value} min` : `${Math.floor(value / 60)} h ${pad2(value % 60)} min`),
};

/** `UTC+05:30` */
export function formatOffset(minutes: number): string {
  const sign = minutes < 0 ? '−' : '+';
  const abs = Math.abs(minutes);
  return `UTC${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`;
}

/** Offsets from UTC−12:00 to UTC+14:00 in half hours, plus +05:45. */
export const utcOffsets: readonly number[] = (() => {
  const all: number[] = [];
  for (let m = -720; m <= 840; m += 30) all.push(m);
  all.push(345);
  return all.sort((a, b) => a - b);
})();

/** Whole minutes between two instants (for kitchen timers). */
export const minutesBetween = (from: Date, to: Date) => Math.floor((to.getTime() - from.getTime()) / MINUTE);

/** Parses an ISO timestamp from the API. */
export const parseInstant = (value: unknown): Date => new Date(String(value));

export const parseOptionalInstant = (value: unknown): Date | null => {
  if (typeof value !== 'string' || !value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** Short random id (idempotency keys). */
export function randomId(length = 16): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}
