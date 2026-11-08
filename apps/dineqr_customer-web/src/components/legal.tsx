import { FileText, ShieldCheck } from 'lucide-react';
import { Fragment, type ReactNode } from 'react';
import { Link } from 'react-router';
import {
  isUpdate,
  legalKinds,
  legalLabel,
  legalStatement,
  parseLegalText,
  type LegalKind,
  type LegalRequirement,
  type LegalSpan,
} from '../core/legal';
import { paths } from '../routes/paths';
import { Card } from './ui';
import { iconSize } from './sizes';

const spans = (items: LegalSpan[]): ReactNode =>
  items.map((span, i) => (span.bold ? <strong key={i}>{span.text}</strong> : <Fragment key={i}>{span.text}</Fragment>));

/** A document body as readable text (rendered as text, never as HTML). */
export function LegalText({ source }: { source: string }) {
  return (
    <div className="legal-text">
      {parseLegalText(source).map((block, i) => {
        switch (block.type) {
          case 'heading':
            return block.level <= 1 ? <h2 key={i}>{spans(block.spans)}</h2> : <h3 key={i}>{spans(block.spans)}</h3>;
          case 'bullets':
            return (
              <ul key={i}>
                {block.items.map((item, j) => (
                  <li key={j}>{spans(item)}</li>
                ))}
              </ul>
            );
          default:
            return <p key={i}>{spans(block.spans)}</p>;
        }
      })}
    </div>
  );
}

/** "Terms & Conditions · Privacy Policy" as links to the full documents. */
export function LegalLinks({ intro }: { intro?: string }) {
  return (
    <p className="legal-links t-caption">
      {intro && <span>{intro} </span>}
      {legalKinds.map((kind, i) => (
        <Fragment key={kind}>
          {i > 0 && ' and '}
          <Link to={paths.legal(kind)}>{legalLabel[kind]}</Link>
        </Fragment>
      ))}
      {intro && '.'}
    </p>
  );
}

/**
 * The boxes a guest ticks before their first order (and after a material
 * change): one per document still to accept, with a link to its full text.
 * Nothing is ticked in advance.
 */
export function LegalConsent({
  pending,
  ticked,
  onChange,
  disabled = false,
}: {
  pending: LegalRequirement[];
  ticked: ReadonlySet<LegalKind>;
  onChange: (kind: LegalKind, ticked: boolean) => void;
  disabled?: boolean;
}) {
  const updated = pending.some(isUpdate);
  return (
    <Card className="legal-consent">
      <div className="row">
        <ShieldCheck size={iconSize.lg} color="var(--accent-text)" />
        <span className="t-card-title">{updated ? 'We have updated our terms' : 'Before you order'}</span>
      </div>
      {pending.map((doc) => (
        <div key={doc.kind} className="legal-consent__item">
          <label className="legal-consent__label">
            <input
              type="checkbox"
              className="checkbox"
              checked={ticked.has(doc.kind)}
              disabled={disabled}
              onChange={(event) => onChange(doc.kind, event.target.checked)}
            />
            <span>{legalStatement[doc.kind]}</span>
          </label>
          {isUpdate(doc) && doc.changeSummary && <p className="legal-consent__change t-caption">What changed: {doc.changeSummary}</p>}
          <Link className="legal-consent__read t-caption" to={paths.legal(doc.kind)}>
            <FileText size={iconSize.sm} /> Read the {legalLabel[doc.kind]} (v{doc.version})
          </Link>
        </div>
      ))}
    </Card>
  );
}
