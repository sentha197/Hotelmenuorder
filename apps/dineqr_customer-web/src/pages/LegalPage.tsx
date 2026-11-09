import { CloudOff, FileText, History } from 'lucide-react';
import { useEffect } from 'react';
import { useParams } from 'react-router';
import { LegalText } from '../components/legal';
import { AppBar, Button, Card, EmptyState, FadeIn, QrLoader } from '../components/ui';
import { iconSize } from '../components/sizes';
import { isLegalKind, legalLabel } from '../core/legal';
import { AppFormat } from '../core/time';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { NotFoundPage } from './MiscPages';

/**
 * The restaurant's Terms & Conditions or Privacy Policy, as published on the
 * server. Readable by anyone: before scanning, and without a session.
 */
export function LegalPage() {
  const { kind } = useParams();
  const { legal } = useApp();
  useStore(legal);

  useEffect(() => {
    // Always the current version: staff may have published a new one.
    void legal.loadDocuments(true);
  }, [legal]);

  if (!isLegalKind(kind)) return <NotFoundPage />;
  const label = legalLabel[kind];
  const document = legal.document(kind);

  let content;
  if (document) {
    content = (
      <FadeIn className="stack-md">
        <header>
          <h1 className="t-headline">{document.title}</h1>
          <p className="t-caption">
            Version {document.version}
            {document.publishedAt && ` · Effective ${AppFormat.date(document.publishedAt)}`}
          </p>
        </header>
        {document.changeSummary && (
          <Card soft className="row-top legal-change">
            <History size={iconSize.md} />
            <span className="t-caption">What changed: {document.changeSummary}</span>
          </Card>
        )}
        <LegalText source={document.body} />
      </FadeIn>
    );
  } else if (legal.documentsState === 'error') {
    content = (
      <EmptyState
        icon={<CloudOff size={iconSize.hero} />}
        title={`Could not load the ${label}`}
        message={legal.documentsError ?? 'Please try again.'}
        action={<Button onClick={() => void legal.loadDocuments(true)}>Try Again</Button>}
      />
    );
  } else if (legal.documentsState === 'ready') {
    content = (
      <EmptyState
        icon={<FileText size={iconSize.hero} />}
        title="Not published"
        message={`The restaurant has not published a ${label}. Please ask a staff member.`}
      />
    );
  } else {
    content = (
      <div className="entry entry--center" role="status">
        <QrLoader size={30} label={`Loading the ${label}`} />
      </div>
    );
  }

  return (
    <div>
      <AppBar title={label} />
      <div className="page page--narrow legal-page">{content}</div>
    </div>
  );
}
