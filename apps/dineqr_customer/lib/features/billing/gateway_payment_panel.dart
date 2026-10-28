import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/upi_launcher.dart';

/// A UPI payment collected by the gateway (Cashfree) while it waits: the
/// guest pays in a UPI app on this phone ([app]) or by scanning the QR code
/// (no [app]), and this page shows that it is being confirmed.
///
/// Nothing here decides the outcome. The gateway reports the payment to the
/// server, which checks it with the gateway and settles the bill; this page
/// asks the server every few seconds (and as soon as the guest comes back
/// from their UPI app), and the payment screen shows the result.
class GatewayPaymentPanel extends StatefulWidget {
  const GatewayPaymentPanel({
    super.key,
    required this.header,
    required this.invoice,
    required this.payment,
    required this.apps,
    required this.checkout,
    required this.onRefresh,
    required this.onCancel,
    this.app,
    this.openAtStart = false,
    this.pollEvery = const Duration(seconds: 4),
  });

  /// The amount banner shown above everything.
  final Widget header;
  final Invoice invoice;

  /// The pending gateway payment.
  final PaymentTransaction payment;

  /// The app to pay in; null pays by QR code.
  final UpiApp? app;

  /// The UPI apps this phone can open (empty on web and desktop).
  final List<UpiApp> apps;

  /// Open [app] as soon as the panel shows: the guest just chose it.
  final bool openAtStart;

  /// The gateway's app links ([qr] false) or QR code for this payment.
  final Future<GatewayCheckout> Function({required bool qr}) checkout;

  /// Asks the server for the payment's latest status.
  final Future<void> Function() onRefresh;

  /// Ends the payment (it comes back paid if the guest already paid).
  final Future<void> Function() onCancel;

  /// How often the server is asked while this is on screen.
  final Duration pollEvery;

  @override
  State<GatewayPaymentPanel> createState() => _GatewayPaymentPanelState();
}

String _messageFor(Object error) => switch (error) {
  PaymentException(:final message) => message,
  ApiException(:final message) => message,
  final SessionExpiredException expired => expired.message,
  _ => 'Something went wrong. Please try again.',
};

