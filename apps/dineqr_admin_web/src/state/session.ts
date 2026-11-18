import { useSyncExternalStore } from 'react';
import { AuthException } from '@/api/auth';
import { ApiException } from '@/api/client';
import { PermissionDeniedError, SessionExpiredError, Staff, type Permission, type StaffAccount } from '@/core/access';
import { requireBackend } from '@/services/backend';

/**
 * The signed-in staff member (AdminSessionController). The session is the
 * guard for every privileged action in the app; the server checks the same
 * permissions on every request.
 */
export type SessionPhase = 'restoring' | 'restoreFailed' | 'signedOut' | 'signedIn';

export interface SessionState {
  phase: SessionPhase;
  staff: StaffAccount | null;
  expiresAt: Date | null;
  busy: boolean;
  /** Why the last session ended on its own (expiry, deactivation), shown once on the login screen. */
  endedReason: string | null;
  /** Restoring failed: what to tell the staff member. */
  problem: { title: string; message: string } | null;
}

let state: SessionState = { phase: 'restoring', staff: null, expiresAt: null, busy: false, endedReason: null, problem: null };
const listeners = new Set<() => void>();

function set(next: Partial<SessionState>) {
  state = { ...state, ...next };
  listeners.forEach((l) => l());
}

export const getSession = () => state;

function validSession(s: SessionState = state): boolean {
  return s.phase === 'signedIn' && s.staff != null && s.expiresAt != null && Date.now() < s.expiresAt.getTime() && s.staff.isActive;
}

export const Session = {
  get actor(): StaffAccount | null {
    return validSession() ? state.staff : null;
  },

  can(permission: Permission): boolean {
    return validSession() && Staff.can(state.staff!, permission);
  },

  /** Throws [SessionExpiredError] or [PermissionDeniedError] (AccessGuard.require). */
  require(permission: Permission): void {
    if (!validSession()) {
      if (state.phase === 'signedIn') void Session.signOut('Your session expired. Please sign in again.');
      throw new SessionExpiredError();
    }
    if (!Staff.can(state.staff!, permission)) throw new PermissionDeniedError(permission);
  },

  /**
   * Restores the saved session behind the splash. A network failure is
   * retried once by itself (a waking server often answers the second time),
   * then the staff member decides.
   */
  async restore(): Promise<void> {
    const { auth } = requireBackend();
    set({ phase: 'restoring', problem: null });
    for (let attempt = 1; ; attempt++) {
      try {
        const restored = await auth.restore();
        if (restored) set({ phase: 'signedIn', staff: restored.staff, expiresAt: restored.sessionExpiresAt, endedReason: null });
        else set({ phase: 'signedOut' });
        return;
      } catch (error) {
        if (error instanceof ApiException && error.isOffline && attempt < 2) {
          await new Promise((r) => setTimeout(r, 1000));
          continue;
        }
        set({
          phase: 'restoreFailed',
          problem:
            error instanceof ApiException
              ? {
                  title: error.isOffline ? "Can't reach the DineQR server" : "Couldn't restore your session",
                  message: `${error.message} Your sign-in is kept for when it is back.`,
                }
              : { title: "Couldn't restore your session", message: 'Try again, or sign in again.' },
        });
        return;
      }
    }
  },

  /** Leaves the splash for the sign-in screen; the saved session stays for the next start. */
  skipRestore(): void {
    set({ phase: 'signedOut', problem: null });
  },

  /** Throws [AuthException] with a message for the form. */
  async signIn(email: string, password: string): Promise<StaffAccount> {
    if (state.busy) throw new AuthException('unavailable');
    set({ busy: true });
    try {
      const result = await requireBackend().auth.signIn(email, password);
      set({ phase: 'signedIn', staff: result.staff, expiresAt: result.sessionExpiresAt, endedReason: null });
      return result.staff;
    } finally {
      set({ busy: false });
    }
  },

  async signOut(reason: string | null = null): Promise<void> {
    if (state.phase !== 'signedIn' && state.staff == null) return;
    set({ phase: 'signedOut', staff: null, expiresAt: null, endedReason: reason });
    await requireBackend().auth.signOut();
  },

  /** The session ended on the server (refresh refused). */
  lost(message: string): void {
    if (state.phase !== 'signedIn') return;
    set({ phase: 'signedOut', staff: null, expiresAt: null, endedReason: message });
  },

  /** Ends an expired session (checked every 30 s and when the tab becomes visible). */
  async checkExpiry(): Promise<void> {
    if (state.phase === 'signedIn' && state.expiresAt && Date.now() >= state.expiresAt.getTime()) {
      await Session.signOut('Your session expired. Please sign in again.');
    }
  },

  /** Applies changes to the signed-in account (role or active flag). */
  refreshActor(updated: StaffAccount): void {
    if (state.staff?.id !== updated.id) return;
    if (!updated.isActive) void Session.signOut('Your account was deactivated.');
    else set({ staff: updated });
  },

  /** Shows the ended-session notice once. */
  takeEndedReason(): string | null {
    const reason = state.endedReason;
    if (reason) set({ endedReason: null });
    return reason;
  },
};

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useSession(): SessionState {
  return useSyncExternalStore(subscribe, getSession, getSession);
}

/** The signed-in staff member and their permission check, re-rendering on change. */
export function useAccess() {
  const s = useSession();
  const valid = validSession(s);
  return {
    actor: valid ? s.staff : null,
    can: (permission: Permission) => valid && Staff.can(s.staff!, permission),
  };
}
