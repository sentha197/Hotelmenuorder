import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/legal_admin_controller.dart';
import '../../widgets/admin_widgets.dart';

/// Opens the editor for a new version of [kind] (starting from [base]'s
/// text) or for an existing [draft].
Future<void> openLegalEditor(
  BuildContext context, {
  required LegalDocumentKind kind,
  LegalDocumentVersion? base,
  LegalDocumentVersion? draft,
}) => pushAdminPage<void>(
  context,
  LegalEditorScreen(kind: kind, base: base, draft: draft),
  permission: Permission.manageSettings,
);

class LegalEditorScreen extends StatefulWidget {
  const LegalEditorScreen({
    super.key,
    required this.kind,
    this.base,
    this.draft,
  });

  final LegalDocumentKind kind;
  final LegalDocumentVersion? base;
  final LegalDocumentVersion? draft;

  @override
  State<LegalEditorScreen> createState() => _LegalEditorScreenState();
}

class _LegalEditorScreenState extends State<LegalEditorScreen> {
  late final _title = TextEditingController(
    text: widget.draft?.title ?? widget.base?.title ?? widget.kind.label,
  );
  late final _summary = TextEditingController(
    text: widget.draft?.changeSummary ?? '',
  );
  late final _body = TextEditingController(
    text: widget.draft?.body ?? widget.base?.body ?? '',
  );
  late bool _material = widget.draft?.requiresReacceptance ?? true;
  bool _preview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().length >= 3 && _body.text.trim().length >= 50;

  Future<void> _save() async {
    final legal = context.read<LegalAdminController>();
    final navigator = Navigator.of(context);
    final draft = LegalDocumentDraft(
      kind: widget.kind,
      title: _title.text.trim(),
      body: _body.text,
      changeSummary: _summary.text.trim(),
      requiresReacceptance: _material,
    );
    setState(() => _saving = true);
    final existing = widget.draft;
    final saved = await runAdminAction(
      context,
      () => existing == null
          ? legal.create(draft)
          : legal.update(existing.id, draft),
      success: 'Draft saved. Publish it when it is ready.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.draft;
    return Scaffold(
      backgroundColor: adminBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          existing == null
              ? 'New ${widget.kind.label} version'
              : '${widget.kind.label} · v${existing.version} draft',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: FilledButton(
              onPressed: _valid && !_saving ? _save : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(_saving ? 'Saving…' : 'Save draft'),
            ),
          ),
        ],
      ),
      body: AdminPage(
        title: widget.kind.label,
        subtitle: existing == null
            ? 'Saved as a draft. Guests see it only once you publish it.'
            : 'Drafts can be changed until they are published.',
        maxWidth: 860,
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: _summary,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'What changed (shown to guests)',
                    hintText: 'e.g. New section on refunds of online payments',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _material,
                  onChanged: (v) => setState(() => _material = v),
                  activeThumbColor: AppColors.primary,
                  title: const Text('Material change'),
                  subtitle: Text(
                    _material
                        ? 'Every guest must accept this version before their '
                              'next order, even if they accepted an earlier '
                              'one.'
                        : 'Guests who accepted an earlier version keep '
                              'ordering; new guests accept this version. Use '
                              'only for wording fixes that change nothing.',
                    style: AppTypography.caption,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.edit_outlined),
                label: Text('Write'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.visibility_outlined),
                label: Text('Preview'),
              ),
            ],
            selected: {_preview},
            onSelectionChanged: (s) => setState(() => _preview = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_preview)
            SectionCard(
              child: _body.text.trim().isEmpty
                  ? Text('Nothing written yet.', style: AppTypography.caption)
                  : LegalTextView(_body.text),
            )
          else ...[
            SectionCard(
              child: TextField(
                controller: _body,
                minLines: 18,
                maxLines: null,
                maxLength: 60000,
                keyboardType: TextInputType.multiline,
                style: AppTypography.body.copyWith(height: 1.45),
                decoration: const InputDecoration(
                  labelText: 'Full text',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Formatting: a line starting with "## " is a heading, "- " a '
              'bullet, and **text** is bold; leave a blank line between '
              'paragraphs. {{restaurant.name}}, {{restaurant.address}}, '
              '{{restaurant.phone}} and {{restaurant.email}} are replaced '
              'with the details in Settings when guests read it.',
              style: AppTypography.caption,
            ),
          ],
        ],
      ),
    );
  }
}