class _GatewayPaymentPanelState extends State<GatewayPaymentPanel>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _clock;
  GatewayCheckout? _checkout;
  late UpiApp? _app = widget.app;
  bool _loading = false;
  bool _launched = false;
  bool _cancelling = false;
  bool _refreshing = false;

  /// The server could not be asked lately (it keeps trying).
  bool _offline = false;
  String? _error;
  String? _launchProblem;

  bool get _qr => _app == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(widget.pollEvery, (_) => _refresh());
    // The countdown to the order's end.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _checkout?.expiresAt != null) setState(() {});
    });
    unawaited(_load(open: widget.openAtStart && !_qr));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the UPI app: ask at once. Returning proves nothing; only
    // the gateway's report to the server does.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing || _cancelling) return;
    _refreshing = true;
    try {
      await widget.onRefresh();
      if (mounted && _offline) setState(() => _offline = false);
    } on Object {
      if (mounted && !_offline) setState(() => _offline = true);
    } finally {
      _refreshing = false;
    }
  }

  /// Fetches the app links or the QR code, opening the app when [open].
  Future<void> _load({required bool open}) async {
    setState(() {
      _loading = true;
      _error = null;
      _launchProblem = null;
    });
    try {
      final checkout = await widget.checkout(qr: _qr);
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _loading = false;
      });
      if (open) await _openApp();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _openApp() async {
    final app = _app;
    final checkout = _checkout;
    if (app == null || checkout == null) return;
    final link = app.linkIn(checkout);
    if (link == null) {
      setState(
        () => _launchProblem =
            'This payment has no UPI app link. Pay by QR code instead.',
      );
      return;
    }
    setState(() => _launchProblem = null);
    final result = await context.read<UpiLauncher>().open(link);
    if (!mounted) return;
    setState(() {
      switch (result) {
        case UpiLaunchResult.opened:
          _launched = true;
        case UpiLaunchResult.noApp:
          _launchProblem =
              '${app == UpiApp.other ? 'No UPI app' : '${app.label} was not'} '
              'found on this phone. Choose another app, or pay by QR code.';
        case UpiLaunchResult.unsupported:
          _launchProblem =
              'This device cannot open a UPI app. Pay by QR code instead.';
        case UpiLaunchResult.failed:
          _launchProblem =
              'We could not open ${app.label}. Choose another app, or pay by '
              'QR code.';
      }
    });
  }

  /// Pays the same order another way: in [app], or by QR code.
  Future<void> _switchTo(UpiApp? app) async {
    setState(() {
      _app = app;
      _launched = false;
      _checkout = null;
    });
    await _load(open: app != null);
  }

  Future<void> _cancel() async {
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await widget.onCancel();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  String? _timeLeft() {
    final end = _checkout?.expiresAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    if (left.isNegative) return null;
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.payment.provider;
    final amount = CurrencyFormatter.format(widget.payment.amount);
    final app = _app;
    final left = _timeLeft();
    final expired = _checkout?.expiresAt != null && left == null;
    final otherApps = widget.apps.where((a) => a != app).toList();
    return ListView(
      key: const ValueKey('gateway-panel'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        widget.header,
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const QrPulseLoader(
                size: 22,
                color: AppColors.primary,
                semanticLabel: 'Waiting for the payment',
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waiting for your payment',
                      key: const ValueKey('gateway-waiting'),
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app == null
                          ? 'Scan the QR code with any UPI app and pay $amount.'
                          : 'Pay $amount in ${app == UpiApp.other ? 'your UPI app' : app.label}.',
                      style: AppTypography.bodySecondary,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'This page updates by itself as soon as $provider '
                      'confirms the payment. You do not need to show anyone '
                      'a screenshot.',
                      style: AppTypography.caption,
                    ),
                    if (left != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Pay within $left',
                        key: const ValueKey('gateway-time-left'),
                        style: AppTypography.label.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_offline) ...[
          const SizedBox(height: AppSpacing.md),
          const _Notice(
            key: ValueKey('gateway-offline'),
            icon: Icons.wifi_off_rounded,
            color: AppColors.warning,
            text:
                'Cannot reach the restaurant server right now. Still checking; '
                'if you paid, your payment is safe and will show here.',
          ),
        ],
        if (expired) ...[
          const SizedBox(height: AppSpacing.md),
          const _Notice(
            key: ValueKey('gateway-expired'),
            icon: Icons.timer_off_outlined,
            color: AppColors.warning,
            text:
                'The time to pay has run out. If you did not pay, cancel and '
                'start again.',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: QrPulseLoader(
                size: 28,
                color: AppColors.primary,
                semanticLabel: 'Preparing the payment',
              ),
            ),
          )
        else if (_error != null) ...[
          _Notice(
            key: const ValueKey('gateway-error'),
            icon: Icons.error_outline_rounded,
            color: AppColors.error,
            text: _error!,
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            key: const ValueKey('gateway-retry'),
            label: 'Try again',
            onPressed: () => _load(open: !_qr),
          ),
        ] else if (app == null)
          _QrCard(checkout: _checkout, amount: amount, invoice: widget.invoice)
        else ...[
          PrimaryButton(
            key: const ValueKey('gateway-open-app'),
            label: app == UpiApp.other
                ? (_launched ? 'Open my UPI app again' : 'Open my UPI app')
                : (_launched ? 'Open ${app.label} again' : 'Open ${app.label}'),
            icon: Icons.open_in_new_rounded,
            onPressed: _checkout == null ? null : _openApp,
          ),
          if (_launchProblem != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Notice(
              key: const ValueKey('gateway-launch-problem'),
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              text: _launchProblem!,
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.lg),
        if (app != null)
          SecondaryButton(
            key: const ValueKey('gateway-show-qr'),
            label: 'Pay by QR code instead',
            icon: Icons.qr_code_2_rounded,
            onPressed: _loading ? null : () => _switchTo(null),
          ),
        if (otherApps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.xs,
            children: [
              for (final other in otherApps)
                TextButton(
                  key: ValueKey('gateway-switch-${other.name}'),
                  onPressed: _loading ? null : () => _switchTo(other),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  child: Text(
                    other == UpiApp.other
                        ? 'Another UPI app'
                        : 'Use ${other.label}',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            key: const ValueKey('gateway-cancel'),
            onPressed: _cancelling ? null : _cancel,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: Text(_cancelling ? 'Cancelling…' : 'Cancel payment'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Your bill is marked paid only when $provider confirms the money '
          'reached the restaurant. Coming back from your UPI app does not '
          'change it on its own, and you are never charged twice for this '
          'payment.',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

/// The gateway's QR code for this payment, with what it pays.
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.checkout,
    required this.amount,
    required this.invoice,
  });

  final GatewayCheckout? checkout;
  final String amount;
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final png = checkout?.qrPng;
    return AppCard(
      child: Column(
        children: [
          Text('Scan to pay', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.md),
          if (png == null)
            Text(
              'The QR code is not available. Try a UPI app instead.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySecondary,
            )
          else
            Container(
              key: const ValueKey('gateway-qr'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Image.memory(
                png,
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
                semanticLabel: 'UPI QR code for $amount',
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 220,
                  height: 220,
                  child: Icon(Icons.qr_code_2_rounded, size: 120),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(amount, style: AppTypography.headline.copyWith(fontSize: 24)),
          Text(
            'To ${invoice.restaurant.name} · Bill ${invoice.billNumber}',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The amount is filled in. Scan with Google Pay, PhonePe, Paytm, '
            'BHIM or any UPI app, on this phone or another.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ],
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
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.label)),
        ],
      ),
    );
  }
}
