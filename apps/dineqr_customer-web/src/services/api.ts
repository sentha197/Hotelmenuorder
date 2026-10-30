import type { ApiConfig } from '../config';

/**
 * A failed API call. [status] 0 means the server was not reached; [code] is
 * the server's machine-readable reason (e.g. `tableInactive`) and [message]
 * is safe to show to the guest.
 */
export class ApiException extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }

  static network(): ApiException {
    return new ApiException(0, 'network', 'Cannot reach the restaurant server. Check your connection and try again.');
  }

  static timeout(): ApiException {
    return new ApiException(0, 'timeout', 'The server took too long to answer. Please try again.');
  }

  get isOffline(): boolean {
    return this.status === 0;
  }

  get isUnauthorized(): boolean {
    return this.status === 401;
  }

  get isNotFound(): boolean {
    return this.status === 404;
  }
}

/** The guest's ordering session ended; the table code must be scanned again. */
export class SessionExpiredError extends Error {
  constructor() {
    super('Your ordering session has ended. Scan the QR code again to continue.');
  }
}

/** A payment that cannot go ahead, with a message for the guest. */
export class PaymentError extends Error {}

export type TokenSource = () => string | null;

type Json = Record<string, unknown>;

const defaultMessages: Record<number, [string, string]> = {
  401: ['unauthorized', 'Your session has ended. Please sign in again.'],
  403: ['forbidden', 'You do not have permission to do that.'],
  404: ['notFound', 'That could not be found. It may have been removed.'],
  409: ['conflict', 'The request could not be completed.'],
  429: ['tooManyRequests', 'Too many attempts. Please wait a moment and try again.'],
};

/** RFC 7807 problem → [ApiException] with the server's own wording. */
export function problemToException(status: number, body: unknown): ApiException {
  let [code, message] =
    status >= 500
      ? ['serverError', 'The server had a problem. Please try again.']
      : (defaultMessages[status] ?? ['badRequest', 'The request could not be completed.']);
  if (body && typeof body === 'object') {
    const problem = body as Json;
    if (typeof problem.code === 'string') code = problem.code;
    if (typeof problem.title === 'string' && problem.title) message = problem.title;
  }
  return new ApiException(status, code, message);
}

/**
 * JSON over HTTP for the DineQR API. Only GET requests are retried (once);
 * anything that changes data is sent once and carries an idempotency key
 * where the API supports it.
 */
export class ApiClient {
  token: TokenSource | null = null;

  constructor(
    readonly config: ApiConfig,
    private readonly fetchImpl: typeof fetch = (...args) => fetch(...args),
  ) {}

  url(path: string, query?: Record<string, string>): string {
    const base = `${this.config.baseUrl}/api/v1${path}`;
    if (!query || Object.keys(query).length === 0) return base;
    return `${base}?${new URLSearchParams(query).toString()}`;
  }

  get hubUrl(): string {
    return `${this.config.baseUrl}/hubs/events`;
  }

  get<T = unknown>(path: string, query?: Record<string, string>): Promise<T> {
    return this.send<T>('GET', path, undefined, query, 1);
  }

  post<T = unknown>(path: string, body?: unknown): Promise<T> {
    return this.send<T>('POST', path, body);
  }

  delete<T = unknown>(path: string): Promise<T> {
    return this.send<T>('DELETE', path);
  }

  private async send<T>(method: string, path: string, body?: unknown, query?: Record<string, string>, retries = 0): Promise<T> {
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json; charset=utf-8';
    const bearer = this.token?.();
    if (bearer) headers.Authorization = `Bearer ${bearer}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    let response: Response;
    try {
      response = await this.fetchImpl(this.url(path, query), {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
        // Bearer tokens only: no cookies are ever sent.
        credentials: 'omit',
      });
    } catch {
      if (retries > 0) return this.retry<T>(method, path, body, query, retries);
      throw controller.signal.aborted ? ApiException.timeout() : ApiException.network();
    } finally {
      clearTimeout(timer);
    }
    if (response.status >= 500 && retries > 0) return this.retry<T>(method, path, body, query, retries);
    const text = await response.text();
    let decoded: unknown = null;
    if (text) {
      try {
        decoded = JSON.parse(text);
      } catch {
        decoded = null;
      }
    }
    if (response.ok) return decoded as T;
    throw problemToException(response.status, decoded);
  }

  private async retry<T>(method: string, path: string, body: unknown, query: Record<string, string> | undefined, retries: number): Promise<T> {
    await new Promise((resolve) => setTimeout(resolve, 600));
    return this.send<T>(method, path, body, query, retries - 1);
  }
}

/** A fresh idempotency key. */
export function newIdempotencyKey(): string {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  return `${Date.now().toString(36)}${Array.from(bytes, (b) => (b % 36).toString(36)).join('')}`;
}
