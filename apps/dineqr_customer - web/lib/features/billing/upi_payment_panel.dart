import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/upi_launcher.dart';

/// Paying a bill by UPI straight to the restaurant's own account.
///
/// The guest pays in their own UPI app, so this app never sees the money and
/// never claims it moved. Google Pay and PhonePe refuse a payment that
/// another app fills in for a restaurant's own UPI ID (Google Pay: "You've
/// exceeded the bank limit"; nothing is debited): only a payment gateway's
/// verified merchant ID gets that. So the chosen app opens on its own with
/// the UPI ID copied, for the guest to pay there, next to a QR code and the
/// details; the guest is asked what happened when they come back; and the
/// payment waits for the restaurant to confirm. Only the restaurant's
/// confirmation settles the bill (see the payment screen, which shows the
/// outcome).
class UpiPaymentPanel extends StatefulWidget {
  const UpiPaymentPanel({
    super.key,
    required this.header,
    required this.invoice,
    required this.payment,
    required this.settings,
    required this.onClaim,
    required this.onCancel,
    required this.onRefresh,
    this.pollEvery = const Duration(seconds: 10),
    this.app,
    this.openAtStart = false,
  });

  /// The UPI app the guest chose; null (or the chooser) lets the phone offer
  /// its UPI apps.
  final InstalledUpiApp? app;

  /// Open [app] as soon as the panel shows: the guest just chose it.
  final bool openAtStart;

  /// The amount banner shown above everything.
  final Widget header;
  final Invoice invoice;

  /// The pending UPI payment being made.
  final PaymentTransaction payment;

  /// The restaurant's payee, as the server last reported it.
  final UpiSettings settings;

  /// The guest says they paid, optionally with the UPI transaction ID.
  final Future<void> Function(String reference) onClaim;

  /// The guest did not pay (or changed their mind).
  final Future<void> Function() onCancel;

  /// Asks the server for the latest state of the payment.
  final Future<void> Function() onRefresh;

  /// How often the server is asked while this is on screen.
  final Duration pollEvery;

  @override
  State<UpiPaymentPanel> createState() => _UpiPaymentPanelState();
}

/// A message for the guest from whatever went wrong.
String _messageFor(Object error) => switch (error) {
  PaymentException(:final message) => message,
  ApiException(:final message) => message,
  final SessionExpiredException expired => expired.message,
  _ => 'Something went wrong. Please try again.',
};

