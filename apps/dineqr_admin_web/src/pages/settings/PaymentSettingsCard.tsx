import { Check, Info, RefreshCw, Trash2, Upload } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { QrCode } from '@/components/domain/Domain';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { Spinner } from '@/components/ui/Feedback';
import { SwitchRow, TextField } from '@/components/ui/Form';
import { toast } from '@/components/ui/Toast';
import { imageUrl } from '@/config/env';
import { automaticUnavailableMessage, Upi, verificationModeLabel, type UpiSettings, type UpiVerificationMode } from '@/core/upi';
import { savePaymentSettings, uploadUpiQr } from '@/state/actions';
import { usePaymentSettings } from '@/state/data';
import { errorMessage, useAction } from '@/state/run';

const empty: UpiSettings = { enabled: false, upiId: '', payeeName: '', qrImageUrl: '', verificationMode: 'manual' };

/**
 * UPI payments straight into the restaurant's own account (PaymentSettingsCard).
 * Saved on its own: it changes where guests' money goes.
 */
export function PaymentSettingsCard() {
  const query = usePaymentSettings();
  const saved = query.data?.upi ?? empty;
  const automaticAvailable = query.data?.automaticVerificationAvailable ?? false;
  const [base, setBase] = useState<UpiSettings>(saved);
  const [draft, setDraft] = useState<UpiSettings>(saved);
  const [submitted, setSubmitted] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [qrError, setQrError] = useState<string | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const { pending, run } = useAction();

  const typed: UpiSettings = { ...draft, upiId: Upi.normalizeId(draft.upiId), payeeName: draft.payeeName.trim() };
  const dirty = !Upi.equal(typed, base);

  // A fresh copy arrived from the server (live update, another device):
  // take it unless the owner is in the middle of an edit.
  useEffect(() => {
    if (!query.data) return;
    const next = query.data.upi;
    setBase(next);
    setDraft((d) => (Upi.equal({ ...d, upiId: Upi.normalizeId(d.upiId), payeeName: d.payeeName.trim() }, base) ? next : d));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query.data]);

  const pickQr = async (files: FileList | null) => {
    const chosen = files?.[0];
    if (!chosen) return;
    setUploading(true);
    setQrError(null);
    try {
      const url = await uploadUpiQr(new Uint8Array(await chosen.arrayBuffer()));
      setDraft((d) => ({ ...d, qrImageUrl: url }));
    } catch (e) {
      const message = errorMessage(e);
      setQrError(message === 'Something went wrong. Please try again.' ? 'The QR image could not be uploaded. Please try again.' : message);
    } finally {
      setUploading(false);
      if (file.current) file.current.value = '';
    }
  };

  const chooseMode = (mode: UpiVerificationMode) => {
    if (mode === 'automatic' && !automaticAvailable) {
      // Not selectable here: the explanation below is already on screen.
      toast(automaticUnavailableMessage, 'info');
      return;
    }
    setDraft((d) => ({ ...d, verificationMode: mode }));
  };

  const save = async () => {
    setSubmitted(true);
    const ok = await run(() => savePaymentSettings(typed, automaticAvailable), { success: 'Payment settings saved' });
    if (ok) setSubmitted(false);
  };

  const busy = pending || uploading;
  // Problems show once a save was tried, and at once when what is saved cannot take payments.
  const problems = submitted || Upi.validate(base) != null ? Upi.problems(typed) : null;
  const status = dirty ? (['Unsaved changes', 'warning'] as const) : Upi.isReady(base) ? (['Active', 'success'] as const) : (['Off', 'muted'] as const);

  return (
    <SectionCard title="Payment Settings" subtitle="Take UPI payments straight into your own account." trailing={query.data && <Badge tone={status[1]}>{status[0]}</Badge>}>
      {query.isPending ? (
        <div className="grid place-items-center py-8">
          <Spinner size={26} />
        </div>
      ) : query.isError ? (
        <div className="flex flex-col items-start gap-2">
          <p role="alert" className="text-[13px] text-danger">
            {errorMessage(query.error) === 'Something went wrong. Please try again.' ? 'The payment settings could not be loaded.' : errorMessage(query.error)}
          </p>
          <Button size="sm" icon={RefreshCw} onClick={() => void query.refetch()}>
            Try again
          </Button>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          <SwitchRow title="Enable UPI Payments" description="Guests can pay their bill by UPI, straight to your account." checked={draft.enabled} disabled={busy} onChange={(on) => setDraft((d) => ({ ...d, enabled: on }))} />
          <div className="grid gap-4 sm:grid-cols-2">
            <TextField
              label="Restaurant UPI ID"
              placeholder="name@bank"
              autoComplete="off"
              spellCheck={false}
              maxLength={100}
              disabled={busy}
              value={draft.upiId}
              onChange={(e) => setDraft((d) => ({ ...d, upiId: e.target.value.replace(/\s/g, '') }))}
              hint="The account guests pay. Check it carefully."
              error={problems?.upiId}
            />
            <TextField
              label="Merchant / Account Name"
              maxLength={60}
              disabled={busy}
              value={draft.payeeName}
              onChange={(e) => setDraft((d) => ({ ...d, payeeName: e.target.value }))}
              hint="Shown to guests in their UPI app when they pay."
              error={problems?.payeeName}
            />
          </div>
          {Upi.isValidId(typed.upiId) && (
            <div className="flex flex-col gap-4 rounded-2xl border border-info/25 bg-info/8 p-4 sm:flex-row">
              <div className="min-w-0 flex-1">
                <p className="text-[14px] font-semibold text-ink">Check this UPI ID</p>
                <p className="mt-1 text-[12.5px] leading-relaxed text-muted">
                  Scan this with your own UPI app before guests pay. It should show your bank account name; you don't need to pay. If it says the UPI ID has no account or can't be found, guests can't pay it either.
                </p>
                <p className="mt-2 text-[12.5px] leading-relaxed text-muted">
                  Google Pay and PhonePe refuse a payment that another app fills in for your own UPI ID (Google Pay shows "You've exceeded the bank limit"; nothing is debited). So guests' UPI app opens with this ID copied and they enter the amount, or they scan the QR on their bill, and staff confirm each payment. For UPI apps that open with the amount filled in and payments confirmed automatically, like big apps, connect a payment gateway (Cashfree).
                </p>
              </div>
              <QrCode payload={Upi.checkUri(typed)} size={160} label={`QR code to check the UPI ID ${typed.upiId}`} />
            </div>
          )}

          <div>
            <p className="text-[14px] font-semibold text-ink">UPI QR code</p>
            <p className="text-[12.5px] text-muted">Optional. Your own merchant QR, shown to guests as a backup. The QR guests scan to pay is made from your UPI ID with the exact amount.</p>
            <div className="mt-3 flex flex-wrap items-end gap-4">
              <div className="relative grid h-36 w-36 place-items-center overflow-hidden rounded-2xl border border-line bg-panel-2">
                {draft.qrImageUrl ? <img src={imageUrl(draft.qrImageUrl)} alt="Your UPI QR image" className="h-full w-full bg-white object-contain" /> : <span className="px-3 text-center text-[12px] text-faint">No QR image</span>}
                {uploading && (
                  <span className="absolute inset-0 grid place-items-center bg-black/40">
                    <Spinner size={24} className="text-white" />
                  </span>
                )}
              </div>
              <div className="flex flex-wrap gap-2">
                <input ref={file} type="file" accept="image/*" className="sr-only" tabIndex={-1} onChange={(e) => void pickQr(e.target.files)} aria-hidden />
                <Button size="sm" icon={Upload} disabled={busy} onClick={() => file.current?.click()}>
                  {draft.qrImageUrl ? 'Replace' : 'Upload QR image'}
                </Button>
                {draft.qrImageUrl && (
                  <Button size="sm" variant="ghost" icon={Trash2} disabled={busy} onClick={() => (setQrError(null), setDraft((d) => ({ ...d, qrImageUrl: '' })))}>
                    Remove
                  </Button>
                )}
              </div>
            </div>
            {draft.qrImageUrl !== base.qrImageUrl && <p className="mt-2 text-[12.5px] text-info">{draft.qrImageUrl ? 'Save to start showing this image to guests.' : 'Save to stop showing the image to guests.'}</p>}
            {qrError && (
              <p role="alert" className="mt-2 text-[12.5px] text-danger">
                {qrError}
              </p>
            )}
          </div>

          <div>
            <p className="text-[14px] font-semibold text-ink">Payment verification</p>
            <p className="text-[12.5px] text-muted">How a UPI payment is confirmed before the bill shows as paid.</p>
            <div className="mt-3 grid gap-2 sm:grid-cols-2">
              {(['manual', 'automatic'] as UpiVerificationMode[]).map((mode) => {
                const selected = draft.verificationMode === mode;
                const notSetUp = mode === 'automatic' && !automaticAvailable;
                return (
                  <button
                    key={mode}
                    type="button"
                    role="radio"
                    aria-checked={selected}
                    disabled={busy}
                    onClick={() => chooseMode(mode)}
                    className={cn('flex items-start gap-3 rounded-2xl border p-4 text-left transition-colors', selected ? 'border-brand-text/60 bg-brand/8' : 'border-line hover:border-line-strong', notSetUp && 'opacity-60')}
                  >
                    <span className={cn('mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full border-2', selected ? 'border-brand-text bg-brand-text' : 'border-line-strong')}>{selected && <Check size={12} strokeWidth={3} className="text-white" aria-hidden />}</span>
                    <span>
                      <span className="flex flex-wrap items-center gap-2 text-[13.5px] font-semibold text-ink">
                        {verificationModeLabel[mode]}
                        {notSetUp && <Badge tone="muted">Not set up</Badge>}
                      </span>
                      <span className="mt-0.5 block text-[12px] text-muted">
                        {mode === 'manual' ? 'A cashier checks that the money arrived in your bank or UPI app, then confirms each payment.' : 'Payments are confirmed by a connected bank or payment provider.'}
                      </span>
                    </span>
                  </button>
                );
              })}
            </div>
            {!automaticAvailable && <p className={cn('mt-2 text-[12px]', draft.verificationMode === 'automatic' ? 'text-danger' : 'text-faint')}>{automaticUnavailableMessage}</p>}
          </div>

          <p className="flex items-start gap-2 rounded-xl bg-info/8 px-3.5 py-3 text-[12.5px] leading-relaxed text-info">
            <Info size={16} className="mt-0.5 shrink-0" aria-hidden />
            Guests pay in their own UPI app and the money goes straight to this account; DineQR never holds it. A bill shows as paid only after a cashier confirms the payment. UPI PINs, card numbers and bank passwords are never asked for or stored.
          </p>
          <Button variant="primary" icon={Check} loading={pending} disabled={uploading} onClick={() => void save()} className="self-start">
            Save payment settings
          </Button>
        </div>
      )}
    </SectionCard>
  );
}
