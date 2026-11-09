/// The small Markdown subset legal documents are written in:
///
/// - `## Heading` (and `#`, `###`) on its own line;
/// - `- item` or `* item` bullets;
/// - paragraphs separated by blank lines (lines within one are joined);
/// - `**bold**` inside any of them.
///
/// Anything else is shown as plain text, so a document can never inject
/// markup or links.
sealed class LegalBlock {
  const LegalBlock(this.spans);

  final List<LegalSpan> spans;

  /// The plain text, without emphasis.
  String get text => spans.map((s) => s.text).join();
}

final class LegalHeading extends LegalBlock {
  const LegalHeading(super.spans, {this.level = 2});

  final int level;
}

final class LegalParagraph extends LegalBlock {
  const LegalParagraph(super.spans);
}

final class LegalBullet extends LegalBlock {
  const LegalBullet(super.spans);
}

class LegalSpan {
  const LegalSpan(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  bool operator ==(Object other) =>
      other is LegalSpan && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => bold ? '**$text**' : text;
}

abstract final class LegalText {
  static final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final _bullet = RegExp(r'^[-*]\s+(.*)$');
  static final _bold = RegExp(r'\*\*(.+?)\*\*');

  static List<LegalBlock> parse(String source) {
    final blocks = <LegalBlock>[];
    final paragraph = <String>[];
    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(LegalParagraph(spans(paragraph.join(' '))));
      paragraph.clear();
    }

    for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (_heading.firstMatch(line) case final m?) {
        flush();
        blocks.add(
          LegalHeading(spans(m.group(2)!.trim()), level: m.group(1)!.length),
        );
      } else if (_bullet.firstMatch(line) case final m?) {
        flush();
        blocks.add(LegalBullet(spans(m.group(1)!.trim())));
      } else {
        paragraph.add(line);
      }
    }
    flush();
    return blocks;
  }

  /// [text] split into plain and `**bold**` runs.
  static List<LegalSpan> spans(String text) {
    final result = <LegalSpan>[];
    var at = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > at) result.add(LegalSpan(text.substring(at, m.start)));
      result.add(LegalSpan(m.group(1)!, bold: true));
      at = m.end;
    }
    if (at < text.length) result.add(LegalSpan(text.substring(at)));
    return result;
  }
}
