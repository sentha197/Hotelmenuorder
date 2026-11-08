import { pendingOf, type LegalDocument, type LegalKind, type LegalRequirement, type LegalStatus } from '../core/legal';
import { ApiException } from '../services/api';
import type { LegalService } from '../services/legalService';
import type { LoadState } from './settingsStore';
import { Store } from './store';

/** Why accepting failed, in words the guest can act on. */
export class LegalAcceptanceError extends Error {
  constructor(
    message: string,
    /** A document was updated while the guest read it; the new version is loaded. */
    readonly versionChanged = false,
  ) {
    super(message);
  }
}

/**
 * The Terms & Conditions and Privacy Policy, and what the guest session has
 * accepted. The server checks acceptance on every order; this only lets the
 * app ask for it before the guest tries.
 */
export class LegalStore extends Store {
  documents: LegalDocument[] = [];
  documentsState: LoadState = 'idle';
  documentsError: string | null = null;
  /** Null until read, and again after the session changed. */
  status: LegalStatus | null = null;
  accepting = false;

  private loading: Promise<void> | null = null;

  constructor(private readonly service: LegalService) {
    super();
  }

  get pending(): LegalRequirement[] {
    return pendingOf(this.status);
  }

  document(kind: LegalKind): LegalDocument | undefined {
    return this.documents.find((d) => d.kind === kind);
  }

  loadDocuments(force = false): Promise<void> {
    if (!force && this.documentsState === 'ready') return Promise.resolve();
    return (this.loading ??= (async () => {
      this.documentsState = 'loading';
      this.documentsError = null;
      this.notify();
      try {
        this.documents = await this.service.published();
        this.documentsState = 'ready';
      } catch (error) {
        this.documentsState = 'error';
        this.documentsError =
          error instanceof ApiException && error.isOffline
            ? 'You are offline. Check your connection and try again.'
            : 'The document could not be loaded. Please try again.';
      } finally {
        this.loading = null;
        this.notify();
      }
    })());
  }

  /** Keeps the last status when the server cannot be asked (it checks on order anyway). */
  async refreshStatus(): Promise<LegalStatus | null> {
    try {
      this.status = await this.service.status();
      this.notify();
    } catch {
      // The order itself is refused if something is still to accept.
    }
    return this.status;
  }

  async accept(documents: LegalRequirement[]): Promise<void> {
    if (documents.length === 0) return;
    this.accepting = true;
    this.notify();
    try {
      this.status = await this.service.accept(documents);
    } catch (error) {
      if (error instanceof ApiException && error.code === 'legalVersionChanged') {
        await Promise.all([this.loadDocuments(true), this.refreshStatus()]);
        throw new LegalAcceptanceError(error.message, true);
      }
      throw new LegalAcceptanceError(
        error instanceof ApiException
          ? error.isOffline
            ? 'You are offline. Check your connection and try again.'
            : error.isUnauthorized
              ? 'Your ordering session has ended. Scan the QR code again to continue.'
              : error.message
          : 'Something went wrong. Please try again.',
      );
    } finally {
      this.accepting = false;
      this.notify();
    }
  }

  /** A new guest session: its acceptances are its own. */
  sessionChanged(): void {
    if (this.status == null) return;
    this.status = null;
    this.notify();
  }

  /** Staff may have published or withdrawn a version. */
  async documentsChanged(): Promise<void> {
    await Promise.all([
      this.documentsState === 'idle' ? Promise.resolve() : this.loadDocuments(true),
      this.status == null ? Promise.resolve() : this.refreshStatus().then(() => undefined),
    ]);
  }
}
