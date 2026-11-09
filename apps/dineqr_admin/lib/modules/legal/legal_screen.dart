import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/legal_admin_controller.dart';
import '../../widgets/admin_widgets.dart';
import 'legal_editor_screen.dart';

enum _Tab {
  terms('Terms & Conditions'),
  privacy('Privacy Policy'),
  history('Acceptance history');

  const _Tab(this.label);

  final String label;

  LegalDocumentKind? get kind => switch (this) {
    _Tab.terms => LegalDocumentKind.terms,
    _Tab.privacy => LegalDocumentKind.privacy,
    _Tab.history => null,
  };
}

/// Terms & Conditions and Privacy Policy: write versions, publish them,
/// and see which guests accepted which version and when.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  _Tab _tab = _Tab.terms;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LegalAdminController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final legal = context.watch<LegalAdminController>();
    return AdminPage(
      title: 'Terms & Privacy',
      subtitle:
          'What guests accept before their first order, and when they '
          'accepted it',
      onRefresh: legal.load,
      children: [
        if (!legal.isAvailable)
          const AdminEmpty(
            icon: Icons.cloud_off_rounded,
            title: 'Needs the restaurant server',
            message:
                'Terms & Conditions, the Privacy Policy and guests\' '
                'acceptances are kept on the DineQR server, which this offline '
                'demo does not use.',
          )
        else ...[
          FilterChipBar<_Tab>(
            values: _Tab.values,
            selected: _tab,
            labelOf: (t) => t.label,
            onSelected: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (legal.error != null && !legal.isLoaded)
            AdminEmpty(
              icon: Icons.error_outline_rounded,
              title: 'Could not load the documents',
              message: legal.error!,
            )
          else if (!legal.isLoaded)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xxxl),
              child: Center(
                child: QrPulseLoader(
                  size: 34,
                  color: AppColors.primary,
                  semanticLabel: 'Loading',
                ),
              ),
            )
          else if (_tab.kind case final kind?)
            _Versions(kind: kind)
          else
            const _History(),
        ],
      ],
    );
  }
}

String _when(DateTime? value) =>
    value == null ? '—' : AppFormat.dateTime(value);

