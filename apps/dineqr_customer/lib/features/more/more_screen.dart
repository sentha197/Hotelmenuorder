import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../state/session_controller.dart';
import '../../state/shell_controller.dart';
import '../qr_scanner/demo_qr_sheet.dart';

/// "More" tab: table session, favourites, bills, demo tools and credits.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _resetDemo(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset demo data?',
      message:
          'This clears your cart, favorites and ratings, and restores the '
          'sample orders and bills on this device. Your table stays selected.',
      confirmLabel: 'Reset',
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await context.read<DemoData>().resetGuestData();
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Demo data has been reset',
        icon: Icons.check_rounded,
      );
    }
  }

  void _showAbout(BuildContext context) {
    final demo = context.read<AppConfig>().demoMode;
    showBrandSheet<void>(
      context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DineQrMark(size: 110),
              const SizedBox(height: AppSpacing.sm),
              const DineQrWordmark(fontSize: 30),
              const SizedBox(height: 4),
              const DineQrTagline(fontSize: 10.5),
              // Staff use the separate DineQR Admin app; this app has no
              // staff entry of any kind.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  demo ? 'Version 1.1.0 · Demo build' : 'Version 1.1.0',
                  style: AppTypography.caption,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                demo
                    ? 'A QR-based restaurant ordering demo. The menu, orders, '
                          'kitchen updates, bills and ratings are stored only on '
                          'this device. Payments are simulated: no money is '
                          'charged and no real restaurant is contacted.'
                    : 'Scan the QR code on your table to browse the menu, '
                          'order and pay your bill.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Got it',
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final favorites = context.select<CatalogController, int>(
      (catalog) => catalog.favorites.length,
    );
    final orders = context.watch<OrderController>();
    final bills = context.watch<BillingController>().forOrders(
      orders.guestOrders,
    );
    final due = Money.sum(bills.map((bill) => bill.outstanding));
    final restaurant = context.select<SettingsController, String>(
      (settings) => settings.settings.name,
    );
    final shell = context.read<ShellController>();
    final demo = context.read<AppConfig>().demoMode;

    final tiles = <Widget>[
      _MoreTile(
        icon: Icons.favorite_rounded,
        title: 'My Favorites',
        subtitle: favorites == 0
            ? 'Tap the heart on a dish to save it'
            : '$favorites saved ${favorites == 1 ? 'dish' : 'dishes'}',
        onTap: () => AppNav.openMenu(context, favoritesOnly: true),
      ),
      _MoreTile(
        icon: Icons.receipt_long_rounded,
        title: 'My Orders',
        subtitle:
            '${orders.currentOrders.length} active · ${orders.pastOrders.length} past',
        onTap: () => shell.select(ShellTab.orders),
      ),
      _MoreTile(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Bills & Payments',
        subtitle: bills.isEmpty
            ? 'Your bills and receipts appear here'
            : due.isZero
            ? '${bills.length} ${bills.length == 1 ? 'bill' : 'bills'} · '
                  'nothing due'
            : '${CurrencyFormatter.format(due)} due across your bills',
        onTap: () => AppNav.openPayments(context),
      ),
      if (demo) ...[
        _MoreTile(
          icon: Icons.qr_code_2_rounded,
          title: 'Demo QR Codes',
          subtitle: 'Scan them from another phone to test the camera',
          onTap: () => showDemoQrSheet(context),
        ),
        _MoreTile(
          icon: Icons.restart_alt_rounded,
          title: 'Reset Demo Data',
          subtitle: 'Clear cart and favorites, restore sample orders',
          onTap: () => _resetDemo(context),
        ),
      ],
      _MoreTile(
        icon: Icons.photo_library_outlined,
        title: 'Photo Credits',
        subtitle: 'Licenses for the food photography',
        onTap: () => Navigator.of(context).pushNamed(Routes.credits),
      ),
      _MoreTile(
        icon: Icons.info_outline_rounded,
        title: demo ? 'About this demo' : 'About DineQR',
        subtitle: 'How this app works',
        onTap: () => _showAbout(context),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: () => shell.select(ShellTab.home)),
        title: const Text('More'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xxl,
        ),
        children: [
          FadeSlideIn(
            child: _SessionCard(
              table: session.tableNumber,
              restaurant: restaurant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final (index, tile) in tiles.indexed)
            FadeSlideIn(index: index + 1, child: tile),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.table, required this.restaurant});

  final int? table;
  final String restaurant;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.glow(AppColors.deepRed),
      ),
      child: BrandPanel(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: [
            const DineQrMark(size: 72, tone: DineQrTone.inverted),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    switch (table) {
                      null => 'No table selected',
                      final number when OrderTables.isTakeaway(number) =>
                        'Takeaway order',
                      final number =>
                        'Dining at Table ${AppFormat.table(number)}',
                    },
                    style: AppTypography.sectionTitle.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    restaurant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Pressable(
                    onTap: () => Navigator.of(context).pushNamed(Routes.scan),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppRadii.pill,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            switch (table) {
                              null => 'Scan table QR',
                              final number
                                  when OrderTables.isTakeaway(number) =>
                                'Switch to a table',
                              _ => 'Change table',
                            },
                            style: AppTypography.label.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.cardTitle),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
