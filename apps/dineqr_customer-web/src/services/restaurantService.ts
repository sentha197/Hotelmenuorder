import { parseMethod, settingsFromJson, tableFromJson, type PaymentMethodType, type RestaurantSettings, type RestaurantTable } from '../core/settings';
import type { ApiClient } from './api';

type Json = Record<string, unknown>;

/** The takeaway payload of servers from before takeaway was renamed. */
export const LEGACY_TAKEAWAY_PAYLOAD = 'DINEQR:PARCEL';

/** The server's live gateway, from `GET /payments/config`. */
export interface PaymentConfig {
  providerName: string;
  /** A real gateway is connected (live mode can be used). */
  liveAvailable: boolean;
  /** Online methods it takes; null (older server) means every one. */
  liveMethods: Set<PaymentMethodType> | null;
}

export const unavailablePaymentConfig: PaymentConfig = { providerName: 'Server', liveAvailable: false, liveMethods: null };

export class RestaurantService {
  constructor(private readonly api: ApiClient) {}

  async settings(): Promise<RestaurantSettings> {
    return settingsFromJson(await this.api.get<Json>('/settings'));
  }

  /** Each table's number and whether it takes orders. */
  async tables(): Promise<RestaurantTable[]> {
    const json = await this.api.get<Json[]>('/tables');
    return json.map(tableFromJson).sort((a, b) => a.number - b.number);
  }

  async paymentConfig(): Promise<PaymentConfig> {
    const json = await this.api.get<Json>('/payments/config');
    // Servers from before payment modes describe only the provider in use.
    const live = (json.liveAvailable as boolean | undefined) ?? (json.available === true && json.simulated !== true);
    const names = json.liveMethods;
    return {
      providerName: (json.liveProvider as string | undefined) ?? (json.provider as string | undefined) ?? 'Server',
      liveAvailable: live,
      liveMethods: Array.isArray(names)
        ? new Set(names.map(parseMethod).filter((m): m is PaymentMethodType => m != null))
        : null,
    };
  }
}
