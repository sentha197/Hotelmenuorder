import { Eye, EyeOff, KeyRound, ShieldCheck, UserCog, UserPlus, Users } from 'lucide-react';
import { motion } from 'motion/react';
import { useState } from 'react';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { Dialog, promptDialog } from '@/components/ui/Dialog';
import { Empty, PageSkeleton } from '@/components/ui/Feedback';
import { Switch, SwitchRow, TextField } from '@/components/ui/Form';
import { ActionMenu } from '@/components/ui/Menu';
import { Page } from '@/components/ui/Page';
import {
  accessGroups,
  accessNotes,
  allPermissions,
  MAX_ROLE_TITLE,
  passwordProblem,
  permissionInfo,
  permissionsOfRole,
  roleFromText,
  roleInfo,
  Staff,
  staffRoles,
  type Permission,
  type StaffAccount,
  type StaffRole,
} from '@/core/access';
import { AppFormat } from '@/core/time';
import { addStaff, changeAccess, changeRole, resetStaffPassword, setStaffActive, sortStaff } from '@/state/actions';
import { useStaff } from '@/state/data';
import { runAction, useAction } from '@/state/run';
import { useAccess } from '@/state/session';

/** Staff accounts, roles and per-person access (StaffScreen). */
export function StaffPage() {
  const { actor } = useAccess();
  const query = useStaff();
  const staff = sortStaff(query.data ?? []);
  const [adding, setAdding] = useState(false);
  const [roleFor, setRoleFor] = useState<StaffAccount | null>(null);
  const [accessFor, setAccessFor] = useState<StaffAccount | null>(null);

  const resetPassword = async (account: StaffAccount) => {
    const password = await promptDialog({ title: `New password for ${account.name}`, label: 'Temporary password (8+ letters and numbers)', confirmLabel: 'Set password', minLength: 8, maxLength: 64, type: 'password' });
    if (password != null) await runAction(() => resetStaffPassword(account, password), { success: 'Password updated. Share it privately.' });
  };

  return (
    <Page
      title="Staff & roles"
      subtitle={`${staff.filter((s) => s.isActive).length} active accounts`}
      actions={
        <Button variant="primary" icon={UserPlus} onClick={() => setAdding(true)}>
          Add staff
        </Button>
      }
    >
      <p className="max-w-3xl text-[12.5px] leading-relaxed text-muted">Roles decide what each person can see and change. The DineQR server enforces them on every request; the app only hides what a role cannot use.</p>
      {query.isPending ? (
        <PageSkeleton rows={4} />
      ) : staff.length === 0 ? (
        <Empty icon={Users} title="No staff accounts" />
      ) : (
        <div className="grid gap-3 lg:grid-cols-2">
          {staff.map((account, i) => {
            const isMe = account.id === actor?.id;
            return (
              <motion.div key={account.id} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: Math.min(i, 16) * 0.03 }} className={cn('panel flex items-center gap-3 p-4', !account.isActive && 'opacity-65')}>
                <span className={cn('grid h-11 w-11 shrink-0 place-items-center rounded-full text-[17px] font-bold', account.isActive ? 'brand-fill' : 'bg-panel-3 text-muted')} aria-hidden>
                  {account.name ? account.name[0]!.toUpperCase() : '?'}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="truncate text-[14.5px] font-semibold text-ink">{isMe ? `${account.name} (you)` : account.name}</span>
                    <Badge tone="ember">{Staff.roleLabel(account)}</Badge>
                    {Staff.hasCustomAccess(account) && <Badge tone="brand">Custom access</Badge>}
                  </div>
                  <p className="truncate text-[12px] text-muted">{account.email}</p>
                  <p className="text-[11.5px] text-faint">{account.lastLoginAt ? `Last sign-in ${AppFormat.dateTime(account.lastLoginAt)}` : 'Never signed in'}</p>
                </div>
                <Switch
                  checked={account.isActive}
                  tone="success"
                  disabled={isMe}
                  label={`${account.name} active`}
                  onChange={(on) => void runAction(() => setStaffActive(account, on), { success: on ? `${account.name} activated` : `${account.name} deactivated` })}
                />
                <ActionMenu
                  label="Staff actions"
                  actions={[
                    { label: 'Change role', icon: UserCog, onSelect: () => setRoleFor(account) },
                    { label: 'Change access', icon: ShieldCheck, disabled: account.role === 'owner', onSelect: () => setAccessFor(account) },
                    { label: 'Reset password', icon: KeyRound, onSelect: () => void resetPassword(account) },
                  ]}
                />
              </motion.div>
            );
          })}
        </div>
      )}
      <RoleGuide />
      <AddStaffDialog
        open={adding}
        onClose={() => setAdding(false)}
        onCustomCreated={(account) => {
          // A role with its own name starts with no access, so ask for it now.
          setAccessFor(account);
        }}
      />
      <RoleDialog account={roleFor} onClose={() => setRoleFor(null)} onCustomFromOther={(a) => setAccessFor(a)} staff={staff} />
      <AccessDialog account={accessFor} onClose={() => setAccessFor(null)} />
    </Page>
  );
}

