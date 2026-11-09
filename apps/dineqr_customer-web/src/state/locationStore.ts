import { locationAppliesTo, type DineInLocation } from '../core/settings';
import { ApiException } from '../services/api';
import {
  OUTSIDE_MESSAGE,
  type GuestPosition,
  type LocationProvider,
  type LocationService,
} from '../services/locationService';
import { Store } from './store';

export type LocationAccess = 'open' | 'checking' | 'allowed' | 'outside' | 'permissionDenied' | 'serviceDisabled' | 'unavailable';

/** Checkout stopped: the guest cannot order from where they are. */
export class LocationRefusedError extends Error {}

/**
 * The guest side of the GPS ordering area, like the Flutter app's
 * LocationAccessController. The server decides: it measures the position
 * sent with each order. This asks the browser for the position (and
 * permission) when the area covers the session, when the guest comes back
 * to the tab, and before checkout, so the guest sees why ordering stopped.
 */
export class LocationStore extends Store {
  private state_: LocationAccess = 'checking';
  message: string | null = null;
  checking = false;
  private serverRequires: boolean | null = null;
  private checkedTable: number | null = null;
  private pending: Promise<GuestPosition | null> | null = null;

  constructor(
    private readonly service: LocationService,
    private readonly provider: LocationProvider,
    private readonly area: () => DineInLocation,
    private readonly table: () => number | null,
  ) {
    super();
  }

  get isRequired(): boolean {
    const table = this.table();
    if (table == null) return false;
    if (table !== this.checkedTable) return locationAppliesTo(this.area(), table);
    return this.serverRequires ?? locationAppliesTo(this.area(), table);
  }

  get state(): LocationAccess {
    return this.isRequired ? this.state_ : 'open';
  }

  get isLocked(): boolean {
    return this.isRequired && this.state_ !== 'allowed';
  }

  get radius(): number {
    return this.area().radius;
  }

  get explanation(): string {
    if (this.message) return this.message;
    switch (this.state) {
      case 'outside':
        return OUTSIDE_MESSAGE;
      case 'permissionDenied':
        return 'Allow this page to use your location (in your browser’s site settings) to order at this restaurant.';
      case 'serviceDisabled':
        return 'Turn on location (GPS) on your phone to order at this restaurant.';
      case 'checking':
        return 'This restaurant takes orders only from guests at the restaurant. Allow your location when asked.';
      default:
        return 'Your location could not be checked. Please try again.';
    }
  }

  /** The session or the settings changed. */
  contextChanged(): void {
    if (this.table() !== this.checkedTable) {
      this.serverRequires = null;
      this.state_ = 'checking';
      this.message = null;
    }
    this.notify();
    if (this.isRequired) void this.verify();
  }

  /** An order was refused by the GPS check. */
  reportRefused(code: string, message: string): void {
    this.checkedTable = this.table();
    this.serverRequires = true;
    this.apply(code, message);
    this.notify();
  }

  verify(): Promise<GuestPosition | null> {
    return (this.pending ??= this.run().finally(() => {
      this.pending = null;
    }));
  }

  /** A fresh position for an order (null when the area does not apply). */
  async positionForOrder(): Promise<GuestPosition | null> {
    if (!this.isRequired) return null;
    const position = await this.verify();
    if (position == null) {
      if (!this.isRequired) return null;
      throw new LocationRefusedError(this.explanation);
    }
    return position;
  }

  private async run(): Promise<GuestPosition | null> {
    const table = this.table();
    if (table == null || !this.isRequired) {
      this.notify();
      return null;
    }
    this.checking = true;
    this.notify();
    let position: GuestPosition | null = null;
    try {
      const reading = await this.provider.current();
      if ('failure' in reading) {
        this.checkedTable = table;
        this.state_ = reading.failure;
        this.message = null;
        const result = await this.service.check(null);
        this.serverRequires = result.required;
        return null;
      }
      position = reading.position;
      const result = await this.service.check(position);
      this.checkedTable = table;
      this.serverRequires = result.required;
      if (!result.required) {
        this.state_ = 'open';
        this.message = null;
        return null;
      }
      if (result.allowed) {
        this.state_ = 'allowed';
        this.message = null;
        return position;
      }
      this.apply(result.code ?? 'outsideRestaurantArea', result.message ?? null);
      return null;
    } catch (error) {
      // No answer proves nothing: let an order carry the position so the
      // server decides.
      if (!(error instanceof ApiException)) throw error;
      return position;
    } finally {
      this.checking = false;
      this.notify();
    }
  }

  private apply(code: string, message: string | null): void {
    this.state_ = code === 'outsideRestaurantArea' ? 'outside' : code === 'locationRequired' ? 'permissionDenied' : 'unavailable';
    this.message = message;
  }
}
