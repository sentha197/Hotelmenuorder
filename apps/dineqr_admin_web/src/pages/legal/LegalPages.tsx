import { useQuery } from '@tanstack/react-query';
import { CloudOff, Eye, FileText, History, Pencil, Plus, Save, Send, SearchX, Trash2, TriangleAlert, Undo2, X } from 'lucide-react';
import { Fragment, useState } from 'react';
import { useNavigate, useParams } from 'react-router';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { SectionCard } from '@/components/ui/Card';
import { confirmDialog } from '@/components/ui/Dialog';
import { Empty, Notice, PageSkeleton } from '@/components/ui/Feedback';
import { FilterChips, Segmented, SwitchRow, TextArea, TextField } from '@/components/ui/Form';
import { Page } from '@/components/ui/Page';
import { legalKindLabel, legalKinds, legalStatusLabel, parseLegalText, shortCustomerId, type LegalDocumentKind, type LegalDocumentVersion, type LegalSpan } from '@/core/legal';
import { AppFormat } from '@/core/time';
import { createLegalVersion, deleteLegalVersion, publishLegalVersion, unpublishLegalVersion, updateLegalVersion } from '@/state/actions';
import { keys, useLegalVersions } from '@/state/data';
import { errorMessage, runAction, useAction } from '@/state/run';
import { requireBackend } from '@/services/backend';
import { useAccess } from '@/state/session';

type Tab = LegalDocumentKind | 'history';
const tabLabel: Record<Tab, string> = { terms: 'Terms & Conditions', privacy: 'Privacy Policy', history: 'Acceptance history' };
const when = (d: Date | null) => (d ? AppFormat.dateTime(d) : '—');

const versionsOf = (all: LegalDocumentVersion[], kind: LegalDocumentKind) => all.filter((v) => v.kind === kind).sort((a, b) => b.version - a.version);

/**
 * Terms & Conditions and Privacy Policy: write versions, publish them, and
 * see which guests accepted which version and when (LegalScreen).
 */
export function LegalPage() {
  const query = useLegalVersions();
  const [tab, setTab] = useState<Tab>('terms');
  return (
    <Page title="Terms & Privacy" subtitle="What guests accept before their first order, and when they accepted it">
      <FilterChips name="legal-tab" values={['terms', 'privacy', 'history'] as Tab[]} selected={tab} labelOf={(t) => tabLabel[t]} onSelect={setTab} />
      {query.isError && !query.data ? (
        <Empty icon={CloudOff} title="Could not load the documents" message={errorMessage(query.error)} action={<Button onClick={() => void query.refetch()}>Try again</Button>} />
      ) : query.isPending ? (
        <PageSkeleton rows={3} />
      ) : tab === 'history' ? (
        <AcceptanceHistory versions={query.data ?? []} />
      ) : (
        <Documents kind={tab} versions={query.data ?? []} />
      )}
    </Page>
  );
}

