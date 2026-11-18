import { parseOptionalInstant } from './time';

type Json = Record<string, unknown>;

/** The restaurant's Terms & Conditions and Privacy Policy, published on the server. */
export type LegalDocumentKind = 'terms' | 'privacy';
export const legalKinds: readonly LegalDocumentKind[] = ['terms', 'privacy'];
export const legalKindLabel: Record<LegalDocumentKind, string> = {
  terms: 'Terms & Conditions',
  privacy: 'Privacy Policy',
};

const parseKind = (name: unknown): LegalDocumentKind | null => (name === 'terms' || name === 'privacy' ? name : null);

export type LegalDocumentStatus = 'draft' | 'published' | 'retired';
export const legalStatusLabel: Record<LegalDocumentStatus, string> = { draft: 'Draft', published: 'Published', retired: 'Retired' };

/** A document version as staff manage it (raw text, placeholders unfilled). */
export interface LegalDocumentVersion {
  id: number;
  kind: LegalDocumentKind;
  version: number;
  title: string;
  body: string;
  status: LegalDocumentStatus;
  changeSummary: string;
  /** A material change: guests who accepted earlier versions accept again. */
  requiresReacceptance: boolean;
  createdAt: Date | null;
  createdBy: string;
  updatedAt: Date | null;
  updatedBy: string;
  publishedAt: Date | null;
  publishedBy: string;
  retiredAt: Date | null;
  /** How many guest sessions accepted this version. */
  acceptances: number;
}

export function legalVersionFromJson(json: Json): LegalDocumentVersion | null {
  const kind = parseKind(json.kind);
  if (!kind) return null;
  const status = json.status === 'draft' || json.status === 'published' ? json.status : 'retired';
  return {
    id: json.id as number,
    kind,
    version: json.version as number,
    title: (json.title as string | undefined) ?? '',
    body: (json.body as string | undefined) ?? '',
    status,
    changeSummary: (json.changeSummary as string | undefined) ?? '',
    requiresReacceptance: (json.requiresReacceptance as boolean | undefined) ?? true,
    createdAt: parseOptionalInstant(json.createdAt),
    createdBy: (json.createdBy as string | undefined) ?? '',
    updatedAt: parseOptionalInstant(json.updatedAt),
    updatedBy: (json.updatedBy as string | undefined) ?? '',
    publishedAt: parseOptionalInstant(json.publishedAt),
    publishedBy: (json.publishedBy as string | undefined) ?? '',
    retiredAt: parseOptionalInstant(json.retiredAt),
    acceptances: (json.acceptances as number | undefined) ?? 0,
  };
}

/** What staff write for a new version or a draft. */
export interface LegalDocumentDraft {
  kind: LegalDocumentKind;
  title: string;
  body: string;
  changeSummary: string;
  requiresReacceptance: boolean;
}

/** One acceptance record: a guest session accepted a document version. */
export interface LegalAcceptanceRecord {
  id: number;
  hotelId: number;
  /** The guest session's id. */
  customerId: string;
  /** Null for takeaway. */
  tableNumber: number | null;
  kind: LegalDocumentKind;
  version: number;
  title: string;
  accepted: boolean;
  acceptedAt: Date;
}

export function acceptanceFromJson(json: Json): LegalAcceptanceRecord | null {
  const kind = parseKind(json.kind);
  if (!kind) return null;
  return {
    id: json.id as number,
    hotelId: (json.hotelId as number | undefined) ?? 1,
    customerId: (json.customerId as string | undefined) ?? '',
    tableNumber: (json.tableNumber as number | null | undefined) ?? null,
    kind,
    version: json.version as number,
    title: (json.title as string | undefined) ?? '',
    accepted: (json.accepted as boolean | undefined) ?? true,
    acceptedAt: parseOptionalInstant(json.acceptedAt) ?? new Date(2000, 0, 1),
  };
}

/** The first block of the session id, enough to tell guests apart. */
export const shortCustomerId = (id: string) => (id.length > 8 ? id.slice(0, 8) : id);

// --------------------------------------------------------- simple Markdown

/**
 * The small Markdown subset legal documents are written in: `## Heading`
 * (and `#`, `###`), `- item` or `* item` bullets, paragraphs separated by
 * blank lines, and `**bold**`. Anything else is plain text, so a document can
 * never inject markup or links.
 */
export interface LegalSpan {
  text: string;
  bold: boolean;
}

export type LegalBlock =
  | { type: 'heading'; level: number; spans: LegalSpan[] }
  | { type: 'paragraph'; spans: LegalSpan[] }
  | { type: 'bullet'; spans: LegalSpan[] };

export function legalSpans(text: string): LegalSpan[] {
  const result: LegalSpan[] = [];
  let at = 0;
  for (const m of text.matchAll(/\*\*(.+?)\*\*/g)) {
    if (m.index! > at) result.push({ text: text.slice(at, m.index), bold: false });
    result.push({ text: m[1]!, bold: true });
    at = m.index! + m[0].length;
  }
  if (at < text.length) result.push({ text: text.slice(at), bold: false });
  return result;
}

export function parseLegalText(source: string): LegalBlock[] {
  const blocks: LegalBlock[] = [];
  const paragraph: string[] = [];
  const flush = () => {
    if (!paragraph.length) return;
    blocks.push({ type: 'paragraph', spans: legalSpans(paragraph.join(' ')) });
    paragraph.length = 0;
  };
  for (const raw of source.replaceAll('\r\n', '\n').split('\n')) {
    const line = raw.trim();
    if (!line) {
      flush();
      continue;
    }
    const heading = /^(#{1,3})\s+(.*)$/.exec(line);
    const bullet = /^[-*]\s+(.*)$/.exec(line);
    if (heading) {
      flush();
      blocks.push({ type: 'heading', level: heading[1]!.length, spans: legalSpans(heading[2]!.trim()) });
    } else if (bullet) {
      flush();
      blocks.push({ type: 'bullet', spans: legalSpans(bullet[1]!.trim()) });
    } else {
      paragraph.push(line);
    }
  }
  flush();
  return blocks;
}