class _Versions extends StatelessWidget {
  const _Versions({required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final legal = context.watch<LegalAdminController>();
    final all = legal.versionsOf(kind);
    final published = legal.publishedOf(kind);
    final drafts = all.where((v) => v.isDraft).toList();
    final earlier = all.where((v) => !v.isDraft && !v.isPublished).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (published == null)
          _Notice(
            icon: Icons.warning_amber_rounded,
            color: AppColors.warning,
            background: AppColors.warningSoft,
            text:
                'No ${kind.label} is published, so guests are not asked to '
                'accept one before ordering. Publish a version to require it.',
          )
        else
          SectionCard(
            title: 'Published · version ${published.version}',
            subtitle:
                'Since ${_when(published.publishedAt)}'
                '${published.publishedBy.isEmpty ? '' : ' by ${published.publishedBy}'}'
                ' · accepted by ${published.acceptances} '
                '${published.acceptances == 1 ? 'guest' : 'guests'}',
            child: _VersionActions(version: published),
          ),
        const SizedBox(height: AppSpacing.lg),
        if (legal.canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => openLegalEditor(
                context,
                kind: kind,
                base: legal.baseFor(kind),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New version'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
        if (drafts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Drafts', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          for (final draft in drafts) ...[
            SectionCard(
              title: 'Version ${draft.version} · draft',
              subtitle:
                  'Last edited ${_when(draft.updatedAt)}'
                  '${draft.updatedBy.isEmpty ? '' : ' by ${draft.updatedBy}'}'
                  '${draft.requiresReacceptance ? ' · guests must accept it again' : ' · minor change'}',
              child: _VersionActions(version: draft),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Earlier versions', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (index, v) in earlier.indexed) ...[
                  if (index > 0) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text('Version ${v.version}'),
                    subtitle: Text(
                      'Published ${_when(v.publishedAt)} · retired '
                      '${_when(v.retiredAt)} · ${v.acceptances} '
                      '${v.acceptances == 1 ? 'acceptance' : 'acceptances'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showLegalPreview(context, v),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          'A published version never changes: guests accepted exactly that '
          'text. To change it, create a new version and publish it. Mark it '
          'as a material change when guests must accept it again before '
          'ordering; minor wording changes do not ask returning guests again.',
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadii.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.caption.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

class _VersionActions extends StatelessWidget {
  const _VersionActions({required this.version});

  final LegalDocumentVersion version;

  Future<void> _publish(BuildContext context) async {
    final legal = context.read<LegalAdminController>();
    final kind = version.kind.label;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Publish version ${version.version}?',
      message: version.requiresReacceptance
          ? 'Guests will see this $kind from now on, and every guest must '
                'accept it before their next order.'
          : 'Guests will see this $kind from now on. Guests who accepted '
                'an earlier version are not asked again (minor change).',
      confirmLabel: 'Publish',
      icon: Icons.publish_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await runAdminAction(
      context,
      () => legal.publish(version.id),
      success: '$kind version ${version.version} published',
    );
  }

  Future<void> _unpublish(BuildContext context) async {
    final legal = context.read<LegalAdminController>();
    final kind = version.kind.label;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Unpublish the $kind?',
      message:
          'Guests will no longer see a $kind, and will not be asked to '
          'accept one before ordering, until you publish a new version. The '
          'acceptance records are kept.',
      confirmLabel: 'Unpublish',
      icon: Icons.unpublished_outlined,
    );
    if (!confirmed || !context.mounted) return;
    await runAdminAction(
      context,
      () => legal.unpublish(version.id),
      success: '$kind unpublished',
    );
  }

  Future<void> _delete(BuildContext context) async {
    final legal = context.read<LegalAdminController>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this draft?',
      message: 'Version ${version.version} was never published.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await runAdminAction(
      context,
      () => legal.delete(version.id),
      success: 'Draft deleted',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<LegalAdminController, bool>(
      (l) => l.canEdit,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(version.title, style: AppTypography.cardTitle),
        if (version.changeSummary.isNotEmpty)
          Text(
            'Changes: ${version.changeSummary}',
            style: AppTypography.caption,
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () => showLegalPreview(context, version),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Preview'),
            ),
            if (canEdit && version.isDraft) ...[
              OutlinedButton.icon(
                onPressed: () => openLegalEditor(
                  context,
                  kind: version.kind,
                  draft: version,
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              FilledButton.icon(
                onPressed: () => _publish(context),
                icon: const Icon(Icons.publish_rounded, size: 18),
                label: const Text('Publish'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
              TextButton.icon(
                onPressed: () => _delete(context),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ],
            if (canEdit && version.isPublished)
              TextButton.icon(
                onPressed: () => _unpublish(context),
                icon: const Icon(Icons.unpublished_outlined, size: 18),
                label: const Text('Unpublish'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
          ],
        ),
      ],
    );
  }
}

/// The version as guests will read it (placeholders as written: the server
/// fills in the restaurant's details when it serves the document).
Future<void> showLegalPreview(
  BuildContext context,
  LegalDocumentVersion version,
) => pushAdminPage<void>(
  context,
  Scaffold(
    backgroundColor: adminBackground,
    appBar: AppBar(
      leading: const AppBackButton(),
      title: Text('${version.kind.label} · v${version.version}'),
    ),
    body: AdminPage(
      title: version.title,
      subtitle:
          '${version.status.label} · '
          '${version.requiresReacceptance ? 'material change' : 'minor change'}',
      maxWidth: 760,
      children: [SectionCard(child: LegalTextView(version.body))],
    ),
  ),
);

class _History extends StatefulWidget {
  const _History();

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  LegalDocumentKind? _kind;
  int? _version;
  String? _customer;
  Future<List<LegalAcceptanceRecord>>? _records;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _records = context.read<LegalAdminController>().history(
      kind: _kind,
      version: _version,
      customerId: _customer,
    );
  }

  void _update(void Function() change) => setState(() {
    change();
    _reload();
  });

  @override
  Widget build(BuildContext context) {
    final legal = context.watch<LegalAdminController>();
    final versions = _kind == null
        ? const <LegalDocumentVersion>[]
        : legal.versionsOf(_kind!).where((v) => !v.isDraft).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterChipBar<LegalDocumentKind?>(
          values: const [null, ...LegalDocumentKind.values],
          selected: _kind,
          labelOf: (k) => k?.label ?? 'Both documents',
          onSelected: (k) => _update(() {
            _kind = k;
            _version = null;
          }),
        ),
        if (versions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          FilterChipBar<int?>(
            values: [null, for (final v in versions) v.version],
            selected: _version,
            labelOf: (v) => v == null ? 'Every version' : 'Version $v',
            onSelected: (v) => _update(() => _version = v),
          ),
        ],
        if (_customer != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Guest ${_customer!.substring(0, 8)}'),
              onDeleted: () => _update(() => _customer = null),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        FutureBuilder<List<LegalAcceptanceRecord>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AdminEmpty(
                icon: Icons.error_outline_rounded,
                title: 'Could not load the history',
                message: switch (snapshot.error) {
                  ValidationException(:final message) => message,
                  ApiException(:final message) => message,
                  _ => 'Please try again.',
                },
              );
            }
            final records = snapshot.data;
            if (records == null) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (records.isEmpty) {
              return const AdminEmpty(
                icon: Icons.fact_check_outlined,
                title: 'No acceptances yet',
                message:
                    'Each time a guest accepts a document before ordering, '
                    'it is recorded here with the version and time.',
              );
            }
            return SectionCard(
              title:
                  '${records.length} '
                  '${records.length == 1 ? 'record' : 'records'}',
              subtitle: 'Newest first. Tap a guest to see all their records.',
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Column(
                children: [
                  for (final (index, r) in records.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r.accepted
                            ? Icons.check_circle_rounded
                            : Icons.cancel_outlined,
                        color: r.accepted
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                      title: Text('${r.kind.label} · version ${r.version}'),
                      subtitle: Text(
                        '${AppFormat.dateTime(r.acceptedAt)} · '
                        '${r.tableNumber == null ? 'Takeaway' : 'Table ${AppFormat.table(r.tableNumber!)}'}'
                        ' · guest ${r.shortCustomerId}',
                      ),
                      onTap: _customer == null
                          ? () => _update(() => _customer = r.customerId)
                          : null,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Guests have no accounts: each record belongs to the guest session '
          'started by scanning a table (or takeaway) QR code. Records are '
          'kept as evidence of what was accepted and cannot be changed.',
          style: AppTypography.caption,
        ),
      ],
    );
  }
}
