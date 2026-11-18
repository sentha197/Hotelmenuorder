import axios, { AxiosError, type AxiosInstance, type InternalAxiosRequestConfig } from 'axios';
import type { ApiConfig } from '@/config/env';

/**
 * A failed API call. [status] 0 means the server was not reached; [code] is
 * the server's machine-readable reason (e.g. `invalidCredentials`) and
 * [message] is safe to show to staff.
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

  get isForbidden(): boolean {
    return this.status === 403;
  }

  get isNotFound(): boolean {
    return this.status === 404;
  }
}

const defaults: Record<number, [string, string]> = {
  401: ['unauthorized', 'Your session has ended. Please sign in again.'],
  403: ['forbidden', 'You do not have permission to do that.'],
  404: ['notFound', 'That could not be found. It may have been removed.'],
  409: ['conflict', 'The request could not be completed.'],
  429: ['tooManyRequests', 'Too many attempts. Please wait a moment and try again.'],
};

/** RFC 7807 problem → [ApiException] with the server's own wording. */
export function problemToException(status: number, body: unknown): ApiException {
  let [code, message] = status >= 500 ? ['serverError', 'The server had a problem. Please try again.'] : (defaults[status] ?? ['badRequest', 'The request could not be completed.']);
  if (body && typeof body === 'object') {
    const problem = body as Record<string, unknown>;
    if (typeof problem.code === 'string') code = problem.code;
    if (typeof problem.title === 'string' && problem.title) message = problem.title;
  }
  return new ApiException(status, code, message);
}

interface RetryConfig extends InternalAxiosRequestConfig {
  _retries?: number;
  _renewed?: boolean;
}

export interface ClientHooks {
  /** A valid access token (renewed shortly before it expires), or null. */
  token?: () => Promise<string | null>;
  /** Called after a 401: renews the session and says whether to retry once. */
  renewSession?: () => Promise<boolean>;
}

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * JSON over HTTP for the DineQR API (`<base>/api/v1`). Only GET requests are
 * retried (once, after 600 ms, on a network failure or a 5xx); anything that
 * changes data is sent once and carries an idempotency key where the API
 * supports it. A 401 renews the session and retries once. Bearer tokens
 * only: no cookies are ever sent.
 */
export function createApiClient(config: ApiConfig, hooks: ClientHooks = {}): AxiosInstance {
  const http = axios.create({
    baseURL: `${config.baseUrl}/api/v1`,
    timeout: config.timeoutMs,
    withCredentials: false,
    headers: { Accept: 'application/json' },
  });

  http.interceptors.request.use(async (request) => {
    const bearer = await hooks.token?.();
    if (bearer) request.headers.set('Authorization', `Bearer ${bearer}`);
    if (request.data != null && !(request.data instanceof FormData)) {
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
    }
    return request;
  });

  http.interceptors.response.use(
    (response) => response,
    async (error: unknown) => {
      if (!(error instanceof AxiosError)) throw error;
      const request = error.config as RetryConfig | undefined;
      const isGet = (request?.method ?? 'get').toLowerCase() === 'get';
      const retriesLeft = request ? (request._retries ?? (isGet ? 1 : 0)) : 0;

      if (!error.response) {
        if (request && retriesLeft > 0) {
          await delay(600);
          return http.request({ ...request, _retries: retriesLeft - 1 } as RetryConfig);
        }
        throw error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT' ? ApiException.timeout() : ApiException.network();
      }

      const status = error.response.status;
      if (status === 401 && request && !request._renewed && hooks.renewSession) {
        if (await hooks.renewSession()) {
          return http.request({ ...request, _renewed: true, _retries: 0 } as RetryConfig);
        }
      }
      if (status >= 500 && request && retriesLeft > 0) {
        await delay(600);
        return http.request({ ...request, _retries: retriesLeft - 1 } as RetryConfig);
      }
      throw problemToException(status, error.response.data);
    },
  );
  return http;
}

/** A fresh idempotency key (random, URL-safe). */
export function newIdempotencyKey(): string {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  return `${Date.now().toString(36)}${Array.from(bytes, (b) => (b % 36).toString(36)).join('')}`;
}
