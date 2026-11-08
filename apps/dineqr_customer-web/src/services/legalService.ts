import {
  legalDocumentFromJson,
  legalStatusFromJson,
  noLegalRequirements,
  type LegalDocument,
  type LegalRequirement,
  type LegalStatus,
} from '../core/legal';
import { ApiException, type ApiClient } from './api';

type Json = Record<string, unknown>;

/** The published documents and the guest session's acceptances. */
export class LegalService {
  constructor(private readonly api: ApiClient) {}

  /** Anyone can read them, before scanning too. */
  async published(): Promise<LegalDocument[]> {
    try {
      return (await this.api.get<Json[]>('/legal/documents'))
        .map(legalDocumentFromJson)
        .filter((d): d is LegalDocument => d != null);
    } catch (error) {
      // A server from before the documents existed has none.
      if (error instanceof ApiException && error.isNotFound) return [];
      throw error;
    }
  }

  /** What the guest session still has to accept. */
  async status(): Promise<LegalStatus> {
    try {
      return legalStatusFromJson(await this.api.get<Json>('/guest/legal'));
    } catch (error) {
      if (error instanceof ApiException && error.isNotFound) return noLegalRequirements;
      throw error;
    }
  }

  /** Records the guest's acceptance of each document's version. */
  async accept(documents: LegalRequirement[]): Promise<LegalStatus> {
    return legalStatusFromJson(
      await this.api.post<Json>('/guest/legal/acceptances', {
        documents: documents.map((d) => ({ kind: d.kind, version: d.version })),
      }),
    );
  }
}