class _UpiPaymentPanelState extends State<UpiPaymentPanel>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  Timer? _poll;

  /// A UPI app was opened for this payment.
  bool _launched = false;

  /// The app went to the background after that (the guest is in their UPI
  /// app), so coming back means "ask what happened".
  bool _leftApp = false;
  bool _askOutcome = false;
  bool _showOwnQr = false;
  bool _busy = false;
  String? _launchProblem;
  String? _error;

  UpiPaymentLink get _link => UpiPaymentLink.forPayment(
    settings: widget.settings,
    invoice: widget.invoice,
    payment: widget.payment,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(widget.pollEvery, (_) {
      if (!_busy) widget.onRefresh().ignore();
    });
    if (widget.openAtStart && !widget.payment.isClaimed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openUpiApp();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_launched || widget.payment.isClaimed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
    } else if (state == AppLifecycleState.resumed && _leftApp) {
      // Back from the UPI app (or from its chooser). What happened there is
      // for the guest to say; the app cannot tell.
      _leftApp = false;
      setState(() => _askOutcome = true);
      // The question sits at the top of the page.
      if (_scroll.hasClients && _scroll.offset > 0) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }
  }

  /// Copies the UPI ID and opens the chosen app on its own, with no payment
  /// request in it (see the class comment), for the guest to pay there.
  Future<void> _openUpiApp() async {
    final launcher = context.read<UpiLauncher>();
    final app = widget.app;
    setState(() => _launchProblem = null);
    // Not awaited: copying never holds up opening the app (the platform
    // handles the two in order), and the ID is on screen to copy by hand.
    unawaited(
      _copy('UPI ID', widget.settings.upiId).catchError((Object error) {
        debugPrint('Could not copy the UPI ID: $error');
      }),
    );
    // No app chosen: the guest opens theirs; nothing can open "any UPI app"
    // without a payment request.
    final result = app == null || app.isChooser
        ? UpiLaunchResult.opened
        : await launcher.openApp(app);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case UpiLaunchResult.opened:
          _launched = true;
          _leftApp = false;
        case UpiLaunchResult.noApp:
          _launchProblem = switch (app) {
            final app? when !app.isChooser =>
              '${app.label} is not on this phone any more. Scan the QR code '
                  'below with any UPI app, or use the details below.',
            _ =>
              'No UPI app was found on this phone. Scan the QR code from '
                  'another phone, or use the details below.',
          };
        case UpiLaunchResult.unsupported:
          _launchProblem =
              'This device cannot open a UPI app. Scan the QR code with your '
              'phone, or use the details below.';
        case UpiLaunchResult.failed:
          _launchProblem =
              'We could not open your UPI app. Scan the QR code from '
              'another phone, or use the details below.';
      }
    });
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showAppSnackBar(context, '$label copied', icon: Icons.copy_rounded);
  }

  /// Runs a request, showing the server's message if it is refused.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The guest says they paid. Asked in a sheet so it is always in view,
  /// whatever part of this long page they were looking at.
  Future<void> _openClaimSheet() async {
    setState(() => _askOutcome = false);
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClaimSheet(onSend: widget.onClaim),
    );
  }

  Future<void> _notPaid() => _run(widget.onCancel);

  @override
  Widget build(BuildContext context) {
    final claimed = widget.payment.isClaimed;
    return ListView(
      key: const ValueKey('upi-list'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        FadeSlideIn(child: widget.header),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[
          _Notice(
            key: const ValueKey('upi-error'),
            icon: Icons.error_outline_rounded,
            color: AppColors.error,
            text: _error!,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (claimed) ..._waiting() else ..._ready(),
      ],
    );
  }

  // --------------------------------------------------- waiting for the shop

  List<Widget> _waiting() {
    final payment = widget.payment;
    final at = payment.claimedAt;
    return [
      AppCard(
        key: const ValueKey('upi-waiting'),
        child: Column(
          children: [
            const QrPulseLoader(
              size: 30,
              color: AppColors.primary,
              semanticLabel: 'Waiting for the restaurant',
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Waiting for the restaurant',
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'You told us you paid ${CurrencyFormatter.format(payment.amount)}. '
              'The restaurant checks its UPI account and confirms it. This '
              'page updates by itself, and your bill is marked paid only '
              'then.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (at != null) _Fact('Told us at', AppFormat.dateTime(at)),
            if (payment.reference.isNotEmpty)
              _Fact('Your UPI transaction ID', payment.reference),
            _Fact('Pay to', widget.settings.payeeName),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      SecondaryButton(
        key: const ValueKey('upi-check'),
        label: 'Check again',
        icon: Icons.refresh_rounded,
        onPressed: _busy ? null : () => _run(widget.onRefresh),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Paid by mistake, or changed your mind? Ask the staff: only they can '
        'cancel a payment you have already told us about.',
        textAlign: TextAlign.center,
        style: AppTypography.caption,
      ),
    ];
  }

  // ------------------------------------------------------ ready to pay

  List<Widget> _ready() {
    final settings = widget.settings;
    final launcher = context.read<UpiLauncher>();
    if (!settings.isReady) {
      return [
        _Notice(
          key: const ValueKey('upi-unavailable'),
          icon: Icons.info_outline_rounded,
          color: AppColors.info,
          text:
              'The restaurant\'s UPI details are not available right now, so '
              'this payment cannot continue. Cancel it and pay at the '
              'counter, or try again in a moment.',
        ),
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: _busy ? null : () => _run(widget.onRefresh),
        ),
        const SizedBox(height: AppSpacing.md),
        _cancelButton(),
      ];
    }
    final link = _link;
    final onPhone = launcher.canOpenApps;
    return [
      if (_askOutcome) ...[
        FadeSlideIn(child: _outcomePrompt()),
        const SizedBox(height: AppSpacing.lg),
      ],
      FadeSlideIn(
        index: 1,
        child: AppCard(child: onPhone ? _pasteInApp(link) : _payOnYourPhone()),
      ),
      const SizedBox(height: AppSpacing.lg),
      FadeSlideIn(
        index: 2,
        child: AppCard(
          child: Column(
            children: [
              Text(
                onPhone ? 'Or scan the QR code' : 'Scan with your phone',
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  'Any UPI app can scan this. The amount and note are filled '
                      'in.',
                  // UPI apps take a screenshot of a QR up to ₹2,000 (NPCI).
                  if (onPhone && widget.payment.amount.paise <= 200000)
                    'On this phone, take a screenshot and choose “Scan from '
                        'gallery” in your UPI app.',
                ].join(' '),
                textAlign: TextAlign.center,
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                key: const ValueKey('upi-qr'),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => PlainQrCode(
                    payload: link.uriString,
                    size: constraints.maxWidth.isFinite
                        ? constraints.maxWidth.clamp(160.0, 240.0).toDouble()
                        : 220,
                    semanticLabel:
                        'QR code to pay ${CurrencyFormatter.format(widget.payment.amount)} '
                        'to ${settings.payeeName} by UPI',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      FadeSlideIn(
        index: 3,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                key: const ValueKey('upi-details-title'),
                'Or enter the details',
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'In your UPI app, pay to this UPI ID. Use exactly this '
                'amount, and add the note so the restaurant can match it.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              _CopyRow(
                label: 'Pay to',
                value: settings.payeeName,
                onCopy: () => _copy('Name', settings.payeeName),
              ),
              _CopyRow(
                label: 'UPI ID',
                value: settings.upiId,
                onCopy: () => _copy('UPI ID', settings.upiId),
                copyKey: const ValueKey('copy-upi-id'),
              ),
              _CopyRow(
                label: 'Amount',
                value: '₹${link.amountText}',
                onCopy: () => _copy('Amount', link.amountText),
                copyKey: const ValueKey('copy-amount'),
              ),
              _CopyRow(
                label: 'Note',
                value: link.note,
                onCopy: () => _copy('Note', link.note),
                copyKey: const ValueKey('copy-note'),
              ),
            ],
          ),
        ),
      ),
      if (settings.hasQrImage) ...[
        const SizedBox(height: AppSpacing.lg),
        _ownQr(settings),
      ],
      const SizedBox(height: AppSpacing.xl),
      SecondaryButton(
        key: const ValueKey('upi-paid'),
        label: 'I\'ve paid',
        icon: Icons.check_rounded,
        onPressed: _busy ? null : _openClaimSheet,
      ),
      const SizedBox(height: AppSpacing.sm),
      _cancelButton(),
    ];
  }

  /// Desktop and web: no UPI app here.
  Widget _payOnYourPhone() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Pay with your UPI app', style: AppTypography.sectionTitle),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Open this page on your phone to pay with a UPI app, or scan the QR '
        'code below with your phone.',
        style: AppTypography.bodySecondary,
      ),
    ],
  );

  /// The chosen app opens on its own with the UPI ID copied, and the guest
  /// pays it there (see the class comment).
  Widget _pasteInApp(UpiPaymentLink link) {
    final app = widget.app;
    final named = app != null && !app.isChooser;
    final name = named ? app.label : 'your UPI app';
    return Column(
      key: const ValueKey('upi-paste-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          named ? 'Pay with ${app.label}' : 'Pay with your UPI app',
          style: AppTypography.sectionTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '1. Tap below: we copy the restaurant\'s UPI ID'
          '${named ? ' and open ${app.label}' : ''}.\n'
          '2. In $name, choose “Pay UPI ID” (or “Pay anyone”), paste it and '
          'pay exactly ₹${link.amountText}. Add the note “${link.note}”.\n'
          '3. Come back here and tell us.',
          style: AppTypography.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          key: const ValueKey('upi-open-app'),
          label: named
              ? 'Copy UPI ID & open ${app.label}'
              : (_launched ? 'Copy UPI ID again' : 'Copy UPI ID'),
          icon: named ? Icons.open_in_new_rounded : Icons.copy_rounded,
          onPressed: _busy ? null : _openUpiApp,
        ),
        if (_launchProblem != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Notice(
            key: const ValueKey('upi-launch-problem'),
            icon: Icons.info_outline_rounded,
            color: AppColors.warning,
            text: _launchProblem!,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Why isn\'t the amount filled in? Google Pay and PhonePe refuse a '
          'payment that another app fills in for a restaurant\'s own UPI ID: '
          'Google Pay shows “You\'ve exceeded the bank limit”, though no limit '
          'was reached and nothing is debited. A payment you start in the app '
          'goes through.',
          key: const ValueKey('upi-open-note'),
          style: AppTypography.caption,
        ),
      ],
    );
  }

  Widget _cancelButton() => TextButton(
    key: const ValueKey('upi-cancel'),
    onPressed: _busy ? null : _notPaid,
    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    child: const Text('Cancel this payment'),
  );

  /// Shown when the guest comes back from their UPI app.
  Widget _outcomePrompt() {
    return Container(
      key: const ValueKey('upi-outcome'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Did your payment go through?',
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'We can\'t see what happened in your UPI app, so please tell us. '
            'The restaurant will confirm the money before your bill is '
            'marked paid.',
            key: const ValueKey('upi-outcome-text'),
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            key: const ValueKey('upi-outcome-paid'),
            label: 'Yes, I\'ve paid',
            icon: Icons.check_rounded,
            height: 48,
            onPressed: _busy ? null : _openClaimSheet,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            key: const ValueKey('upi-outcome-failed'),
            label: 'No, it failed or I cancelled',
            height: 48,
            onPressed: _busy ? null : _notPaid,
          ),
          TextButton(
            key: const ValueKey('upi-outcome-unsure'),
            onPressed: () => setState(() => _askOutcome = false),
            child: const Text('Not sure yet'),
          ),
        ],
      ),
    );
  }

  /// The restaurant's own merchant QR, as a backup. It cannot carry the
  /// amount, so the guest is told to enter it.
  Widget _ownQr(UpiSettings settings) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('upi-own-qr-toggle'),
            onTap: () => setState(() => _showOwnQr = !_showOwnQr),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'The restaurant\'s own QR',
                    style: AppTypography.sectionTitle,
                  ),
                ),
                Icon(
                  _showOwnQr
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ],
            ),
          ),
          if (_showOwnQr) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This one does not carry the amount: enter '
              '₹${_link.amountText} yourself, and add the note '
              '"${_link.note}".',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Image.network(
                  settings.qrImageUrl,
                  key: const ValueKey('upi-own-qr'),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                    'The picture could not be loaded. Use the QR code above '
                    'instead.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "I've paid": the guest tells the restaurant, optionally with the UPI
/// transaction ID from their app. The request runs here, so a refusal is
/// shown next to the button and the guest can try again.
class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.onSend});

  final Future<void> Function(String reference) onSend;

  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  final _reference = TextEditingController();
  bool _busy = false;
  String? _referenceError;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reference = UpiReference.normalize(_reference.text);
    if (reference.isNotEmpty && !UpiReference.isValid(reference)) {
      setState(() => _referenceError = UpiReference.rule);
      return;
    }
    setState(() {
      _busy = true;
      _referenceError = null;
      _error = null;
    });
    try {
      await widget.onSend(reference);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          child: Column(
            key: const ValueKey('upi-claim-form'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell the restaurant you paid',
                style: AppTypography.sectionTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'They will check their UPI account and confirm it. Your bill '
                'is marked paid only after they do.',
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('upi-ref-field'),
                controller: _reference,
                enabled: !_busy,
                maxLength: 40,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: InputDecoration(
                  labelText: 'UPI transaction ID (optional)',
                  helperText:
                      'Shown in your UPI app after paying. It helps the staff '
                      'find your payment.',
                  helperMaxLines: 2,
                  counterText: '',
                  errorText: _referenceError,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _Notice(
                  key: const ValueKey('upi-claim-error'),
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  text: _error!,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                key: const ValueKey('upi-claim'),
                label: 'Tell the restaurant',
                icon: Icons.send_rounded,
                isLoading: _busy,
                onPressed: _busy ? null : _send,
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.label.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.copyKey,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final Key? copyKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption),
                SelectableText(
                  value,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: copyKey,
            tooltip: 'Copy $label',
            icon: const Icon(Icons.copy_rounded, size: 20),
            color: AppColors.primary,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
