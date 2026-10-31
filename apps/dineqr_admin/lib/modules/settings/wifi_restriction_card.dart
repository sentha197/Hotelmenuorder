import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';

/// Dine-in Wi-Fi restriction: guests at a table can order and pay only from
/// the restaurant's own internet connection. The server recognises it by
/// the public address requests come from; the Wi-Fi name is only a hint for
/// guests. Saved separately from the rest of the page.
class WifiRestrictionCard extends StatefulWidget {
  const WifiRestrictionCard({super.key});

  @override
  State<WifiRestrictionCard> createState() => _WifiRestrictionCardState();
}

class _WifiRestrictionCardState extends State<WifiRestrictionCard> {
  late final NetworkAccessSettingsController _controller = context
      .read<NetworkAccessSettingsController>();

  bool _enabled = false;
  bool _takeaway = false;
  final _ssid = TextEditingController();
  final _value = TextEditingController();
  final _label = TextEditingController();
  List<AuthorizedNetwork> _networks = [];
  bool _loading = false;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _adopt(_controller.settings);
    if (_controller.isAvailable && !_controller.isLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _ssid.dispose();
    _value.dispose();
    _label.dispose();
    super.dispose();
  }

  void _adopt(NetworkAccessSettings settings) {
    _enabled = settings.enabled;
    _takeaway = settings.restrictTakeaway;
    _ssid.text = settings.ssid;
    _networks = [...settings.networks];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _controller.load();
      if (mounted) setState(() => _adopt(_controller.settings));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _loadError = error is ApiException
              ? error.message
              : 'The Wi-Fi restriction could not be loaded.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _add(String value, String label) {
    final text = value.trim();
    if (text.isEmpty || _networks.any((n) => n.value == text)) return;
    setState(() {
      _networks = [..._networks, AuthorizedNetwork(value: text, label: label)];
      _value.clear();
      _label.clear();
    });
  }

