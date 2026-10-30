import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../shell/admin_modules.dart';
import '../../widgets/admin_widgets.dart';
import 'payment_settings_card.dart';
import 'wifi_restriction_card.dart';

/// Restaurant configuration (owner only).
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  late final SettingsController _controller = context
      .read<SettingsController>();
  late RestaurantSettings _draft = _controller.settings;
  late final _name = TextEditingController(text: _draft.name);
  late final _phone = TextEditingController(text: _draft.phone);
  late final _email = TextEditingController(text: _draft.email);
  late final _address = TextEditingController(text: _draft.address);
  late final _taxReg = TextEditingController(text: _draft.taxRegistration);
  late final _taxName = TextEditingController(text: _draft.taxName);
  late final _taxRate = TextEditingController(
    text: _percent(_draft.taxRateBasisPoints),
  );
  late final _service = TextEditingController(
    text: _percent(_draft.serviceChargeBasisPoints),
  );
  late final _footer = TextEditingController(text: _draft.receiptFooter);
  late final _buffer = TextEditingController(
    text: '${_draft.prepBufferMinutes}',
  );
  bool _saving = false;

  static String _percent(int bp) =>
      PricingConfig.formatRate(bp).replaceAll('%', '');

  /// Offsets from UTC−12:00 to UTC+14:00 in half hours, plus +05:45.
  static final List<int> _offsets = [
    for (var m = -720; m <= 840; m += 30) m,
    345,
  ]..sort();

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _email,
      _address,
      _taxReg,
      _taxName,
      _taxRate,
      _service,
      _footer,
      _buffer,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final tax = SettingsController.parsePercent(_taxRate.text);
    final service = SettingsController.parsePercent(
      _service.text.trim().isEmpty ? '0' : _service.text,
    );
    final buffer = int.tryParse(_buffer.text.trim());
    if (tax == null || service == null || buffer == null) {
      await runAdminAction(
        context,
        () async => throw const ValidationException(
          'Check the tax rate, service charge and preparation buffer.',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    await runAdminAction(
      context,
      () => _controller.updateSettings(
        _draft.copyWith(
          name: _name.text,
          phone: _phone.text,
          email: _email.text,
          address: _address.text,
          taxRegistration: _taxReg.text,
          taxName: _taxName.text,
          taxRateBasisPoints: tax,
          serviceChargeBasisPoints: service,
          receiptFooter: _footer.text,
          prepBufferMinutes: buffer,
          // Offers are saved separately; keep the latest list.
          offers: _controller.settings.offers,
        ),
      ),
      success: 'Settings saved',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _draft = _controller.settings;
    });
  }

  Future<void> _resetDemo() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset all demo data?',
      message:
          'Restores the sample menu, settings, tables, staff, stock, orders '
          'and bills, and clears the activity log. You will be signed out.',
      confirmLabel: 'Reset',
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed || !mounted) return;
    await runAdminAction(
      context,
      () => context.read<DemoData>().resetEverything(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the settings change (e.g. saved on another device).
    context.watch<SettingsController>();
    final billing = context.watch<BillingController>();
    final printer = context.read<ThermalPrinter>();
    final demo = context.read<AppConfig>().demoMode;
    final demoPayments = _draft.paymentMode == PaymentMode.demo;
    final supported = demoPayments
        ? PaymentMethodType.online.toSet()
        : billing.liveMethods;
    return AdminPage(
      title: 'Settings',
      subtitle: 'Changes apply to new orders and bills',
      maxWidth: 820,
      children: [
        SectionCard(
          title: 'Restaurant',
          subtitle:
              'Contact details and the tax registration are printed on bills '
              'only when filled in.',
          child: Column(
            children: [
              TextField(
                controller: _name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Restaurant name'),
              ),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _address,
                maxLength: 160,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                ),
              ),
              TextField(
                controller: _taxReg,
                maxLength: 20,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Tax registration number (optional)',
                  helperText: 'e.g. your GSTIN. Leave empty if not registered.',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Taxes & charges',
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taxName,
                      maxLength: 20,
                      decoration: const InputDecoration(labelText: 'Tax name'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _taxRate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tax rate',
                        suffixText: '%',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _service,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Service charge (0 for none)',
                  suffixText: '%',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _draft.currencyCode,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  helperText:
                      'Fixed once the first bill exists, so earlier bills '
                      'keep their currency.',
                  helperMaxLines: 2,
                ),
                items: [
                  for (final currency in CurrencyFormatter.supported)
                    DropdownMenuItem(
                      value: currency.code,
                      child: Text(currency.label),
                    ),
                ],
                onChanged: (code) => setState(
                  () => _draft = _draft.copyWith(currencyCode: code),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Has its own Save button: it changes where guests' money goes, so
        // it is not part of the page-wide "Save settings" below.
        const PaymentSettingsCard(),
        const SizedBox(height: AppSpacing.lg),
        // Also saved on its own: it decides who can order at a table.
        const WifiRestrictionCard(),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Payments',
          subtitle: demoPayments
              ? 'Demo mode: online payments are simulated, and every payment '
                    '(counter ones too) is labelled DEMO. No money moves.'
              : 'Live mode: online payments go through '
                    '${billing.liveAvailable ? billing.gateway.providerName : 'the payment gateway'}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PaymentMode>(
                segments: [
                  const ButtonSegment(
                    value: PaymentMode.demo,
                    label: Text('Demo'),
                    icon: Icon(Icons.science_outlined),
                  ),
                  ButtonSegment(
                    value: PaymentMode.live,
                    label: const Text('Live'),
                    icon: const Icon(Icons.verified_outlined),
                    // Never without a verified gateway on the server.
                    enabled: billing.liveAvailable,
                  ),
                ],
                selected: {_draft.paymentMode},
                showSelectedIcon: false,
                onSelectionChanged: (mode) => setState(
                  () => _draft = _draft.copyWith(paymentMode: mode.first),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                billing.liveAvailable
                    ? 'Live payments are verified by '
                          '${billing.gateway.providerName}.'
                    : 'Live is unavailable: no verified payment gateway is '
                          'configured on the server, so the restaurant stays '
                          'in demo mode.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final method in PaymentMethodType.online)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _draft.onlineMethods.contains(method),
                  onChanged: supported.contains(method)
                      ? (on) => setState(() {
                          final methods = {..._draft.onlineMethods};
                          if (on ?? false) {
                            methods.add(method);
                          } else {
                            methods.remove(method);
                          }
                          _draft = _draft.copyWith(onlineMethods: methods);
                        })
                      : null,
                  title: Text(
                    method == PaymentMethodType.upi
                        ? 'UPI and QR Payment'
                        : method.label,
                    style: AppTypography.cardTitle,
                  ),
                  subtitle: !supported.contains(method)
                      ? Text(
                          'Not supported by the connected provider',
                          style: AppTypography.caption,
                        )
                      : method == PaymentMethodType.upi &&
                            _draft.currencyCode != 'INR'
                      ? Text(
                          'Offered only for bills in Indian rupees',
                          style: AppTypography.caption,
                        )
                      : null,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.allowPartialPayments,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(allowPartialPayments: v),
                ),
                title: Text(
                  'Allow part payments',
                  style: AppTypography.cardTitle,
                ),
                subtitle: Text(
                  'Guests may pay part of a bill online and the rest later, '
                  'or split it across methods. Cash and paying at the '
                  'counter are always offered.',
                  style: AppTypography.caption,
                ),
              ),
              InfoRow('Receipt printer', printer.description),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Time zone & receipts',
          child: Column(
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _offsets.contains(_draft.utcOffsetMinutes)
                    ? _draft.utcOffsetMinutes
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Restaurant time zone',
                  helperText: 'Used for bills, reports and "today".',
                ),
                items: [
                  for (final m in _offsets)
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                        '${RestaurantSettings.formatOffset(m)}'
                        '${m == 330 ? ' · India' : ''}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(
                    utcOffsetMinutes: value ?? _draft.utcOffsetMinutes,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _footer,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Note on receipts',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Menu & stock',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.showSoldOutDishes,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(showSoldOutDishes: v),
                ),
                title: Text(
                  'Show sold-out dishes',
                  style: AppTypography.cardTitle,
                ),
                subtitle: Text(
                  'Off hides them from guests instead of greying them out.',
                  style: AppTypography.caption,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.autoUnavailableWhenOutOfStock,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(
                    autoUnavailableWhenOutOfStock: v,
                  ),
                ),
                title: Text(
                  'Sold out when stock runs out',
                  style: AppTypography.cardTitle,
                ),
                subtitle: Text(
                  'Dishes linked to an inventory item follow its stock.',
                  style: AppTypography.caption,
                ),
              ),
              TextField(
                controller: _buffer,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Preparation buffer',
                  suffixText: 'min',
                  helperText: 'Added to the longest dish time for estimates.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Save settings',
          icon: Icons.check_rounded,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: AppSpacing.xxl),
        SectionCard(
          title: 'Offers',
          subtitle:
              'Coupons, special offers and combos have their own section.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              label: 'Open Offers',
              icon: Icons.local_offer_outlined,
              expand: false,
              height: 42,
              onPressed: () =>
                  context.read<AdminShellController>().open(AdminModule.offers),
            ),
          ),
        ),
        if (demo) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Demo data',
            subtitle: 'Only in the offline demo build.',
            child: SecondaryButton(
              label: 'Reset all demo data',
              icon: Icons.restart_alt_rounded,
              onPressed: _resetDemo,
            ),
          ),
        ],
      ],
    );
  }
}
