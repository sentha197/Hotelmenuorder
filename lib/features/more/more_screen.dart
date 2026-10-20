import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/motion.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/brand/brand_surfaces.dart';
import '../../core/brand/dineqr_logo.dart';
import '../../state/cart_controller.dart';
import '../../state/catalog_controller.dart';
import '../../state/order_controller.dart';
import '../../state/session_controller.dart';
import '../../state/shell_controller.dart';
import '../qr_scanner/demo_qr_sheet.dart';

/// "More" tab: table session, favourites, demo tools and credits.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _resetDemo(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset demo data?',
      message:
          'This clears your cart, favorites, ratings and the orders placed on '
          'this device. Your table stays selected.',
      confirmLabel: 'Reset',
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed || !context.mounted) return;
    context.read<CartController>().clear();
    await context.read<CatalogController>().clearFavorites();
    if (!context.mounted) return;
    await context.read<OrderController>().resetDemo();
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Demo data has been reset',
        icon: Icons.check_rounded,
      );
    }
  }

  void _showAbout(BuildContext context) {
    showBrandSheet<void>(
      context,
      builder: (context) => SafeArea(
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
              const SizedBox(height: AppSpacing.sm),
              Text('Version 1.0.0 · Demo build', style: AppTypography.caption),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'A QR-based restaurant ordering demo. The menu, orders, kitchen '
                'updates and ratings are simulated and stored only on this '
                'device. No payments are taken and no real restaurant is '
                'contacted.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Got it',
                onPressed: () => Navigator.pop(context),
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
    final shell = context.read<ShellController>();

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
        icon: Icons.qr_code_2_rounded,
        title: 'Demo QR Codes',
        subtitle: 'Scan them from another phone to test the camera',
        onTap: () => showDemoQrSheet(context),
      ),
      _MoreTile(
        icon: Icons.restart_alt_rounded,
        title: 'Reset Demo Data',
        subtitle: 'Clear cart, favorites and orders',
        onTap: () => _resetDemo(context),
      ),
      _MoreTile(
        icon: Icons.photo_library_outlined,
        title: 'Photo Credits',
        subtitle: 'Licenses for the food photography',
        onTap: () => Navigator.of(context).pushNamed(Routes.credits),
      ),
      _MoreTile(
        icon: Icons.info_outline_rounded,
        title: 'About this demo',
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
          FadeSlideIn(child: _SessionCard(table: session.tableNumber)),
          const SizedBox(height: AppSpacing.xl),
          for (final (index, tile) in tiles.indexed)
            FadeSlideIn(index: index + 1, child: tile),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.table});

  final int? table;

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
                    table == null
                        ? 'No table selected'
                        : 'Dining at Table ${AppFormat.table(table!)}',
                    style: AppTypography.sectionTitle.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'DineQR · Demo restaurant',
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
                            table == null ? 'Scan table QR' : 'Change table',
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