  Future<void> _save() async {
    final you = _controller.you;
    if (_enabled && !_controller.settings.enabled && you?.matches != true) {
      // Switching on from elsewhere is allowed (the owner may be at home),
      // but worth a second look.
      final confirmed = await showConfirmDialog(
        context,
        title: 'Switch the restriction on?',
        message:
            'This device is not on one of the listed networks right now, so '
            'the server cannot confirm the list is right. Guests not on a '
            'listed network will not be able to order at their table.',
        confirmLabel: 'Switch on',
        icon: Icons.wifi_lock_rounded,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _saving = true);
    final ok = await runAdminAction(
      context,
      () => _controller.save(
        NetworkAccessSettings(
          enabled: _enabled,
          ssid: _ssid.text,
          restrictTakeaway: _takeaway,
          networks: _networks,
        ),
      ),
      success: 'Wi-Fi restriction saved',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _adopt(_controller.settings);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<NetworkAccessSettingsController>();
    const title = 'Dine-in Wi-Fi restriction';
    const subtitle =
        "Guests at a table can order and pay only from the restaurant's own "
        'internet connection, recognised by its public address. Mobile data '
        'and other Wi-Fi networks are refused by the server.';
    if (!_controller.isAvailable) {
      return const SectionCard(
        title: title,
        subtitle: subtitle,
        child: Text(
          'Needs the DineQR server: only the server can see which network a '
          'guest is on. It is not part of the offline demo.',
        ),
      );
    }
    if (_loading && !_controller.isLoaded) {
      return const SectionCard(
        title: title,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null && !_controller.isLoaded) {
      return SectionCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_loadError!, style: AppTypography.caption),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final you = _controller.you;
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            activeThumbColor: AppColors.primary,
            onChanged: (value) => setState(() => _enabled = value),
            title: Text(
              'Require the restaurant Wi-Fi',
              style: AppTypography.cardTitle,
            ),
            subtitle: Text(
              'Off: guests order from any network, as before.',
              style: AppTypography.caption,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _takeaway,
            activeThumbColor: AppColors.primary,
            onChanged: (value) => setState(() => _takeaway = value),
            title: Text(
              'Include takeaway orders',
              style: AppTypography.cardTitle,
            ),
            subtitle: Text(
              'Off: takeaway guests can order from anywhere.',
              style: AppTypography.caption,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _ssid,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi name shown to guests (optional)',
              helperText:
                  'Only a hint for which network to join. It never grants '
                  'access: any phone can show any name.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Authorised networks', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "The restaurant connection's public address (IPv4, e.g. "
            '203.0.113.7), its IPv6 prefix (e.g. 2001:db8:12:34::/64), a '
            'small range, or a dynamic-DNS name (e.g. cafe.ddns.net) if the '
            'provider changes the address. Never shown to guests.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_networks.isEmpty)
            Text(
              'None yet.',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          for (final network in _networks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                network.isHost ? Icons.dns_outlined : Icons.router_outlined,
                color: AppColors.textSecondary,
              ),
              title: Text(network.value, style: AppTypography.label),
              subtitle: network.label.isEmpty && network.resolved.isEmpty
                  ? null
                  : Text(
                      [
                        if (network.label.isNotEmpty) network.label,
                        if (network.isHost)
                          network.resolved.isEmpty
                              ? 'does not resolve right now'
                              : 'now ${network.resolved.join(', ')}',
                      ].join(' · '),
                      style: AppTypography.caption,
                    ),
              trailing: IconButton(
                tooltip: 'Remove ${network.value}',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => setState(
                  () => _networks = [
                    for (final n in _networks)
                      if (n.value != network.value) n,
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _value,
                  decoration: const InputDecoration(
                    labelText: 'Address, range or hostname',
                  ),
                  onSubmitted: (value) => _add(value, _label.text),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _label,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
              ),
              IconButton(
                tooltip: 'Add network',
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () => _add(_value.text, _label.text),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (you != null) _ThisDevice(check: you, onAdd: _add, onCheck: _load),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save Wi-Fi restriction',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// What the server sees for this device, to confirm the setup works.
class _ThisDevice extends StatelessWidget {
  const _ThisDevice({
    required this.check,
    required this.onAdd,
    required this.onCheck,
  });

  final NetworkCheck check;
  final void Function(String value, String label) onAdd;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final address = check.address;
    final suggestion = check.suggestedEntry;
    final warnings = [
      if (address == null)
        "The server cannot see this device's address, so the restriction "
            'would block every guest. Check Network:ClientIpSource on the '
            'server.',
      if (address != null && !check.consistent)
        'A proxy header names a different address '
            '(${check.headers.entries.map((e) => '${e.key}: ${e.value}').join('; ')}). '
            'The server may be seeing a proxy instead of each guest: do not '
            'switch the restriction on until this is fixed (see the README).',
      if (check.sharedCarrier)
        'This connection uses carrier-grade NAT, shared with other customers '
            'of the provider. It cannot identify the restaurant: ask the '
            'provider for a public address.',
      if (check.isPrivate)
        'This is a private address: fine for a test on the local network, '
            'never seen for guests of the deployed server.',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.softWhite,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                check.matches
                    ? Icons.verified_rounded
                    : Icons.help_outline_rounded,
                color: check.matches ? AppColors.success : AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This device: ${address ?? 'unknown'}',
                  style: AppTypography.cardTitle,
                ),
              ),
              TextButton(onPressed: onCheck, child: const Text('Check again')),
            ],
          ),
          Text(
            check.matches
                ? 'On an authorised network (${check.matchedBy}).'
                : 'Not on an authorised network.',
            style: AppTypography.caption,
          ),
          Text(
            'Seen by the server from its ${check.source}. Check once on the '
            'restaurant Wi-Fi and once on mobile data: the two addresses must '
            'differ.',
            style: AppTypography.caption,
          ),
          for (final warning in warnings) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    warning,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!check.matches &&
              suggestion != null &&
              !check.sharedCarrier &&
              check.consistent) ...[
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: 'Add this network ($suggestion)',
              icon: Icons.add_rounded,
              expand: false,
              height: 40,
              onPressed: () => onAdd(suggestion, 'Restaurant Wi-Fi'),
            ),
          ],
        ],
      ),
    );
  }
}
