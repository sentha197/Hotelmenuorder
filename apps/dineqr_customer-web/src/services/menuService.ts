import { categoryFromJson, MenuItem, type MenuCategory } from '../core/menu';
import type { ApiClient } from './api';

type Json = Record<string, unknown>;

/** The public menu (`GET /menu`): categories and dishes in one request. */
export class MenuService {
  constructor(private readonly api: ApiClient) {}

  async menu(): Promise<{ categories: MenuCategory[]; items: MenuItem[] }> {
    const json = await this.api.get<Json>('/menu');
    const categories = ((json.categories as Json[] | undefined) ?? []).map(categoryFromJson);
    categories.sort((a, b) => a.sortOrder - b.sortOrder);
    const byId = new Map(categories.map((c) => [c.id, c]));
    const items = ((json.items as Json[] | undefined) ?? []).map((item) => MenuItem.fromJson(item, byId));
    return { categories, items };
  }
}
