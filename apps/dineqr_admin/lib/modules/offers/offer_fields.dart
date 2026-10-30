import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Where an offer stands today: Live, Scheduled, Ended, Paused or Used up.
class OfferStatusChip extends StatelessWidget {
  const OfferStatusChip(this.status, {super.key});

  final OfferStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (status) {
      OfferStatus.live => (AppColors.success, AppColors.successSoft),
      OfferStatus.scheduled => (AppColors.info, AppColors.infoSoft),
      OfferStatus.paused => (AppColors.warning, AppColors.warningSoft),
      OfferStatus.usedUp => (AppColors.primary, AppColors.primarySoft),
      OfferStatus.ended => (AppColors.textSecondary, AppColors.softWhite),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.label,
        style: AppTypography.overline.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

/// `Used 12 of 50` or `Used 12 times`.
String usageText(int used, int? limit) => limit == null
    ? 'Used $used ${used == 1 ? 'time' : 'times'}'
    : 'Used $used of $limit';

/// The first and last day an offer runs (restaurant days, both included);
/// either may be left open.
class OfferDatesField extends StatelessWidget {
  const OfferDatesField({
    super.key,
    required this.startsOn,
    required this.endsOn,
    required this.onChanged,
  });

  final DateTime? startsOn;
  final DateTime? endsOn;
  final void Function(DateTime? startsOn, DateTime? endsOn) onChanged;

  Future<DateTime?> _pick(BuildContext context, DateTime? current) async {
    final today = OfferRules.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    return picked == null ? null : OfferRules.asDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    Widget day({
      required String label,
      required DateTime? value,
      required String open,
      required ValueChanged<DateTime?> onPicked,
    }) => Expanded(
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.event_rounded)
              : IconButton(
                  tooltip: 'Clear $label',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onPicked(null),
                ),
        ),
        child: InkWell(
          onTap: () async {
            final picked = await _pick(context, value);
            if (picked != null) onPicked(picked);
          },
          child: Text(
            value == null ? open : AppFormat.day(value),
            style: AppTypography.body.copyWith(
              color: value == null ? AppColors.textMuted : null,
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        day(
          label: 'First day',
          value: startsOn,
          open: 'From now',
          onPicked: (value) => onChanged(value, endsOn),
        ),
        const SizedBox(width: AppSpacing.md),
        day(
          label: 'Last day',
          value: endsOn,
          open: 'No end date',
          onPicked: (value) => onChanged(startsOn, value),
        ),
      ],
    );
  }
}

/// How many orders may use an offer; empty for no limit.
class UsageLimitField extends StatelessWidget {
  const UsageLimitField({super.key, required this.controller, this.used = 0});

  final TextEditingController controller;

  /// Orders that used it so far (shown as help).
  final int used;

  /// The limit typed into [controller]: null for none, -1 when it is not a
  /// whole number.
  static int? parse(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text) ?? -1;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Usage limit (optional)',
        suffixText: 'orders',
        helperText: used == 0
            ? 'Each order that saves with it counts once. Cancelled orders '
                  'give their use back.'
            : '${usageText(used, null)} so far. Cancelled orders give their '
                  'use back.',
      ),
    );
  }
}
