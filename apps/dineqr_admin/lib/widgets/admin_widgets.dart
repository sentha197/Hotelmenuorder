import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/admin_session_controller.dart';

/// Neutral background for data-heavy admin screens.
const adminBackground = AppColors.softWhite;

/// Runs an admin action and turns expected failures into a snackbar.
/// Returns true when [action] completed.
Future<bool> runAdminAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (success != null && context.mounted) {
      showAppSnackBar(context, success, icon: Icons.check_circle_rounded);
    }
    return true;
  } on Object catch (error) {
    if (!context.mounted) return false;
    final message = switch (error) {
      ValidationException(:final message) => message,
      PaymentException(:final message) => message,
      final CheckoutException checkout => checkout.message,
      final PermissionDeniedException denied => denied.message,
      final SessionExpiredException expired => expired.message,
      // The API's own wording ("That photo is too large", ...) is written
      // for the user, so it is clearer than the fallback below.
      ApiException(:final message) => message,
      StateError(:final message) => message,
      _ => 'Something went wrong. Please try again.',
    };
    showAppSnackBar(context, message, icon: Icons.error_outline_rounded);
    return false;
  }
}

/// Standard admin page: title row with actions, then scrollable content
/// limited to a readable width on large screens.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 1100,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.lg,
      AppSpacing.page,
      AppSpacing.xxxl,
    ),
    this.leading,
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  final Widget? leading;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: padding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ?leading,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTypography.headline.copyWith(
                              fontSize: 22,
                            ),
                          ),
                          if (subtitle != null)
                            Text(subtitle!, style: AppTypography.bodySecondary),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
    final refresh = onRefresh;
    // A Material (not a plain coloured box) so list tiles show ink.
    return Material(
      color: adminBackground,
      child: refresh == null
          ? list
          : RefreshIndicator(
              onRefresh: refresh,
              color: AppColors.primary,
              child: list,
            ),
    );
  }
}