/** What each built-in role can do (_RoleGuide). */
function RoleGuide() {
  const [open, setOpen] = useState<StaffRole | null>(null);
  return (
    <SectionCard title="What each role can do">
      <div className="divide-y divide-line">
        {staffRoles
          .filter((r) => r !== 'custom')
          .map((role) => {
            const perms = allPermissions.filter((p) => permissionsOfRole(role).has(p));
            const expanded = open === role;
            return (
              <div key={role}>
                <button type="button" aria-expanded={expanded} onClick={() => setOpen(expanded ? null : role)} className="flex w-full items-center gap-3 py-3 text-left">
                  <div className="min-w-0 flex-1">
                    <p className="text-[14px] font-semibold text-ink">{roleInfo[role].label}</p>
                    <p className="text-[12.5px] text-muted">{roleInfo[role].description}</p>
                  </div>
                  <span className="text-[12px] text-faint">{perms.length} permissions</span>
                </button>
                {expanded && (
                  <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} className="flex flex-wrap gap-1.5 overflow-hidden pb-3">
                    {perms.map((p) => (
                      <span key={p} className="rounded-full border border-line bg-panel-2 px-2.5 py-1 text-[11.5px] text-muted">
                        {permissionInfo[p].label}
                      </span>
                    ))}
                  </motion.div>
                )}
              </div>
            );
          })}
      </div>
    </SectionCard>
  );
}

function AddStaffDialog({ open, onClose, onCustomCreated }: { open: boolean; onClose: () => void; onCustomCreated: (account: StaffAccount) => void }) {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState('');
  const [password, setPassword] = useState('');
  const [obscure, setObscure] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [wasOpen, setWasOpen] = useState(false);
  const { pending, run } = useAction();
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) {
      setName('');
      setEmail('');
      setRole('');
      setPassword('');
      setError(null);
    }
  }
  const submit = async () => {
    const weak = passwordProblem(password);
    const parsed = roleFromText(role);
    if (!name.trim()) return setError('Enter a name.');
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) return setError('Enter a valid email address.');
    if (!parsed) return setError(`Role name must be 2 to ${MAX_ROLE_TITLE} characters.`);
    if (weak) return setError(weak);
    setError(null);
    let created: StaffAccount | null = null;
    const custom = parsed.role === 'custom';
    const ok = await run(
      async () => {
        created = await addStaff({ name, email, role: parsed.role, roleTitle: parsed.title, password });
      },
      { success: custom ? `${name.trim()} added. Now choose what they can access.` : `${name.trim()} added. Share the temporary password privately.` },
    );
    if (!ok) return;
    onClose();
    if (custom && created) onCustomCreated(created);
  };
  const standard = staffRoles.filter((r) => r !== 'custom').map((r) => roleInfo[r].label);
  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Add staff"
      icon={UserPlus}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void submit()}>
            Add
          </Button>
        </>
      }
    >
      <form className="flex flex-col gap-4 pb-2" onSubmit={(e) => (e.preventDefault(), void submit())} autoComplete="off">
        <TextField label="Full name" maxLength={40} value={name} onChange={(e) => setName(e.target.value)} />
        <TextField label="Email" type="email" autoComplete="off" value={email} onChange={(e) => setEmail(e.target.value)} />
        <div>
          <TextField label="Role" list="dineqr-roles" maxLength={MAX_ROLE_TITLE} value={role} onChange={(e) => setRole(e.target.value)} hint={`Type any name, e.g. Officer; you choose its access next. Standard roles: ${standard.join(', ')}.`} />
          <datalist id="dineqr-roles">
            {standard.map((label) => (
              <option key={label} value={label} />
            ))}
          </datalist>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {standard.map((label) => (
              <button key={label} type="button" onClick={() => setRole(label)} className={cn('rounded-full border px-2.5 py-1 text-[11.5px] font-medium', role === label ? 'border-transparent brand-fill' : 'border-line bg-panel-2 text-muted hover:text-ink')}>
                {label}
              </button>
            ))}
          </div>
        </div>
        <div className="relative">
          <TextField label="Temporary password" type={obscure ? 'password' : 'text'} autoComplete="new-password" className="pr-12" hint="At least 8 characters with letters and numbers" value={password} onChange={(e) => setPassword(e.target.value)} />
          <button type="button" aria-label={obscure ? 'Show password' : 'Hide password'} onClick={() => setObscure((o) => !o)} className="absolute right-1.5 top-[30px] grid h-9 w-9 place-items-center rounded-lg text-muted hover:text-ink">
            {obscure ? <Eye size={17} aria-hidden /> : <EyeOff size={17} aria-hidden />}
          </button>
        </div>
        {error && (
          <p role="alert" className="text-[12.5px] text-danger">
            {error}
          </p>
        )}
      </form>
    </Dialog>
  );
}

