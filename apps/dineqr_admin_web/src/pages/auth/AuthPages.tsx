import { zodResolver } from '@hookform/resolvers/zod';
import { AtSign, ChartColumn, ChefHat, CloudOff, Eye, EyeOff, FileText, LockKeyhole, LogIn, QrCode, ReceiptText, RefreshCw, ShieldCheck } from 'lucide-react';
import { motion, useReducedMotion } from 'motion/react';
import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { AuthException } from '@/api/auth';
import { DineQrMark, Lockup } from '@/components/brand/Brand';
import { Button } from '@/components/ui/Button';
import { Dialog } from '@/components/ui/Dialog';
import { TextField } from '@/components/ui/Form';
import { Notice } from '@/components/ui/Feedback';
import type { ConfigIssue } from '@/config/env';
import { Session, useSession } from '@/state/session';

/** The deep burgundy stage behind the splash and sign-in. */
function Stage({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative min-h-dvh overflow-hidden bg-[#0d0608] text-[#f6ecec]">
      <div className="pointer-events-none absolute inset-0" aria-hidden>
        <div className="drift absolute -left-40 -top-40 h-[34rem] w-[34rem] rounded-full bg-[#b5121b] opacity-30 blur-[120px]" />
        <div className="drift absolute -bottom-48 right-[-10rem] h-[38rem] w-[38rem] rounded-full bg-[#ff6a00] opacity-[0.16] blur-[140px]" style={{ animationDelay: '-9s' }} />
        <div
          className="absolute inset-0 opacity-[0.5]"
          style={{
            backgroundImage: 'linear-gradient(rgba(255,228,230,0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(255,228,230,0.04) 1px, transparent 1px)',
            backgroundSize: '48px 48px',
            maskImage: 'radial-gradient(ellipse at center, #000 30%, transparent 75%)',
          }}
        />
      </div>
      <div className="relative">{children}</div>
    </div>
  );
}

/**
 * The opening: the saved staff session (if any) is restored behind it. If the
 * server cannot be reached, it offers a retry or the sign-in screen, never an
 * endless wait (AdminSplashScreen).
 */
export function SplashScreen() {
  const { phase, problem } = useSession();
  const reduced = useReducedMotion();
  const [waiting, setWaiting] = useState(false);
  const [slow, setSlow] = useState(false);
  useEffect(() => {
    if (phase !== 'restoring') return;
    setWaiting(false);
    setSlow(false);
    const a = setTimeout(() => setWaiting(true), 1600);
    const b = setTimeout(() => setSlow(true), 8000);
    return () => {
      clearTimeout(a);
      clearTimeout(b);
    };
  }, [phase]);
  return (
    <Stage>
      <div className="flex min-h-dvh flex-col items-center justify-center px-6">
        <motion.div initial={reduced ? false : { opacity: 0, scale: 0.86, rotate: -6 }} animate={{ opacity: 1, scale: 1, rotate: 0 }} transition={{ type: 'spring', stiffness: 120, damping: 14 }} className="relative">
          <div className="absolute inset-0 -z-10 scale-150 rounded-full bg-[#d62828]/25 blur-3xl" aria-hidden />
          <DineQrMark size={132} tone="inverted" label="DineQR Admin" />
        </motion.div>
        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.25, duration: 0.5 }} className="mt-7 text-center">
          <p className="text-[30px] font-bold tracking-tight">
            DineQR <span className="bg-[linear-gradient(100deg,#ff7a7f,#ffb25c)] bg-clip-text text-transparent">Admin</span>
          </p>
          <p className="mt-1 text-[13px] tracking-[0.04em] text-[#c4aeb1]">Restaurant management</p>
        </motion.div>
        <div className="mt-12 min-h-[150px] w-full max-w-md">
          {phase === 'restoreFailed' && problem ? (
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} role="alert" className="rounded-3xl border border-white/12 bg-white/[0.06] p-6 text-center backdrop-blur-xl">
              <CloudOff size={28} className="mx-auto text-[#ff8a00]" aria-hidden />
              <p className="mt-2 text-[16px] font-semibold">{problem.title}</p>
              <p className="mt-1 text-[13px] leading-relaxed text-[#c4aeb1]">{problem.message}</p>
              <Button variant="primary" icon={RefreshCw} block className="mt-5" onClick={() => void Session.restore()}>
                Try again
              </Button>
              <button type="button" onClick={() => Session.skipRestore()} className="mt-2 w-full rounded-xl py-2.5 text-[13px] font-semibold text-[#f6ecec]/85 hover:bg-white/5">
                Go to sign-in
              </button>
            </motion.div>
          ) : (
            (waiting || slow) && (
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex flex-col items-center gap-3" aria-live="polite">
                <div className="h-1 w-40 overflow-hidden rounded-full bg-white/10">
                  <motion.div className="h-full w-1/3 rounded-full bg-[linear-gradient(90deg,#d62828,#ff8a00)]" animate={reduced ? undefined : { x: ['-100%', '300%'] }} transition={{ duration: 1.4, repeat: Infinity, ease: 'easeInOut' }} />
                </div>
                <p className="text-center text-[13px] text-[#c4aeb1]">{slow ? 'The DineQR server is starting up. This can take up to a minute.' : 'Restoring your session…'}</p>
              </motion.div>
            )
          )}
        </div>
      </div>
    </Stage>
  );
}