/// White rounded section with an optional title row.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.subtitle,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.divider),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: AppTypography.sectionTitle),
                          if (subtitle != null)
                            Text(subtitle!, style: AppTypography.caption),
                        ],
                      ),
                    ),
                    // Capped so it can never push the title out.
                    if (trailing case final trailing?)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.6,
                        ),
                        child: trailing,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Compact metric tile: label, value and an optional change indicator.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.change,
    this.accent = AppColors.primary,
    this.highlight = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? detail;

  /// Relative change versus the previous period (0.12 = +12%).
  final double? change;
  final Color accent;

  /// Brand-gradient treatment for the headline metric.
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onDark = highlight;
    final textColor = onDark ? Colors.white : AppColors.textPrimary;
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: onDark ? null : Colors.white,
        gradient: onDark ? AppColors.brandGradient : null,
        borderRadius: AppRadii.card,
        border: onDark ? null : Border.all(color: AppColors.divider),
        boxShadow: onDark
            ? [
                const BoxShadow(
                  color: AppColors.panelLip,
                  offset: Offset(0, 3),
                ),
                BoxShadow(
                  color: AppColors.deepRed.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: onDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.sm + 2),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: onDark ? Colors.white : accent,
                ),
              ),
              const Spacer(),
              if (change != null) _ChangeChip(change: change!, onDark: onDark),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.headline.copyWith(
                fontSize: 22,
                color: textColor,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.textSecondary,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: onDark ? AppColors.peach : AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
    final tap = onTap;
    return tap == null ? card : Pressable(onTap: tap, scale: 0.98, child: card);
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.change, required this.onDark});

  final double change;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = onDark
        ? Colors.white
        : (up ? AppColors.success : AppColors.error);
    final percent = (change.abs() * 100);
    final text = percent >= 999
        ? '999%+'
        : '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%';
    return Semantics(
      label: '${up ? 'Up' : 'Down'} $text versus the previous period',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : color.withValues(alpha: 0.1),
          borderRadius: AppRadii.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              text,
              style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays out metric cards in a responsive grid.
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    super.key,
    required this.children,
    this.minTileWidth = 170,
  });

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(
          2,
          5,
        );
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        // Row by row, so tiles in a row share the tallest tile's height.
        return Column(
          children: [
            for (var start = 0; start < children.length; start += columns) ...[
              if (start > 0) const SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < start + columns; i++) ...[
                      if (i > start) const SizedBox(width: gap),
                      SizedBox(
                        width: width,
                        child: i < children.length
                            ? FadeSlideIn(index: i, child: children[i])
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Horizontally scrolling single-choice filter chips.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.countOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final int Function(T value)? countOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final value in values) ...[
            _FilterChip(
              label: labelOf(value),
              count: countOf?.call(value),
              selected: value == selected,
              onTap: () => onSelected(value),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.95,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.charcoal : Colors.white,
            borderRadius: AppRadii.pill,
            border: Border.all(
              color: selected ? AppColors.charcoal : AppColors.border,
            ),
          ),
          child: Text(
            count == null ? label : '$label ($count)',
            style: AppTypography.label.copyWith(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact search box for admin lists.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Empty/unauthorised placeholder inside admin pages.
class AdminEmpty extends StatelessWidget {
  const AdminEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        ],
      ),
    );
  }
}

/// Shown when a module or action is not part of the staff member's role.
class PermissionNotice extends StatelessWidget {
  const PermissionNotice({super.key, required this.permission});

  final Permission permission;

  @override
  Widget build(BuildContext context) {
    final role = context.read<AdminSessionController>().actor?.role;
    return AdminEmpty(
      icon: Icons.lock_outline_rounded,
      title: 'Not available for your role',
      message:
          '${role?.label ?? 'Your role'} cannot ${permission.label.toLowerCase()}. '
          'Ask the restaurant owner if you need access.',
    );
  }
}

/// Banner reminding staff that the dashboard is running on demo data.
class DemoDataBanner extends StatelessWidget {
  const DemoDataBanner({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text ??
                  'Demo mode: sample data and simulated payments. Nothing here '
                      'moves real money.',
              style: AppTypography.caption.copyWith(color: AppColors.info),
            ),
          ),
          const DemoTag(),
        ],
      ),
    );
  }
}

/// Label / value pair used in detail panels.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: AppTypography.bodySecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a free-text reason (cancellations, refunds, adjustments).
Future<String?> askForText(
  BuildContext context, {
  required String title,
  required String label,
  String confirmLabel = 'Confirm',
  String? message,
  int minLength = 3,
  int maxLength = 120,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final valid = controller.text.trim().length >= minLength;
        return AlertDialog(
          title: Text(title, style: AppTypography.sectionTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[
                Text(message, style: AppTypography.bodySecondary),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: maxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: label),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(context, controller.text.trim())
                  : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  ).whenComplete(controller.dispose);
}

/// `₹1,250` with a sign for changes.
String signedMoney(Money value) =>
    '${value.paise < 0 ? '−' : ''}${CurrencyFormatter.format(Money(value.paise.abs()))}';

/// Wraps a pushed admin page: closes it when the session ends and shows a
/// notice instead of the page when the role lacks [permission].
class AdminGuard extends StatelessWidget {
  const AdminGuard({super.key, required this.child, this.permission});

  final Widget child;
  final Permission? permission;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    if (admin.actor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(
          context,
        ).popUntil((route) => route.settings.name == '/admin' || route.isFirst);
      });
      return const Scaffold(backgroundColor: adminBackground);
    }
    final needed = permission;
    if (needed != null && !admin.can(needed)) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: PermissionNotice(permission: needed),
      );
    }
    return child;
  }
}

/// Pushes an admin detail page guarded by [AdminGuard].
Future<T?> pushAdminPage<T>(
  BuildContext context,
  Widget page, {
  Permission? permission,
}) => Navigator.of(context).push<T>(
  MaterialPageRoute<T>(
    builder: (_) => AdminGuard(permission: permission, child: page),
  ),
);