/** Picks a new role; "Another name…" names a custom role (_changeRole). */
function RoleDialog({ account, onClose, onCustomFromOther, staff }: { account: StaffAccount | null; onClose: () => void; onCustomFromOther: (a: StaffAccount) => void; staff: StaffAccount[] }) {
  const choose = async (role: StaffRole) => {
    if (!account) return;
    onClose();
    let target = role;
    let title: string | null = null;
    if (role === 'custom') {
      const typed = await promptDialog({ title: `Role name for ${account.name}`, label: 'Role name, e.g. Officer', confirmLabel: 'Save', minLength: 2, maxLength: MAX_ROLE_TITLE });
      // Typing a standard role's name picks that role.
      const named = typed == null ? null : roleFromText(typed);
      if (!named) return;
      target = named.role;
      title = named.title;
    }
    const changed = await runAction(() => changeRole(account, target, title), { success: `${account.name} is now ${title ?? roleInfo[target].label}` });
    // A custom role begun from another role starts with no access.
    if (changed && target === 'custom' && account.role !== 'custom') {
      const updated = staff.find((s) => s.id === account.id);
      onCustomFromOther(updated ? { ...updated, role: 'custom', roleTitle: title, customPermissions: null } : account);
    }
  };
  return (
    <Dialog open={account != null} onClose={onClose} title={account ? `Role for ${account.name}` : ''} icon={UserCog}>
      <div className="flex flex-col gap-1 pb-3">
        {staffRoles.map((role) => {
          const current = account?.role === role;
          return (
            <button key={role} type="button" onClick={() => void choose(role)} className={cn('flex items-start gap-3 rounded-xl px-3 py-2.5 text-left', current ? 'bg-brand/10' : 'hover:bg-panel-2')}>
              <span className={cn('mt-1 h-4 w-4 shrink-0 rounded-full border-2', current ? 'border-brand-text bg-brand-text shadow-[inset_0_0_0_3px_var(--panel-solid)]' : 'border-line-strong')} aria-hidden />
              <span>
                <span className="block text-[13.5px] font-semibold text-ink">{role === 'custom' ? (account?.role === 'custom' ? `${Staff.roleLabel(account)} (rename)` : 'Another name…') : roleInfo[role].label}</span>
                <span className="block text-[12px] text-muted">{roleInfo[role].description}</span>
              </span>
            </button>
          );
        })}
      </div>
    </Dialog>
  );
}

/** Lets the owner choose exactly what a person may do (AccessDialog). */
function AccessDialog({ account, onClose }: { account: StaffAccount | null; onClose: () => void }) {
  const [shown, setShown] = useState<StaffAccount | null>(null);
  const [selected, setSelected] = useState<Set<Permission>>(new Set());
  const { pending, run } = useAction();
  if (account && account !== shown) {
    setShown(account);
    setSelected(new Set(Staff.permissions(account)));
  }
  const a = account ?? shown;
  if (!a) return null;
  const role = a.role;
  const dependsOn = (permission: Permission, other: Permission) => {
    for (let need = permissionInfo[permission].requires; need; need = permissionInfo[need].requires) if (need === other) return true;
    return false;
  };
  const toggle = (permission: Permission, on: boolean) =>
    setSelected((current) => {
      const next = new Set(current);
      if (on) {
        next.add(permission);
        for (let need = permissionInfo[permission].requires; need; need = permissionInfo[need].requires) next.add(need);
      } else {
        next.delete(permission);
        for (const other of [...next]) if (dependsOn(other, permission)) next.delete(other);
      }
      return next;
    });
  const save = async () => {
    const ok = await run(() => changeAccess(a, selected), { success: `Access updated for ${a.name}` });
    if (ok) onClose();
  };
  return (
    <Dialog
      open={account != null}
      onClose={onClose}
      title={`Access for ${a.name}`}
      icon={ShieldCheck}
      size="lg"
      description={role === 'custom' ? 'Nothing is allowed until you switch it on. Switch on what this person needs.' : `Starts from what a ${roleInfo[role].label} can do. Switch anything on or off for this person.`}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" loading={pending} onClick={() => void save()}>
            Save
          </Button>
        </>
      }
    >
      <div className="flex flex-wrap items-center justify-between gap-2 pb-2">
        <p className="text-[14px] font-semibold text-ink">
          {selected.size} of {allPermissions.length} allowed
        </p>
        <Button size="sm" variant="ghost" onClick={() => setSelected(new Set(permissionsOfRole(role)))}>
          {role === 'custom' ? 'Clear all' : `Reset to ${roleInfo[role].label}`}
        </Button>
      </div>
      <div className="grid gap-x-6 pb-3 md:grid-cols-2">
        {accessGroups.map(([title, permissions]) => (
          <section key={title} className="mt-3">
            <h3 className="text-[11.5px] font-bold uppercase tracking-[0.1em] text-brand-text">{title}</h3>
            <div className="divide-y divide-line">
              {permissions.map((p) => (
                <SwitchRow key={p} title={permissionInfo[p].label} description={accessNotes[p]} checked={selected.has(p)} onChange={(on) => toggle(p, on)} tone="success" />
              ))}
            </div>
          </section>
        ))}
      </div>
    </Dialog>
  );
}
