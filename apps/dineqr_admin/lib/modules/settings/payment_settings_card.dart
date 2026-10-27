import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';

/// Lets the owner choose a QR picture from the gallery: the picture's bytes,
/// or null when nothing was chosen. Replaceable so the card can be tested
/// without a phone.
typedef QrImagePicker = Future<Uint8List?> Function();

/// The device gallery. Not downscaled: shrinking a QR code can make it
/// unreadable, and the server caps the size anyway.
Future<Uint8List?> pickQrFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked?.readAsBytes();
}

/// Payment settings: UPI payments straight into the restaurant's own
/// account, with no payment gateway. Saved separately from the rest of the
/// page, because it changes where guests' money goes.
class PaymentSettingsCard extends StatefulWidget {
  const PaymentSettingsCard({super.key, this.picker = pickQrFromGallery});

  final QrImagePicker picker;

  @override
  State<PaymentSettingsCard> createState() => _PaymentSettingsCardState();
}

class _PaymentSettingsCardState extends State<PaymentSettingsCard> {
  late final PaymentSettingsController _controller = context
      .read<PaymentSettingsController>();

  /// What the server last told us; the form is "unsaved" when it differs.
  late UpiSettings _base = _controller.upi;
  late UpiSettings _draft = _controller.upi;
  late final _upiId = TextEditingController(text: _draft.upiId);
  late final _name = TextEditingController(text: _draft.payeeName);

  bool _saving = false;
  bool _uploading = false;

