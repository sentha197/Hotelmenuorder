import { settingsFromJson, tableFromJson, type RestaurantSettings, type RestaurantTable } from '../core/settings';
import type { ApiClient } from './api';

type Json = Record<string, unknown>;

/** The takeaway payload of servers from before takeaway was renamed. */
export const LEGACY_TAKEAWAY_PAYLOAD = 'DINEQR:PARCEL';

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
}
