import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Screen 12: "Rate Your Experience" bottom sheet for a served order.
Future<void> showFeedbackSheet(BuildContext context, String orderId) {
  return showBrandSheet<void>(
    context,
    showDragHandle: false,
    builder: (_) => FeedbackSheet(orderId: orderId),
  );
}

class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, required this.orderId});

  final String orderId;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;
  int _errorCount = 0;

  static const _labels = [
    '',
    'Poor',
    'Could be better',
    'Good',
    'Great',
    'Loved it!',
  ];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _setRating(int value) {
    HapticFeedback.selectionClick();
    setState(() {
      _rating = value;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || _submitted) return;
    final validation = OrderFeedback.validate(
      rating: _rating,
      comment: _comment.text,
    );
    if (validation != null) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = validation.message;
        _errorCount++;
      });
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<OrderController>().submitFeedback(
        widget.orderId,
        rating: _rating,
        comment: _comment.text,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _submitted = true);
    } on FeedbackException catch (exception) {
      if (mounted) setState(() => _error = exception.error.message);
    } on StateError {
      if (mounted) {
        setState(() => _error = 'This order has already been rated.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = context.select<OrderController, RestaurantOrder?>(
      (orders) => orders.byId(widget.orderId),
    );
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.md,
          AppSpacing.xxl,
          AppSpacing.xl,
        ),
        child: AnimatedSize(
          duration: Motion.of(context, Motion.medium),
          curve: Motion.standard,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            child: _submitted
                ? _SuccessView(key: const ValueKey('done'), rating: _rating)
                : order == null
                ? const SizedBox(height: 120)
                : order.feedback != null
                ? _SuccessView(
                    key: const ValueKey('existing'),
                    rating: order.feedback!.rating,
                    alreadyRated: true,
                  )
                : _buildForm(order),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(RestaurantOrder order) {
    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Text(
                'Rate Your Experience',
                textAlign: TextAlign.center,
                style: AppTypography.screenTitle,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              gradient: AppColors.emberGradient,
              borderRadius: BorderRadius.circular(AppRadii.lg + 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FoodImage(
              order.previewImage,
              width: 132,
              height: 108,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'How was your food?',
          style: AppTypography.sectionTitle.copyWith(fontSize: 17),
        ),
        const SizedBox(height: 2),
        Text(
          'Order ${AppFormat.orderNumber(order.id)} · ${order.tableLabel}',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.lg),
        ShakeOnChange(
          trigger: _errorCount,
          child: AnimatedStarRating(value: _rating, onChanged: _setRating),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 20,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: Text(
              _error ?? _labels[_rating],
              key: ValueKey(_error ?? _rating),
              style: AppTypography.label.copyWith(
                color: _error != null ? AppColors.error : AppColors.orangeText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _comment,
          minLines: 3,
          maxLines: 5,
          maxLength: OrderFeedback.maxCommentLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Share your feedback (optional)',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(
          label: 'Submit',
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppTypography.label.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Skip'),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    super.key,
    required this.rating,
    this.alreadyRated = false,
  });

  final int rating;
  final bool alreadyRated;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        SuccessEmblem(
          size: 84,
          burst: !alreadyRated,
          semanticLabel: alreadyRated ? 'Already rated' : 'Feedback sent',
        ),
        Text(
          alreadyRated ? 'Already rated' : 'Thank you!',
          style: AppTypography.headline,
        ),
        const SizedBox(height: AppSpacing.sm),
        FadeSlideIn(index: 2, child: StarRow(rating: rating, size: 28)),
        const SizedBox(height: AppSpacing.sm),
        FadeSlideIn(
          index: 3,
          child: Text(
            'Your rating is saved with this order on this device.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