  /// Field errors appear once a save has been tried, then stay live.
  bool _submitted = false;
  String? _qrError;
  String? _loadError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    if (_controller.isAvailable && !_controller.isLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _upiId.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The details as typed: the ID trimmed and lower-cased, as it is saved.
  UpiSettings _collect() => _draft.copyWith(
    upiId: UpiSettings.normalizeId(_upiId.text),
    payeeName: _name.text.trim(),
  );

  bool get _dirty => _collect() != _base;

  void _adopt(UpiSettings saved) {
    setState(() {
      _base = saved;
      _draft = saved;
      _upiId.text = saved.upiId;
      _name.text = saved.payeeName;
      _submitted = false;
      _qrError = null;
    });
  }

  /// A fresh copy arrived from the server (live update, another device):
  /// take it unless the owner is in the middle of an edit.
  void _onController() {
    if (!mounted) return;
    final saved = _controller.upi;
    final editing = _dirty;
    if (editing) {
      setState(() => _base = saved);
    } else {
      _adopt(saved);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _controller.load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _loadError = switch (error) {
          ApiException(:final message) => message,
          SessionExpiredException(:final message) => message,
          ValidationException(:final message) => message,
          _ => 'The payment settings could not be loaded.',
        },
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickQr() async {
    setState(() {
      _uploading = true;
      _qrError = null;
    });
    try {
      final bytes = await widget.picker();
      if (bytes == null) return; // Cancelled.
      final url = await _controller.uploadQr(bytes);
      if (mounted) setState(() => _draft = _draft.copyWith(qrImageUrl: url));
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _qrError = switch (error) {
          ValidationException(:final message) => message,
          ApiException(:final message) => message,
          PermissionDeniedException(:final message) => message,
          SessionExpiredException(:final message) => message,
          _ => 'The QR image could not be uploaded. Please try again.',
        },
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final next = _collect();
    setState(() {
      _submitted = true;
      _saving = true;
    });
    final saved = await runAdminAction(
      context,
      () => _controller.save(next),
      success: 'Payment settings saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) _adopt(_controller.upi);
  }

  void _chooseMode(UpiVerificationMode mode) {
    if (mode == UpiVerificationMode.automatic &&
        !_controller.automaticVerificationAvailable) {
      // Not selectable here: the explanation below is already on screen.
      showAppSnackBar(
        context,
        PaymentSettingsController.automaticUnavailableMessage,
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    setState(() => _draft = _draft.copyWith(verificationMode: mode));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PaymentSettingsController>();
    final available = controller.isAvailable;
    return SectionCard(
      title: 'Payment Settings',
      subtitle: 'Take UPI payments straight into your own account.',
      trailing: available && controller.isLoaded
          ? _StatusPill(active: _base.isReady, unsaved: _dirty)
          : null,
      child: !available
          ? const _Unavailable()
          : _loading && !controller.isLoaded
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          : !controller.isLoaded
          ? _LoadFailed(message: _loadError, onRetry: _load)
          : _form(controller),
    );
  }

  Widget _form(PaymentSettingsController controller) {
    final problems = _submitted ? _collect().problems : null;
    final busy = _saving || _uploading;
    final automaticAvailable = controller.automaticVerificationAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('upi-enabled'),
          contentPadding: EdgeInsets.zero,
          value: _draft.enabled,
          activeThumbColor: AppColors.primary,
          onChanged: busy
              ? null
              : (on) => setState(() => _draft = _draft.copyWith(enabled: on)),
          title: Text('Enable UPI Payments', style: AppTypography.cardTitle),
          subtitle: Text(
            'Guests can pay their bill by UPI, straight to your account.',
            style: AppTypography.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('upi-id'),
          controller: _upiId,
          enabled: !busy,
          maxLength: 100,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.emailAddress,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Restaurant UPI ID',
            hintText: 'name@bank',
            helperText: 'The account guests pay. Check it carefully.',
            helperMaxLines: 2,
            counterText: '',
            errorText: problems?.upiId,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('upi-name'),
          controller: _name,
          enabled: !busy,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Merchant / Account Name',
            helperText: 'Shown to guests in their UPI app when they pay.',
            helperMaxLines: 2,
            counterText: '',
            errorText: problems?.payeeName,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('UPI QR code', style: AppTypography.cardTitle),
        const SizedBox(height: 2),
        Text(
          'Optional. Your own merchant QR, shown to guests as a backup. The '
          'QR guests scan to pay is made from your UPI ID with the exact '
          'amount.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        _QrPreview(url: _draft.qrImageUrl, busy: _uploading),
        const SizedBox(height: AppSpacing.md),
        if (controller.canUploadQr)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SecondaryButton(
                key: const ValueKey('upi-qr-upload'),
                label: _draft.hasQrImage ? 'Replace' : 'Upload QR image',
                icon: Icons.upload_rounded,
                expand: false,
                height: 42,
                onPressed: busy ? null : _pickQr,
              ),
              if (_draft.hasQrImage)
                SecondaryButton(
                  key: const ValueKey('upi-qr-remove'),
                  label: 'Remove',
                  icon: Icons.delete_outline_rounded,
                  expand: false,
                  height: 42,
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          _qrError = null;
                          _draft = _draft.copyWith(qrImageUrl: '');
                        }),
                ),
            ],
          )
        else
          Text(
            'Uploading a QR image needs the restaurant server.',
            style: AppTypography.caption,
          ),
        if (_draft.qrImageUrl != _base.qrImageUrl) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _draft.hasQrImage
                ? 'Save to start showing this image to guests.'
                : 'Save to stop showing the image to guests.',
            key: const ValueKey('upi-qr-pending'),
            style: AppTypography.caption.copyWith(color: AppColors.info),
          ),
        ],
        if (_qrError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ErrorLine(message: _qrError!),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('Payment verification', style: AppTypography.cardTitle),
        const SizedBox(height: 2),
        Text(
          'How a UPI payment is confirmed before the bill shows as paid.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ModeTile(
          key: const ValueKey('upi-mode-manual'),
          title: UpiVerificationMode.manual.label,
          description:
              'A cashier checks that the money arrived in your bank or UPI '
              'app, then confirms each payment.',
          selected: _draft.verificationMode == UpiVerificationMode.manual,
          onTap: busy ? null : () => _chooseMode(UpiVerificationMode.manual),
        ),
        _ModeTile(
          key: const ValueKey('upi-mode-automatic'),
          title: UpiVerificationMode.automatic.label,
          description:
              'Payments are confirmed by a connected bank or payment '
              'provider.',
          selected: _draft.verificationMode == UpiVerificationMode.automatic,
          notSetUp: !automaticAvailable,
          onTap: busy ? null : () => _chooseMode(UpiVerificationMode.automatic),
        ),
        if (!automaticAvailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              PaymentSettingsController.automaticUnavailableMessage,
              key: const ValueKey('upi-automatic-setup-note'),
              style: AppTypography.caption.copyWith(
                color: _draft.verificationMode == UpiVerificationMode.automatic
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        const _Assurance(),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          key: const ValueKey('upi-save'),
          label: 'Save payment settings',
          icon: Icons.check_rounded,
          isLoading: _saving,
          onPressed: busy ? null : _save,
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, required this.unsaved});

  final bool active;
  final bool unsaved;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = unsaved
        ? ('Unsaved changes', AppColors.warningSoft, AppColors.warning)
        : active
        ? ('Active', AppColors.successSoft, AppColors.success)
        : ('Off', AppColors.softWhite, AppColors.textSecondary);
    return Container(
      key: const ValueKey('upi-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: AppRadii.pill),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Shown where the build has no server (the offline demo).
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('upi-unavailable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'UPI payments to your own account need the restaurant server, so '
            'they are not part of the offline demo. Connect the app to your '
            'server to set them up.',
            style: AppTypography.bodySecondary,
          ),
        ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('upi-load-failed'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ErrorLine(
          message: message ?? 'The payment settings have not loaded yet.',
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: AppColors.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTypography.label.copyWith(color: AppColors.error),
          ),
        ),
      ],
    );
  }
}

/// A square preview of the QR picture, or a placeholder.
class _QrPreview extends StatelessWidget {
  const _QrPreview({required this.url, required this.busy});

  final String url;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Widget placeholder(String text, IconData icon) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 34, color: AppColors.textMuted),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.label.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: url.isEmpty ? 'No QR image' : 'Your UPI QR image',
        image: true,
        child: Container(
          key: const ValueKey('upi-qr-preview'),
          width: 168,
          height: 168,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.softWhite,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : url.isEmpty
              ? placeholder('No QR image', Icons.qr_code_2_rounded)
              : Image.network(
                  url,
                  key: ValueKey(url),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => placeholder(
                    'Preview not available',
                    Icons.broken_image_outlined,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.notSetUp = false,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  /// The option exists but this server cannot offer it yet.
  final bool notSetUp;

  @override
  Widget build(BuildContext context) {
    final muted = notSetUp && !selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySoft : Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? AppColors.primary
                      : (muted ? AppColors.inactive : AppColors.textMuted),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: AppTypography.cardTitle.copyWith(
                                color: muted ? AppColors.textSecondary : null,
                              ),
                            ),
                          ),
                          if (notSetUp) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.softWhite,
                                borderRadius: AppRadii.pill,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                'Not set up',
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(description, style: AppTypography.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the restaurant should know about where the money goes.
class _Assurance extends StatelessWidget {
  const _Assurance();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.info,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Guests pay in their own UPI app and the money goes straight '
              'to this account; DineQR never holds it. A bill shows as paid '
              'only after a cashier confirms the payment. UPI PINs, card '
              'numbers and bank passwords are never asked for or stored.',
              style: AppTypography.caption.copyWith(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }
}
