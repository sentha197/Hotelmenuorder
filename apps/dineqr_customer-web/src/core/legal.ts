/**
 * The restaurant's Terms & Conditions and Privacy Policy, as published by
 * staff on the server. The app holds no copy of the text: it shows what the
 * server sends.
 */

export type LegalKind = 'terms' | 'privacy';

export const legalKinds: readonly LegalKind[] = ['terms', 'privacy'];

export const legalLabel: Record<LegalKind, string> = {
  terms: 'Terms & Conditions',
  privacy: 'Privacy Policy',
};

/** What the guest says when ticking the box. */
export const legalStatement: Record<LegalKind, string> = {
  terms: 'I have read and accept the Terms & Conditions.',
  privacy: 'I have read and acknowledge the Privacy Policy.',
};

export const isLegalKind = (value: unknown): value is LegalKind => value === 'terms' || value === 'privacy';

type Json = Record<string, unknown>;

const date = (value: unknown): Date | null => {
  if (typeof value !== 'string') return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

/** A published document, placeholders already filled in by the server. */
export interface LegalDocument {
  kind: LegalKind;
  version: number;
  title: string;
  body: string;
  changeSummary: string;
  publishedAt: Date | null;
}

export function legalDocumentFromJson(json: Json): LegalDocument | null {
  if (!isLegalKind(json.kind)) return null;
  return {
    kind: json.kind,
    version: Number(json.version),
    title: String(json.title ?? ''),
    body: String(json.body ?? ''),
    changeSummary: String(json.changeSummary ?? ''),
    publishedAt: date(json.publishedAt),
  };
}

/** One document in the guest's status. */
export interface LegalRequirement {
  kind: LegalKind;
  version: number;
  title: string;
  changeSummary: string;
  /** The guest must accept [version] before ordering. */
  required: boolean;
  acceptedVersion: number | null;
}

/** The guest accepted an earlier version and this one changed materially. */
export const isUpdate = (r: LegalRequirement): boolean => r.required && r.acceptedVersion != null;

export interface LegalStatus {
  canOrder: boolean;
  documents: LegalRequirement[];
}

export const noLegalRequirements: LegalStatus = { canOrder: true, documents: [] };

export function legalStatusFromJson(json: Json): LegalStatus {
  const documents = (Array.isArray(json.documents) ? (json.documents as Json[]) : [])
    .filter((d) => isLegalKind(d.kind))
    .map(
      (d): LegalRequirement => ({
        kind: d.kind as LegalKind,
        version: Number(d.version),
        title: String(d.title ?? ''),
        changeSummary: String(d.changeSummary ?? ''),
        required: d.required !== false,
        acceptedVersion: typeof d.acceptedVersion === 'number' ? d.acceptedVersion : null,
      }),
    );
  return { canOrder: json.canOrder === true, documents };
}

export const pendingOf = (status: LegalStatus | null): LegalRequirement[] =>
  status?.documents.filter((d) => d.required) ?? [];

// ------------------------------------------------------------- the text

/**
 * The small Markdown subset documents are written in: `#`/`##`/`###`
 * headings, `- ` or `* ` bullets, paragraphs separated by blank lines, and
 * `**bold**`. Everything else stays plain text (rendered as text, never as
 * HTML), so a document cannot inject markup or links.
 */
export type LegalSpan = { text: string; bold: boolean };
export type LegalBlock =
  | { type: 'heading'; level: number; spans: LegalSpan[] }
  | { type: 'paragraph'; spans: LegalSpan[] }
  | { type: 'bullets'; items: LegalSpan[][] };

export function legalSpans(text: string): LegalSpan[] {
  const spans: LegalSpan[] = [];
  const bold = /\*\*(.+?)\*\*/g;
  let at = 0;
  for (const match of text.matchAll(bold)) {
    const start = match.index ?? 0;
    if (start > at) spans.push({ text: text.slice(at, start), bold: false });
    spans.push({ text: match[1] ?? '', bold: true });
    at = start + match[0].length;
  }
  if (at < text.length) spans.push({ text: text.slice(at), bold: false });
  return spans;
}

export function parseLegalText(source: string): LegalBlock[] {
  const blocks: LegalBlock[] = [];
  let paragraph: string[] = [];
  const flush = () => {
    if (paragraph.length > 0) blocks.push({ type: 'paragraph', spans: legalSpans(paragraph.join(' ')) });
    paragraph = [];
  };
  for (const raw of source.replace(/\r\n/g, '\n').split('\n')) {
    const line = raw.trim();
    if (!line) {
      flush();
      continue;
    }
    const heading = /^(#{1,3})\s+(.*)$/.exec(line);
    const bullet = /^[-*]\s+(.*)$/.exec(line);
    if (heading) {
      flush();
      blocks.push({ type: 'heading', level: (heading[1] ?? '#').length, spans: legalSpans((heading[2] ?? '').trim()) });
    } else if (bullet) {
      flush();
      const last = blocks[blocks.length - 1];
      const item = legalSpans((bullet[1] ?? '').trim());
      if (last?.type === 'bullets') last.items.push(item);
      else blocks.push({ type: 'bullets', items: [item] });
    } else {
      paragraph.push(line);
    }
  }
  flush();
  return blocks;
}
