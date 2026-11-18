type Json = Record<string, unknown>;

export type UpiVerificationMode = 'manual' | 'automatic';
export const verificationModeLabel: Record<UpiVerificationMode, string> = {
  manual: 'Manual verification',
  automatic: 'Automatic verification',
};

/**
 * The restaurant's UPI details for payments straight to its own account. Only
 * public payee details: never a PIN, a card or any bank credential. The
 * server checks the same rules; they are repeated so mistakes show in the form.
 */
export interface UpiSettings {
  enabled: boolean;
  upiId: string;
  payeeName: string;
  qrImageUrl: string;
  verificationMode: UpiVerificationMode;
}

export const upiFromJson = (json: Json): UpiSettings => ({
  enabled: (json.enabled as boolean | undefined) ?? false,
  upiId: (json.upiId as string | undefined) ?? '',
  payeeName: (json.payeeName as string | undefined) ?? '',
  qrImageUrl: (json.qrImage as string | undefined) ?? '',
  verificationMode: json.verificationMode === 'automatic' ? 'automatic' : 'manual',
});

export const upiToJson = (s: UpiSettings): Json => ({
  enabled: s.enabled,
  upiId: s.upiId,
  payeeName: s.payeeName,
  qrImage: s.qrImageUrl,
  verificationMode: s.verificationMode,
});

export interface PaymentSettingsSnapshot {
  upi: UpiSettings;
  /** True only when a bank or payment-provider integration is connected. */
  automaticVerificationAvailable: boolean;
}

export const paymentSettingsFromJson = (json: Json): PaymentSettingsSnapshot => ({
  upi: upiFromJson(json),
  automaticVerificationAvailable: (json.automaticVerificationAvailable as boolean | undefined) ?? false,
});

const ID_PATTERN = /^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9]{1,31}$/;
// eslint-disable-next-line no-control-regex
const BAD_NAME_CHARACTER = /[<>\u0000-\u001F\u007F-\u009F]/;
const GOOGLE_PAY_HANDLES = ['okaxis', 'okhdfcbank', 'okicici', 'oksbi'];

/** One character replaced, added or left out, or two neighbours swapped. */
function oneTypoApart(a: string, b: string): boolean {
  if (a === b || Math.abs(a.length - b.length) > 1) return false;
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  if (a.length !== b.length) return a.length > b.length ? a.slice(i + 1) === b.slice(i) : a.slice(i) === b.slice(i + 1);
  return a.slice(i + 1) === b.slice(i + 1) || (i + 1 < a.length && a[i] === b[i + 1] && a[i + 1] === b[i] && a.slice(i + 2) === b.slice(i + 2));
}

export const Upi = {
  /** A UPI ID as it is stored: trimmed and lower case. */
  normalizeId: (id: string) => id.trim().toLowerCase(),
  /** Why [id] (normalised, not empty) cannot take payments, or null. */
  idProblem(id: string): string | null {
    if (!ID_PATTERN.test(id)) return 'Enter a valid UPI ID, like name@bank.';
    const handle = id.slice(id.indexOf('@') + 1);
    if (GOOGLE_PAY_HANDLES.includes(handle)) return null;
    const meant = GOOGLE_PAY_HANDLES.find((h) => oneTypoApart(handle, h));
    return meant ? `@${handle} is not a Google Pay UPI ID. Did you mean @${meant}? Copy the UPI ID from your UPI app.` : null;
  },
  isValidId: (id: string) => Upi.idProblem(id) == null,
  isValidName: (name: string) => name.length >= 2 && name.length <= 60 && !BAD_NAME_CHARACTER.test(name),
  /** Guests can be offered UPI: switched on and fully set up. */
  isReady: (s: UpiSettings) => s.enabled && Upi.isValidId(Upi.normalizeId(s.upiId)) && Upi.isValidName(s.payeeName.trim()),
  /** What is wrong with each field, for showing next to it. */
  problems(s: UpiSettings): { upiId: string | null; payeeName: string | null } {
    const id = Upi.normalizeId(s.upiId);
    const name = s.payeeName.trim();
    return {
      upiId: id ? Upi.idProblem(id) : s.enabled ? "Enter the restaurant's UPI ID to switch UPI payments on." : null,
      payeeName: name ? (Upi.isValidName(name) ? null : 'The name must be 2 to 60 characters.') : s.enabled ? 'Enter the name guests will see when they pay.' : null,
    };
  },
  validate(s: UpiSettings): string | null {
    const p = Upi.problems(s);
    return p.upiId ?? p.payeeName;
  },
  equal: (a: UpiSettings, b: UpiSettings) =>
    a.enabled === b.enabled && a.upiId === b.upiId && a.payeeName === b.payeeName && a.qrImageUrl === b.qrImageUrl && a.verificationMode === b.verificationMode,
  /** The note a payment carries, e.g. `Bill DQ-2026-00012 PAY000001`. */
  noteFor: (billNumber: string, paymentId: string) => `Bill ${billNumber} ${paymentId}`,
  /**
   * A link with no amount for the owner to scan with their own UPI app: it
   * shows the bank account name the ID belongs to. Nothing is paid unless they
   * enter an amount and their PIN.
   */
  checkUri(s: UpiSettings): string {
    const encode = (v: string) => encodeURIComponent(v).replaceAll('%40', '@');
    return `upi://pay?pa=${encode(Upi.normalizeId(s.upiId))}&pn=${encode(s.payeeName.trim())}&cu=INR`;
  },
};

export const automaticUnavailableMessage =
  'Automatic verification needs a bank or payment provider connected to this server, and none is set up. Choose manual verification so a cashier confirms each payment.';

/** The bank's UPI transaction ID (UTR) a cashier records when confirming a payment. */
export const UpiReference = {
  rule: 'The UPI transaction ID is 6 to 40 letters or digits.',
  normalize: (reference: string) => reference.trim().toUpperCase(),
  isValid: (reference: string) => /^[A-Z0-9][A-Z0-9._/-]{5,39}$/.test(reference),
};