const loginSchema = z.object({
  email: z
    .string()
    .trim()
    .min(1, 'Enter your email.')
    .refine((v) => v.includes('@') && v.includes('.'), 'Enter a valid email address.'),
  password: z.string().min(1, 'Enter your password.'),
});
type LoginForm = z.infer<typeof loginSchema>;

const capabilities = [
  { icon: ReceiptText, label: 'Live orders' },
  { icon: ChefHat, label: 'Kitchen display' },
  { icon: FileText, label: 'Bills & payments' },
  { icon: ChartColumn, label: 'Reports' },
  { icon: QrCode, label: 'Table QR codes' },
];

/** Staff sign-in against the DineQR server (AdminLoginScreen). */
export function LoginScreen() {
  const { busy } = useSession();
  const [notice] = useState(() => Session.takeEndedReason());
  const [error, setError] = useState<string | null>(null);
  const [shake, setShake] = useState(0);
  const [obscure, setObscure] = useState(true);
  const [forgot, setForgot] = useState(false);
  const { register, handleSubmit, setValue, setFocus, formState } = useForm<LoginForm>({ resolver: zodResolver(loginSchema), defaultValues: { email: '', password: '' } });

  const submit = handleSubmit(async ({ email, password }) => {
    setError(null);
    try {
      await Session.signIn(email, password);
    } catch (e) {
      setError(e instanceof AuthException ? e.message : 'Sign-in is unavailable right now. Please try again.');
      setShake((s) => s + 1);
      setValue('password', '');
      setFocus('password');
    }
  });

  return (
    <Stage>
      <div className="mx-auto grid min-h-dvh max-w-6xl items-center gap-10 px-5 py-10 lg:grid-cols-[1.1fr_1fr] lg:px-10">
        <motion.section initial={{ opacity: 0, x: -16 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }} className="hidden lg:block">
          <Lockup height={52} trim onDark />
          <p className="mt-3 text-[14px] text-[#c4aeb1]">Restaurant management</p>
          <h1 className="mt-10 max-w-lg text-[44px] font-bold leading-[1.08] tracking-tight">
            Orders, kitchen, bills and reports{' '}
            <span className="bg-[linear-gradient(100deg,#ff7a7f,#ff8a00)] bg-clip-text text-transparent">for your restaurant team.</span>
          </h1>
          <ul className="mt-9 flex max-w-lg flex-wrap gap-2.5">
            {capabilities.map((c, i) => (
              <motion.li
                key={c.label}
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.25 + i * 0.06 }}
                className="flex items-center gap-2 rounded-full border border-white/12 bg-white/[0.05] px-3.5 py-2 text-[13px] backdrop-blur"
              >
                <c.icon size={15} className="text-[#ff8a00]" aria-hidden />
                {c.label}
              </motion.li>
            ))}
          </ul>
        </motion.section>

        <motion.section
          key={shake}
          initial={{ opacity: 0, y: 16 }}
          animate={shake ? { opacity: 1, y: 0, x: [0, -10, 9, -6, 4, 0] } : { opacity: 1, y: 0 }}
          transition={{ duration: shake ? 0.4 : 0.5, ease: [0.22, 1, 0.36, 1] }}
          className="mx-auto w-full max-w-[440px]"
        >
          <div className="mb-8 flex flex-col items-center text-center lg:hidden">
            <DineQrMark size={86} tone="inverted" />
            <p className="mt-4 text-[24px] font-bold">DineQR Admin</p>
            <p className="text-[13px] text-[#c4aeb1]">Restaurant management</p>
          </div>
          {/* The card is always light-on-dark glass, whatever the app theme. */}
          <div data-theme="dark" className="rounded-[28px] border border-white/12 bg-[#170c10]/85 p-7 shadow-[0_40px_120px_-40px_rgba(0,0,0,0.9)] backdrop-blur-2xl sm:p-9">
            <h2 className="text-[22px] font-bold text-ink">Staff sign in</h2>
            <p className="mt-1 text-[13px] text-muted">Use the account your restaurant gave you.</p>
            <form className="mt-6 flex flex-col gap-4" onSubmit={submit} noValidate>
              {notice && <Notice tone="info">{notice}</Notice>}
              {error && (
                <Notice tone="danger" className="items-center">
                  <span role="alert">{error}</span>
                </Notice>
              )}
              <TextField
                label="Email"
                type="email"
                autoComplete="username"
                autoCapitalize="none"
                spellCheck={false}
                disabled={busy}
                prefix={<AtSign size={15} />}
                error={formState.errors.email?.message}
                {...register('email')}
              />
              <div className="relative">
                <TextField
                  label="Password"
                  type={obscure ? 'password' : 'text'}
                  autoComplete="current-password"
                  disabled={busy}
                  prefix={<LockKeyhole size={15} />}
                  className="pr-12"
                  error={formState.errors.password?.message}
                  {...register('password')}
                />
                <button
                  type="button"
                  onClick={() => setObscure((o) => !o)}
                  aria-label={obscure ? 'Show password' : 'Hide password'}
                  title={obscure ? 'Show password' : 'Hide password'}
                  className="absolute right-1.5 top-[30px] grid h-9 w-9 place-items-center rounded-lg text-muted hover:text-ink"
                >
                  {obscure ? <Eye size={17} aria-hidden /> : <EyeOff size={17} aria-hidden />}
                </button>
              </div>
              <div className="-mt-1 flex justify-end">
                <button type="button" disabled={busy} onClick={() => setForgot(true)} className="text-[12.5px] font-semibold text-brand-text hover:underline">
                  Forgot password?
                </button>
              </div>
              <Button type="submit" variant="primary" size="lg" icon={LogIn} loading={busy} block>
                Sign in
              </Button>
              <p className="flex items-center justify-center gap-1.5 text-center text-[11.5px] text-faint">
                <ShieldCheck size={13} aria-hidden /> Sessions end after 8 hours. Repeated failures lock sign-in for a minute.
              </p>
            </form>
          </div>
        </motion.section>
      </div>
      <Dialog
        open={forgot}
        onClose={() => setForgot(false)}
        title="Forgot your password?"
        size="sm"
        footer={
          <Button variant="primary" onClick={() => setForgot(false)}>
            Got it
          </Button>
        }
      >
        <p className="pb-2 text-[13.5px] leading-relaxed text-muted">Ask the restaurant owner to reset it from Staff → Reset password. DineQR does not send password-reset emails.</p>
      </Dialog>
    </Stage>
  );
}

/** A build whose server address cannot work (AdminNotConfiguredApp). */
export function NotConfiguredScreen({ issue }: { issue: ConfigIssue | null }) {
  return (
    <Stage>
      <div className="flex min-h-dvh flex-col items-center justify-center px-6 text-center">
        <DineQrMark size={110} tone="inverted" />
        <p className="mt-6 text-[18px] font-semibold">{issue?.title ?? 'DineQR Admin is not connected'}</p>
        <p className="mt-2 max-w-md text-[13.5px] leading-relaxed text-[#c4aeb1]">{issue?.detail ?? 'This build has no server address. Set VITE_API_URL to the DineQR API and build again.'}</p>
      </div>
    </Stage>
  );
}
