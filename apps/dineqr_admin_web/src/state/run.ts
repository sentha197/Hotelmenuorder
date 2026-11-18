import { useCallback, useState } from 'react';
import { AuthException } from '@/api/auth';
import { ApiException } from '@/api/client';
import { CheckoutError } from '@/api/dineqr';
import { PaymentError, PermissionDeniedError, SessionExpiredError, ValidationError } from '@/core/access';
import { toast } from '@/components/ui/Toast';

/** The message staff see for a failure (runAdminAction's mapping). */
export function errorMessage(error: unknown): string {
  if (error instanceof ApiException) return error.isUnauthorized ? new SessionExpiredError().message : error.message;
  if (
    error instanceof ValidationError ||
    error instanceof PaymentError ||
    error instanceof CheckoutError ||
    error instanceof PermissionDeniedError ||
    error instanceof SessionExpiredError ||
    error instanceof AuthException
  ) {
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

/**
 * Runs an admin action and turns failures into a toast. Returns true when
 * [action] completed (runAdminAction).
 */
export async function runAction(action: () => Promise<unknown>, options: { success?: string; successAction?: { label: string; onClick: () => void } } = {}): Promise<boolean> {
  try {
    await action();
    if (options.success) toast(options.success, 'success', options.successAction);
    return true;
  } catch (error) {
    toast(errorMessage(error), 'error');
    return false;
  }
}

/** [runAction] with a pending flag for the button that started it. */
export function useAction() {
  const [pending, setPending] = useState(false);
  const run = useCallback(async (action: () => Promise<unknown>, options?: Parameters<typeof runAction>[1]) => {
    setPending(true);
    try {
      return await runAction(action, options);
    } finally {
      setPending(false);
    }
  }, []);
  return { pending, run };
}
