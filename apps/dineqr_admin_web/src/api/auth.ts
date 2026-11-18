import type { AxiosInstance } from 'axios';
import { staffFromApi, type StaffAccount } from '@/core/access';
import { ApiException } from './client';

/** What sign-in failures mean for the person at the login form (AuthError). */
export type AuthError = 'invalidInput' | 'invalidCredentials' | 'inactive' | 'lockedOut' | 'unavailable';

export const authErrorMessage: Record<AuthError, string> = {
  invalidInput: 'Enter your email and password.',
  invalidCredentials: 'Incorrect email or password.',
  inactive: 'This account has been deactivated. Contact the restaurant owner.',
  lockedOut: 'Too many attempts. Try again in a minute.',
  unavailable: 'Sign-in is unavailable right now. Please try again.',
};

export class AuthException extends Error {
  constructor(readonly error: AuthError) {
    super(authErrorMessage[error]);
  }
}

export interface SignedIn {
  staff: StaffAccount;
  /** The session's hard end (8 hours after sign-in). */
  sessionExpiresAt: Date;
}

/** The Flutter app's secure-storage key, kept for the same meaning. */
const REFRESH_KEY = 'dineqr.staff.refresh';
const LOCK_NAME = 'dineqr.staff.refresh';

function readStored(): string | null {
  try {
    return window.localStorage.getItem(REFRESH_KEY);
  } catch {
    return null;
  }
}

/**
 * This tab's short-lived access token, kept in session storage so reloading
 * the page does not rotate the refresh token every time (the server allows
 * only a few refreshes a minute). Cleared when the tab closes.
 */
const ACCESS_KEY = 'dineqr.staff.access';

interface StoredAccess {
  token: string;
  expires: number;
  session: string;
}

function readAccess(): StoredAccess | null {
  try {
    const raw = window.sessionStorage.getItem(ACCESS_KEY);
    return raw ? (JSON.parse(raw) as StoredAccess) : null;
  } catch {
    return null;
  }
}

function writeAccess(value: StoredAccess | null) {
  try {
    if (value == null) window.sessionStorage.removeItem(ACCESS_KEY);
    else window.sessionStorage.setItem(ACCESS_KEY, JSON.stringify(value));
  } catch {
    // Kept in memory only.
  }
}

/** Only an answer that refuses the token ends the session; rate limits and server errors keep it. */
const refused = (error: unknown) => error instanceof ApiException && error.isUnauthorized;

function writeStored(value: string | null) {
  try {
    if (value == null) window.localStorage.removeItem(REFRESH_KEY);
    else window.localStorage.setItem(REFRESH_KEY, value);
  } catch {
    // Storage blocked (private mode): the session lasts until the tab closes.
  }
}

/**
 * Runs [task] while no other tab of this app refreshes the session. The
 * server rotates refresh tokens and ends the whole session when an old one
 * is presented again, so every tab must refresh with the newest token.
 */
async function exclusively<T>(task: () => Promise<T>): Promise<T> {
  const locks = (navigator as Navigator & { locks?: LockManager }).locks;
  if (!locks?.request) return task();
  return locks.request(LOCK_NAME, task) as Promise<T>;
}

/**
 * Staff sign-in against the server (HttpAuthService). The short-lived access
 * token stays in memory; the refresh token is kept in this browser's storage
 * so staff stay signed in (up to the 8-hour session), as the Flutter app keeps
 * it in secure storage. A refresh always reads the newest stored token.
 */
export class AuthService {
  private access: string | null = null;
  private accessExpires = 0;
  private hasRefresh = false;
  private renewing: Promise<boolean> | null = null;

  /** The server refused the session (ended, expired, deactivated). */
  onSessionLost: ((message: string) => void) | null = null;

  constructor(private readonly plain: AxiosInstance) {
    // Signed out in another tab: this tab's session is gone too.
    window.addEventListener('storage', (event) => {
      if (event.key === REFRESH_KEY && event.newValue == null && this.hasSession) {
        this.forget();
        this.onSessionLost?.('You signed out in another tab.');
      }
    });
  }

  get hasSession(): boolean {
    return this.access != null || this.hasRefresh;
  }