function Documents({ kind, versions }: { kind: LegalDocumentKind; versions: LegalDocumentVersion[] }) {
  const navigate = useNavigate();
  const { can } = useAccess();
  const all = versionsOf(versions, kind);
  const published = all.find((v) => v.status === 'published');
  const drafts = all.filter((v) => v.status === 'draft');
  const earlier = all.filter((v) => v.status === 'retired');
  return (
    <>
      {published ? (
        <SectionCard
          title={`Published · version ${published.version}`}
          subtitle={`Since ${when(published.publishedAt)}${published.publishedBy ? ` by ${published.publishedBy}` : ''} · accepted by ${published.acceptances} ${published.acceptances === 1 ? 'guest' : 'guests'}`}
        >
          <VersionActions version={published} />
        </SectionCard>
      ) : (
        <Notice tone="warning" icon={TriangleAlert}>
          No {legalKindLabel[kind]} is published, so guests are not asked to accept one before ordering. Publish a version to require it.
        </Notice>
      )}
      {can('manageSettings') && (
        <Button variant="primary" icon={Plus} className="self-start" onClick={() => navigate(`/legal/new/${kind}`)}>
          New version
        </Button>
      )}
      {drafts.length > 0 && (
        <section className="flex flex-col gap-3">
          <h2 className="text-[15px] font-semibold text-ink">Drafts</h2>
          {drafts.map((d) => (
            <SectionCard key={d.id} title={`Version ${d.version} · draft`} subtitle={`Last edited ${when(d.updatedAt)}${d.updatedBy ? ` by ${d.updatedBy}` : ''}${d.requiresReacceptance ? ' · guests must accept it again' : ' · minor change'}`}>
              <VersionActions version={d} />
            </SectionCard>
          ))}
        </section>
      )}
      {earlier.length > 0 && (
        <SectionCard title="Earlier versions">
          <ul className="divide-y divide-line">
            {earlier.map((v) => (
              <li key={v.id}>
                <button type="button" onClick={() => navigate(`/legal/versions/${v.id}`)} className="flex w-full items-center gap-3 py-3 text-left hover:bg-panel-2/50">
                  <History size={18} className="text-faint" aria-hidden />
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13.5px] font-semibold text-ink">Version {v.version}</span>
                    <span className="block text-[12px] text-muted">
                      Published {when(v.publishedAt)} · retired {when(v.retiredAt)} · {v.acceptances} {v.acceptances === 1 ? 'acceptance' : 'acceptances'}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </SectionCard>
      )}
      <p className="max-w-3xl text-[12.5px] leading-relaxed text-faint">
        A published version never changes: guests accepted exactly that text. To change it, create a new version and publish it. Mark it as a material change when guests must accept it again before ordering; minor wording changes do not ask returning guests again.
      </p>
    </>
  );
}

function VersionActions({ version }: { version: LegalDocumentVersion }) {
  const navigate = useNavigate();
  const { can } = useAccess();
  const canEdit = can('manageSettings');
  const kind = legalKindLabel[version.kind];
  const publish = async () => {
    const ok = await confirmDialog({
      title: `Publish version ${version.version}?`,
      message: version.requiresReacceptance
        ? `Guests will see this ${kind} from now on, and every guest must accept it before their next order.`
        : `Guests will see this ${kind} from now on. Guests who accepted an earlier version are not asked again (minor change).`,
      confirmLabel: 'Publish',
      icon: Send,
    });
    if (ok) await runAction(() => publishLegalVersion(version.id), { success: `${kind} version ${version.version} published` });
  };
  const unpublish = async () => {
    const ok = await confirmDialog({
      title: `Unpublish the ${kind}?`,
      message: `Guests will no longer see a ${kind}, and will not be asked to accept one before ordering, until you publish a new version. The acceptance records are kept.`,
      confirmLabel: 'Unpublish',
      icon: Undo2,
      danger: true,
    });
    if (ok) await runAction(() => unpublishLegalVersion(version.id), { success: `${kind} unpublished` });
  };
  const remove = async () => {
    const ok = await confirmDialog({ title: 'Delete this draft?', message: `Version ${version.version} was never published.`, confirmLabel: 'Delete', icon: Trash2, danger: true });
    if (ok) await runAction(() => deleteLegalVersion(version.id), { success: 'Draft deleted' });
  };
  return (
    <div>
      <p className="text-[14px] font-semibold text-ink">{version.title}</p>
      {version.changeSummary && <p className="mt-0.5 text-[12.5px] text-muted">Changes: {version.changeSummary}</p>}
      <div className="mt-3 flex flex-wrap gap-2">
        <Button size="sm" icon={Eye} onClick={() => navigate(`/legal/versions/${version.id}`)}>
          Preview
        </Button>
        {canEdit && version.status === 'draft' && (
          <>
            <Button size="sm" icon={Pencil} onClick={() => navigate(`/legal/drafts/${version.id}`)}>
              Edit
            </Button>
            <Button size="sm" variant="primary" icon={Send} onClick={() => void publish()}>
              Publish
            </Button>
            <Button size="sm" variant="danger" icon={Trash2} onClick={() => void remove()}>
              Delete
            </Button>
          </>
        )}
        {canEdit && version.status === 'published' && (
          <Button size="sm" variant="danger" icon={Undo2} onClick={() => void unpublish()}>
            Unpublish
          </Button>
        )}
      </div>
    </div>
  );
}

function Spans({ spans }: { spans: LegalSpan[] }) {
  return (
    <>
      {spans.map((s, i) => (s.bold ? <strong key={i}>{s.text}</strong> : <Fragment key={i}>{s.text}</Fragment>))}
    </>
  );
}

/** The simple Markdown of legal documents, rendered as text only (LegalTextView). */
export function LegalText({ body }: { body: string }) {
  return (
    <div className="flex flex-col gap-3 text-[14px] leading-relaxed text-ink">
      {parseLegalText(body).map((block, i) =>
        block.type === 'heading' ? (
          <h3 key={i} className={block.level === 1 ? 'text-[19px] font-bold' : block.level === 2 ? 'mt-2 text-[16px] font-semibold' : 'text-[14.5px] font-semibold'}>
            <Spans spans={block.spans} />
          </h3>
        ) : block.type === 'bullet' ? (
          <p key={i} className="flex gap-2 pl-1 text-muted">
            <span aria-hidden>•</span>
            <span>
              <Spans spans={block.spans} />
            </span>
          </p>
        ) : (
          <p key={i} className="text-muted">
            <Spans spans={block.spans} />
          </p>
        ),
      )}
    </div>
  );
}

/** The version as guests will read it (placeholders as written). */
export function LegalPreviewPage() {
  const { versionId } = useParams();
  const query = useLegalVersions();
  const version = query.data?.find((v) => String(v.id) === versionId);
  if (query.isPending) return <Page title="Preview" back="/legal"><PageSkeleton rows={3} /></Page>;
  if (!version) {
    return (
      <Page title="Preview" back="/legal">
        <Empty icon={SearchX} title="Version not found" />
      </Page>
    );
  }
  return (
    <Page title={version.title} eyebrow={`${legalKindLabel[version.kind]} · v${version.version}`} subtitle={`${legalStatusLabel[version.status]} · ${version.requiresReacceptance ? 'material change' : 'minor change'}`} back="/legal" width="narrow">
      <SectionCard>
        <LegalText body={version.body} />
      </SectionCard>
    </Page>
  );
}

/** Writes a new version or edits a draft (LegalEditorScreen). */
export function LegalEditorPage() {
  const { kind: kindParam, versionId } = useParams();
  const query = useLegalVersions();
  if (query.isPending) return <Page title="Document" back="/legal"><PageSkeleton rows={3} /></Page>;
  const draft = versionId ? query.data?.find((v) => String(v.id) === versionId && v.status === 'draft') : undefined;
  if (versionId && !draft) {
    return (
      <Page title="Document" back="/legal">
        <Empty icon={SearchX} title="Draft not found" message="It may have been published or deleted." />
      </Page>
    );
  }
  const kind: LegalDocumentKind = draft?.kind ?? (kindParam === 'privacy' ? 'privacy' : 'terms');
  const all = versionsOf(query.data ?? [], kind);
  // A new draft starts from the published version, else the newest.
  const base = draft ? null : (all.find((v) => v.status === 'published') ?? all[0] ?? null);
  return <LegalEditor key={versionId ?? kind} kind={kind} draft={draft ?? null} base={base} />;
}

function LegalEditor({ kind, draft, base }: { kind: LegalDocumentKind; draft: LegalDocumentVersion | null; base: LegalDocumentVersion | null }) {
  const navigate = useNavigate();
  const [title, setTitle] = useState(draft?.title ?? base?.title ?? legalKindLabel[kind]);
  const [summary, setSummary] = useState(draft?.changeSummary ?? '');
  const [body, setBody] = useState(draft?.body ?? base?.body ?? '');
  const [material, setMaterial] = useState(draft?.requiresReacceptance ?? true);
  const [mode, setMode] = useState<'write' | 'preview'>('write');
  const { pending, run } = useAction();
  const valid = title.trim().length >= 3 && body.trim().length >= 50;
  const save = async () => {
    const payload = { kind, title: title.trim(), body, changeSummary: summary.trim(), requiresReacceptance: material };
    const ok = await run(() => (draft ? updateLegalVersion(draft.id, payload) : createLegalVersion(payload)), { success: 'Draft saved. Publish it when it is ready.' });
    if (ok) navigate('/legal');
  };
  return (
    <Page
      title={draft ? `${legalKindLabel[kind]} · v${draft.version} draft` : `New ${legalKindLabel[kind]} version`}
      subtitle={draft ? 'Drafts can be changed until they are published.' : 'Saved as a draft. Guests see it only once you publish it.'}
      back="/legal"
      width="medium"
      actions={
        <Button variant="primary" icon={Save} loading={pending} disabled={!valid} onClick={() => void save()}>
          Save draft
        </Button>
      }
    >
      <SectionCard title={legalKindLabel[kind]}>
        <div className="flex flex-col gap-4">
          <TextField label="Title" maxLength={120} value={title} onChange={(e) => setTitle(e.target.value)} />
          <TextField label="What changed (shown to guests)" placeholder="e.g. New section on refunds of online payments" maxLength={300} value={summary} onChange={(e) => setSummary(e.target.value)} />
          <SwitchRow
            title="Material change"
            description={
              material
                ? 'Every guest must accept this version before their next order, even if they accepted an earlier one.'
                : 'Guests who accepted an earlier version keep ordering; new guests accept this version. Use only for wording fixes that change nothing.'
            }
            checked={material}
            onChange={setMaterial}
          />
        </div>
      </SectionCard>
      <SectionCard
        title="Full text"
        trailing={
          <Segmented
            name="legal-mode"
            value={mode}
            onChange={setMode}
            options={[
              { value: 'write', label: 'Write', icon: <FileText size={15} aria-hidden /> },
              { value: 'preview', label: 'Preview', icon: <Eye size={15} aria-hidden /> },
            ]}
          />
        }
      >
        {mode === 'write' ? (
          <TextArea aria-label="Full text" rows={18} maxLength={60000} value={body} onChange={(e) => setBody(e.target.value)} className="font-mono text-[13px]" />
        ) : body.trim() ? (
          <LegalText body={body} />
        ) : (
          <p className="text-[12.5px] text-faint">Nothing written yet.</p>
        )}
        <p className="mt-3 text-[12px] leading-relaxed text-faint">
          Formatting: a line starting with "## " is a heading, "- " a bullet, and **text** is bold; leave a blank line between paragraphs. {'{{restaurant.name}}'}, {'{{restaurant.address}}'}, {'{{restaurant.phone}}'} and {'{{restaurant.email}}'} are replaced with the details in Settings when guests read it.
        </p>
        {!valid && <p className="mt-2 text-[12px] text-warning">A title of at least 3 characters and a text of at least 50 characters are needed.</p>}
      </SectionCard>
    </Page>
  );
}

/** Which guests accepted which version and when (_History). */
function AcceptanceHistory({ versions }: { versions: LegalDocumentVersion[] }) {
  const [kind, setKind] = useState<LegalDocumentKind | null>(null);
  const [version, setVersion] = useState<number | null>(null);
  const [customer, setCustomer] = useState<string | null>(null);
  const filter = { kind, version, customer };
  const query = useQuery({
    queryKey: keys.legalHistory(filter),
    queryFn: () => requireBackend().api.legalAcceptances({ kind, version, customerId: customer, limit: 1000 }),
    retry: false,
  });
  const kindVersions = kind ? versionsOf(versions, kind).filter((v) => v.status !== 'draft') : [];
  const records = query.data ?? [];
  return (
    <div className="flex flex-col gap-4">
      <FilterChips
        name="history-kind"
        values={[null, ...legalKinds] as (LegalDocumentKind | null)[]}
        selected={kind}
        labelOf={(k) => (k ? legalKindLabel[k] : 'Both documents')}
        onSelect={(k) => {
          setKind(k);
          setVersion(null);
        }}
      />
      {kindVersions.length > 0 && <FilterChips name="history-version" values={[null, ...kindVersions.map((v) => v.version)]} selected={version} labelOf={(v) => (v == null ? 'Every version' : `Version ${v}`)} onSelect={setVersion} />}
      {customer && (
        <button type="button" onClick={() => setCustomer(null)} className="inline-flex w-fit items-center gap-1.5 rounded-full border border-line bg-panel-2 py-1 pl-3 pr-1.5 text-[12.5px] text-ink">
          Guest {shortCustomerId(customer)}
          <X size={14} aria-label="Show every guest" />
        </button>
      )}
      {query.isPending ? (
        <PageSkeleton rows={2} />
      ) : query.isError ? (
        <Empty icon={CloudOff} title="Could not load the history" message={errorMessage(query.error)} />
      ) : records.length === 0 ? (
        <Empty icon={History} title="No acceptances yet" message="Each time a guest accepts a document before ordering, it is recorded here with the version and time." />
      ) : (
        <SectionCard title={`${records.length} ${records.length === 1 ? 'record' : 'records'}`} subtitle="Newest first. Tap a guest to see all their records.">
          <ul className="divide-y divide-line">
            {records.map((r) => (
              <li key={r.id}>
                <button type="button" onClick={() => setCustomer(r.customerId)} className="flex w-full items-center gap-3 py-2.5 text-left hover:bg-panel-2/50">
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13.5px] font-semibold text-ink">
                      {legalKindLabel[r.kind]} · version {r.version}
                    </span>
                    <span className="block text-[12px] text-muted">
                      {AppFormat.dateTime(r.acceptedAt)} · {r.tableNumber == null ? 'Takeaway' : `Table ${AppFormat.table(r.tableNumber)}`} · guest {shortCustomerId(r.customerId)}
                    </span>
                  </span>
                  {!r.accepted && <Badge tone="warning">Declined</Badge>}
                </button>
              </li>
            ))}
          </ul>
        </SectionCard>
      )}
      <p className="text-[12px] leading-relaxed text-faint">
        Guests have no accounts: each record belongs to the guest session started by scanning a table (or takeaway) QR code. Records are kept as evidence of what was accepted and cannot be changed.
      </p>
    </div>
  );
}
