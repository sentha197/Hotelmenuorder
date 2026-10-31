import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Covers the whole app (menu, cart, checkout and payments) while the
/// restaurant's Wi-Fi restriction applies and the server has not confirmed
/// the guest is on its network. The server refuses those actions anyway;
/// this says why, and opens again by itself once a check passes.
class DineInLock extends StatelessWidget {
  const DineInLock({super.key, required this.child, required this.onScanOther});

  final Widget child;

  /// Leaves the session for the scanner (e.g. to order takeaway instead).
  final VoidCallback onScanOther;

  @override
  Widget build(BuildContext context) {
    final locked = context.select<DineInAccessController, bool>(
      (access) => access.isLocked,
    );
    return Stack(
      children: [
        // Hidden from assistive technology and taps while locked.
        ExcludeSemantics(
          excluding: locked,
          child: AbsorbPointer(absorbing: locked, child: child),
        ),
        if (locked)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: SafeArea(child: DineInLockPanel(onScanOther: onScanOther)),
            ),
          ),
      ],
    );
  }
}

/// Why dine-in is locked, which Wi-Fi to join, and a way to check again.
class DineInLockPanel extends StatelessWidget {
  const DineInLockPanel({super.key, this.onScanOther, this.onRetry});

  final VoidCallback? onScanOther;

  /// Defaults to asking the server again.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final access = context.watch<DineInAccessController>();
    final ssid = access.ssid;
    final status = access.isChecking
        ? 'Checking your connection…'
        : access.isOffline
        ? 'Your phone is not connected to any network.'
        : access.state == DineInAccess.checking
        ? 'Checking that you are on the restaurant Wi-Fi…'
        : 'You seem to be on mobile data or another Wi-Fi network.';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  access.isChecking
                      ? Icons.wifi_find_rounded
                      : Icons.wifi_off_rounded,
                  size: 42,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Connect to the restaurant Wi-Fi',
                textAlign: TextAlign.center,
                style: AppTypography.screenTitle,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                DineInWifi.blockedMessage,
                textAlign: TextAlign.center,
                style: AppTypography.body,
              ),
              if (ssid.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.softWhite,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          'Wi-Fi: $ssid',
                          style: AppTypography.cardTitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                status,
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                isLoading: access.isChecking,
                onPressed: access.isChecking
                    ? null
                    : () => (onRetry ?? access.verify)(),
              ),
              if (onScanOther != null) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: onScanOther,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text('Scan a different code'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