  async signIn(email: string, password: string): Promise<SignedIn> {
    try {
      const { data } = await this.plain.post('/auth/login', { email: email.trim(), password });
      return this.accept(data as Record<string, unknown>);
    } catch (error) {
      if (!(error instanceof ApiException)) throw new AuthException('unavailable');
      switch (error.code) {
        case 'invalidInput':
          throw new AuthException('invalidInput');
        case 'invalidCredentials':
          throw new AuthException('invalidCredentials');
        case 'lockedOut':
        case 'tooManyRequests':
          throw new AuthException('lockedOut');
        case 'forbidden':
          throw new AuthException('inactive');
        default:
          throw new AuthException('unavailable');
      }
    }
  }

  /**
   * Restores the saved session. Null when there is none or the server
   * refused it (the token is then forgotten). Throws the [ApiException] when
   * the server could not be reached, keeping the token for a retry.
   */
  async restore(): Promise<SignedIn | null> {
    const saved = readStored();
    if (!saved) return null;
    // A reload within the access token's lifetime: ask who it belongs to.
    const access = readAccess();
    if (access && Date.now() < access.expires - 60_000) {
      try {
        const { data } = await this.plain.get('/auth/me', { headers: { Authorization: `Bearer ${access.token}` } });
        this.access = access.token;
        this.accessExpires = access.expires;
        this.hasRefresh = true;
        return { staff: staffFromApi(data as Record<string, unknown>), sessionExpiresAt: new Date(access.session) };
      } catch (error) {
        if (!refused(error)) throw error;
        writeAccess(null);
      }
    }
    return exclusively(async () => {
      const newest = readStored();
      if (!newest) return null;
      try {
        const { data } = await this.plain.post('/auth/refresh', { refreshToken: newest });
        return this.accept(data as Record<string, unknown>);
      } catch (error) {
        // Unreachable, rate-limited or failing: keep the sign-in for a retry.
        if (!refused(error)) throw error;
        this.forget();
        return null;
      }
    });
  }

  async signOut(): Promise<void> {
    const refresh = readStored();
    try {
      if (refresh) await this.plain.post('/auth/logout', { refreshToken: refresh });
    } catch {
      // Best effort: the session expires on the server anyway.
    } finally {
      this.forget();
    }
  }

  /** A valid access token, renewed shortly before it expires. */
  accessToken = async (): Promise<string | null> => {
    if (this.access && Date.now() < this.accessExpires - 30_000) return this.access;
    if (!this.hasRefresh) return this.access;
    await this.renew();
    return this.access;
  };

  /** Exchanges the newest refresh token for a new pair (one call at a time). */
  renew = (): Promise<boolean> => {
    this.renewing ??= this.doRenew().finally(() => {
      this.renewing = null;
    });
    return this.renewing;
  };

  private async doRenew(): Promise<boolean> {
    return exclusively(async () => {
      const refresh = readStored();
      if (!refresh) {
        if (this.hasSession) {
          this.forget();
          this.onSessionLost?.('Your session has ended. Please sign in again.');
        }
        return false;
      }
      try {
        const { data } = await this.plain.post('/auth/refresh', { refreshToken: refresh });
        this.accept(data as Record<string, unknown>);
        return true;
      } catch (error) {
        if (!refused(error)) return false;
        this.forget();
        this.onSessionLost?.(error instanceof ApiException ? error.message : 'Your session has ended. Please sign in again.');
        return false;
      }
    });
  }

  private accept(json: Record<string, unknown>): SignedIn {
    this.access = String(json.accessToken);
    this.accessExpires = new Date(String(json.accessTokenExpiresAt)).getTime();
    this.hasRefresh = true;
    writeStored(String(json.refreshToken));
    writeAccess({ token: this.access, expires: this.accessExpires, session: String(json.sessionExpiresAt) });
    return {
      staff: staffFromApi(json.staff as Record<string, unknown>),
      sessionExpiresAt: new Date(String(json.sessionExpiresAt)),
    };
  }

  private forget() {
    this.access = null;
    this.accessExpires = 0;
    this.hasRefresh = false;
    writeStored(null);
    writeAccess(null);
  }
}
