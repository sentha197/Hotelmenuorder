import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Covers the app while the restaurant's GPS ordering area applies and the
/// server has not confirmed the guest is inside it. Separate from the
/// Wi-Fi lock ([DineInLock]); the server refuses orders from outside
/// anyway, this says why and opens again once a check passes.
class LocationLock extends StatelessWidget {
  const LocationLock({
    super.key,
    required this.child,
    required this.onScanOther,
  });

  final Widget child;

  /// Leaves the session for the scanner.
  final VoidCallback onScanOther;

  @override
  Widget build(BuildContext context) {
    final locked = context.select<LocationAccessController, bool>(
      (access) => access.isLocked,
    );
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: AbsorbPointer(absorbing: locked, child: child),
        ),
        if (locked)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: SafeArea(
                child: LocationLockPanel(onScanOther: onScanOther),
              ),
            ),
          ),
      ],
    );
  }
}

/// Why ordering is locked (outside the area, no permission, GPS off) and
/// what to do about it.
class LocationLockPanel extends StatelessWidget {
  const LocationLockPanel({super.key, this.onScanOther});

  final VoidCallback? onScanOther;

  @override
  Widget build(BuildContext context) {
    final access = context.watch<LocationAccessController>();
    final state = access.state;
    final (icon, title) = switch (state) {
      LocationAccess.checking => (
        Icons.my_location_rounded,
        'Checking your location',
      ),
      LocationAccess.outside => (
        Icons.wrong_location_rounded,
        'You are too far from the restaurant',
      ),
      LocationAccess.permissionDenied ||
      LocationAccess.permissionDeniedForever => (
        Icons.location_disabled_rounded,
        'Allow location to order',
      ),
      LocationAccess.serviceDisabled => (
        Icons.location_off_rounded,
        'Turn on location',
      ),
      _ => (Icons.location_searching_rounded, 'Location needed to order'),
    };
    final message = state == LocationAccess.checking
        ? 'This restaurant takes orders only from guests at the restaurant. '
              'Allow DineQR to use your location when asked.'
        : access.explanation;
    final settings =
        state == LocationAccess.permissionDeniedForever ||
        state == LocationAccess.serviceDisabled;
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
                child: Icon(icon, size: 42, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.screenTitle,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.body,
              ),
              if (access.radius > 0) ...[
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
                        Icons.radar_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          'Ordering within ${access.radius} m of the restaurant',
                          style: AppTypography.cardTitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (settings) ...[
                PrimaryButton(
                  label: state == LocationAccess.serviceDisabled
                      ? 'Open location settings'
                      : 'Open app settings',
                  icon: Icons.settings_rounded,
                  onPressed: access.openSettings,
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  onPressed: access.isChecking ? null : access.verify,
                ),
              ] else
                PrimaryButton(
                  label: state == LocationAccess.permissionDenied
                      ? 'Allow location'
                      : 'Try again',
                  icon: Icons.refresh_rounded,
                  isLoading: access.isChecking,
                  onPressed: access.isChecking ? null : access.verify,
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
