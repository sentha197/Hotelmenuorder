import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../app/upi_launcher.dart';
import 'demo_checkout_sheet.dart';
import 'gateway_payment_panel.dart';
import 'upi_payment_panel.dart';

enum _Stage {
  choose,
  processing,
  success,
  failed,
  cancelled,
  counter,
  upi,
  gateway,
}

/// Pays all or part of a bill: by UPI from an app on this phone (Google Pay,
/// PhonePe, Paytm, ...) or by QR code, in cash or at the counter, by card
/// and the like where the demo offers them, or split across several.
///
/// With the live gateway (Cashfree) a UPI payment is settled automatically
/// once the gateway reports it to the server; without one, UPI goes to the
/// restaurant's own UPI ID and staff confirm it. Coming back from a UPI app
/// never counts as payment.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _amountField = TextEditingController();
  _Stage _stage = _Stage.choose;
  PaymentOption? _option;
  bool _payFull = true;
  String? _amountError;
  PaymentTransaction? _result;
  String? _message;

  /// Reused when an attempt is retried after its result never arrived, so
  /// the server returns that attempt instead of charging again. Cleared
  /// once an attempt has a final result or the request changes.
  String? _attemptKey;

  /// The UPI app chosen under the UPI option; null until the guest picks one
  /// (the first installed app is shown as chosen).
  InstalledUpiApp? _app;

  /// The UPI apps found on this phone; null until known.
  List<InstalledUpiApp>? _installed;

  /// The payment shown in [_Stage.upi] (to the restaurant's own UPI ID) or
  /// [_Stage.gateway] (through the gateway). What those stages show follows
  /// the payment's real status on the bill, so the outcome arrives on its
  /// own.
  String? _paymentId;

  /// How that payment is paid: in this app or by QR code (null).
  InstalledUpiApp? _payWith;

  /// The guest just chose how to pay, so the UPI app opens at once.
  bool _openAtStart = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    final billing = context.read<BillingController>();
    // The payee may have changed since the app last asked.
    unawaited(billing.loadUpiSettings());
    unawaited(_findApps());
    // Coming back to a payment that was started earlier (the app was closed
    // or the guest left): carry on with it instead of starting another.
    final unfinished = billing
        .byId(widget.invoiceId)
        ?.payments
        .where(
          (p) =>
              (p.isUpiDirect || p.isGateway) &&
              p.status == PaymentStatus.pending,
        )
        .lastOrNull;
    if (unfinished != null) {
      _paymentId = unfinished.id;
      _stage = unfinished.isGateway ? _Stage.gateway : _Stage.upi;
    }
  }

  Future<void> _findApps() async {
    final installed = await context.read<UpiLauncher>().installedApps();
    if (mounted) setState(() => _installed = installed);
  }

  @override
  void dispose() {
    _amountField.dispose();
    super.dispose();
  }

  Money? _amount(Invoice invoice) => _payFull
      ? invoice.payableNow
      : SettingsController.parseRupees(_amountField.text);

  /// The chosen option. Real-money UPI (the gateway's, or the restaurant's
  /// own UPI ID) is chosen until the guest picks another, so the page never
  /// opens on demo wording.
  PaymentOption? _selected(BillingController billing) {
    if (billing.paymentOptions.contains(_option)) return _option;
    return billing.gatewayUpiAvailable || billing.upiDirectAvailable
        ? PaymentOption.upi
        : null;
  }

  /// The UPI apps offered: those installed, then any UPI app (the phone's
  /// own list). None where no app can be opened (web, desktop).
  List<InstalledUpiApp> get _apps => context.read<UpiLauncher>().canOpenApps
      ? [...?_installed, InstalledUpiApp.chooser]
      : const [];

  InstalledUpiApp get _chosenApp => _app != null && _apps.contains(_app)
      ? _app!
      : (_apps.firstOrNull ?? InstalledUpiApp.chooser);

  void _select(PaymentOption option) => setState(() {
    _option = option;
    _attemptKey = null;
    _amountError = null;
  });

  /// Pays with [option]; for UPI, in [app] (the chosen one by default).
  Future<void> _pay(
    Invoice invoice,
    PaymentOption option, {
    InstalledUpiApp? app,
  }) async {
    final billing = context.read<BillingController>();
    if (_starting) return;
    final amount = _amount(invoice);
    if (amount == null) {
      setState(() => _amountError = 'Enter an amount, e.g. 250 or 250.50.');
      return;
    }
    final problem = billing.validateAmount(
      invoice,
      amount,
      allowPartial: billing.allowPartialPayments,
    );
    if (problem != null) {
      setState(() => _amountError = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    if (!option.isOnline) return _payAtCounter(invoice, option, amount);
    // QR Payment is paid by scanning, so no app opens for it.
    final upiApp = option == PaymentOption.upi && _apps.isNotEmpty
        ? (app ?? _chosenApp)
        : null;
    if (billing.isGatewayOption(option)) {
      return _startGateway(invoice, amount, app: upiApp);
    }
    if (billing.isDirectUpiOption(option)) {
      return _startUpi(invoice, amount, app: upiApp);
    }

    var outcome = SimulatedOutcome.success;
    var detail = option.detail;
    if (billing.isSimulated) {
      // The demo checkout: the payment is made only once the guest confirms.
      final checkout = await showDemoCheckout(
        context,
        option: option,
        amount: amount,
        invoice: invoice,
      );
      if (checkout == null || !mounted) return;
      outcome = checkout.outcome;
      detail = checkout.detail;
    }
    setState(() {
      _stage = _Stage.processing;
      _amountError = null;
    });
    try {
      final transaction = await billing.payOnline(
        invoiceId: invoice.id,
        amount: amount,
        method: option.method!,
        methodDetail: detail,
        idempotencyKey: _attemptKey ??= Ids.random(),
        outcome: outcome,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _attemptKey = null;
        _result = transaction;
        _message = transaction.failureReason;
        _stage = switch (transaction.status) {
          PaymentStatus.succeeded => _Stage.success,
          PaymentStatus.cancelled => _Stage.cancelled,
          _ => _Stage.failed,
        };
      });
    } on PaymentException catch (error) {
      // The key is kept: trying again replays this attempt.
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _result = null;
        _message = error.message;
      });
    }
  }

  /// Starts a UPI payment through the gateway (the server holds the amount
  /// against the bill) and moves on to paying it: in [app], or by QR code
  /// when [app] is null.
  Future<void> _startGateway(
    Invoice invoice,
    Money amount, {
    InstalledUpiApp? app,
  }) async {
    final billing = context.read<BillingController>();
    setState(() {
      _starting = true;
      _amountError = null;
    });
    try {
      final payment = await billing.startGatewayUpi(
        invoiceId: invoice.id,
        amount: amount,
        idempotencyKey: _attemptKey ??= Ids.random(),
        methodDetail: switch (app) {
          null => PaymentOption.scanAndPay.detail,
          final app when app.isChooser => '',
          final app => app.label,
        },
      );
      if (!mounted) return;
      setState(() {
        _starting = false;
        _attemptKey = null;
        _paymentId = payment.id;
        _payWith = app;
        _openAtStart = app != null;
        _stage = _Stage.gateway;
      });
    } on PaymentException catch (error) {
      // The key is kept: trying again replays this request.
      if (!mounted) return;
      setState(() {
        _starting = false;
        _stage = _Stage.failed;
        _result = null;
        _message = error.message;
      });
    }
  }

  /// Records a UPI payment to the restaurant as pending (holding the amount
  /// against the bill) and moves on to paying it: in [app], or by QR code
  /// when [app] is null.
  Future<void> _startUpi(
    Invoice invoice,
    Money amount, {
    InstalledUpiApp? app,
  }) async {
    final billing = context.read<BillingController>();
    setState(() {
      _starting = true;
      _amountError = null;
    });
    try {
      final payment = await billing.startUpiPayment(
        invoiceId: invoice.id,
        amount: amount,
      );
      if (!mounted) return;
      setState(() {
        _starting = false;
        _paymentId = payment.id;
        _payWith = app;
        _openAtStart = app != null;
        _stage = _Stage.upi;
      });
    } on PaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _stage = _Stage.failed;
        _result = null;
        _message = error.message;
      });
    }
  }

  Future<void> _payAtCounter(
    Invoice invoice,
    PaymentOption option,
    Money amount,
  ) async {
    final billing = context.read<BillingController>();
    setState(() => _stage = _Stage.processing);
    try {
      await billing.requestCounterPayment(
        invoiceId: invoice.id,
        kind: option.counter!,
        amount: amount,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _stage = _Stage.counter);
    } on PaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.choose;
        _amountError = error.message;
      });
    }
  }

  Future<void> _payOnlineInstead(Invoice invoice) async {
    try {
      await context.read<BillingController>().cancelCounterRequest(invoice.id);
    } on PaymentException catch (error) {
      if (mounted) showAppSnackBar(context, error.message);
    }
    if (mounted) _retry();
  }

  void _retry() => setState(() {
    _stage = _Stage.choose;
    _paymentId = null;
    _payWith = null;
    _openAtStart = false;
    _result = null;
    _message = null;
  });

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingController>();
    final invoice = billing.byId(widget.invoiceId);
    final processing = _stage == _Stage.processing;
    final selected = _selected(billing);
    final canPay =
        invoice != null &&
        _stage == _Stage.choose &&
        !invoice.payableNow.isZero &&
        selected != null;
    return PopScope(
      // Leaving mid-payment could hide its result.
      canPop: !processing,
      child: Scaffold(
        appBar: AppBar(
          leading: processing ? const SizedBox.shrink() : const AppBackButton(),
          title: const Text('Payment'),
        ),
        // The pay button stays in reach however long the form is.
        bottomNavigationBar: canPay
            ? _PayButtonBar(
                label: _payLabel(
                  selected,
                  _amount(invoice),
                  app: selected == PaymentOption.upi && _apps.isNotEmpty
                      ? _chosenApp
                      : null,
                ),
                icon: switch (selected) {
                  PaymentOption.scanAndPay => Icons.qr_code_2_rounded,
                  _ when selected.isOnline => Icons.lock_rounded,
                  _ => Icons.storefront_rounded,
                },
                isLoading: _starting,
                onPressed: () => _pay(invoice, selected),
              )
            : null,
        body: invoice == null
            ? const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Bill not found',
                message: 'This bill is no longer on this device.',
              )
            : _Constrained(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  child: switch (_stage) {
                    _Stage.choose => _buildChoose(invoice, billing),
                    _Stage.upi => _buildUpi(invoice, billing),
                    _Stage.gateway => _buildGateway(invoice, billing),
                    _Stage.processing => _Processing(
                      key: const ValueKey('processing'),
                      simulated: billing.isSimulated,
                      counter: !(selected?.isOnline ?? true),
                    ),
                    _Stage.success => _Result(
                      key: const ValueKey('success'),
                      success: true,
                      title: _result?.isSimulated ?? false
                          ? 'Demo payment successful'
                          : 'Payment successful',
                      invoice: invoice,
                      transaction: _result,
                      onPrimary: () => Navigator.of(context).pop(),
                      primaryLabel: 'Done',
                      onSecondary: () =>
                          AppNav.openReceipt(context, invoice.id),
                      secondaryLabel: 'View, print or share receipt',
                    ),
                    _Stage.failed => _Result(
                      key: const ValueKey('failed'),
                      success: false,
                      title: 'Payment failed',
                      // Server reasons say whether money moved; an
                      // unconfirmed attempt says it will not charge twice.
                      message: _message?.isNotEmpty ?? false
                          ? _message
                          : 'The payment did not go through. No money was '
                                'taken.',
                      invoice: invoice,
                      transaction: _result,
                      onPrimary: _retry,
                      primaryLabel: 'Try again',
                      onSecondary: () => Navigator.of(context).pop(),
                      secondaryLabel: 'Back to bill',
                    ),
                    _Stage.cancelled => _Result(
                      key: const ValueKey('cancelled'),
                      success: false,
                      title: 'Payment cancelled',
                      message:
                          'Nothing was charged. You can try again any time.',
                      invoice: invoice,
                      transaction: _result,
                      onPrimary: _retry,
                      primaryLabel: 'Try again',
                      onSecondary: () => Navigator.of(context).pop(),
                      secondaryLabel: 'Back to bill',
                    ),
                    _Stage.counter => _CounterResult(
                      key: const ValueKey('counter'),
                      invoice: invoice,
                      simulated: billing.isSimulated,
                      onDone: () => Navigator.of(context).pop(),
                      onPayOnline: billing.onlinePaymentsAvailable
                          ? () => _payOnlineInstead(invoice)
                          : null,
                    ),
                  },
                ),
              ),
      ),
    );
  }

  static String _payLabel(
    PaymentOption option,
    Money? amount, {
    InstalledUpiApp? app,
  }) {
    final value = amount == null ? '' : ' ${CurrencyFormatter.format(amount)}';
    return switch (option) {
      PaymentOption.cash => 'Pay$value in cash',
      PaymentOption.payAtCounter => 'Pay$value at the counter',
      PaymentOption.scanAndPay => 'Pay$value by QR code',
      PaymentOption.upi when app != null && !app.isChooser =>
        'Pay$value with ${app.label}',
      _ => 'Pay$value with ${option.label}',
    };
  }

  /// The payment shown in the UPI and gateway stages, or null (after going
  /// back to the choice) when it is no longer on the bill.
  PaymentTransaction? _shownPayment(Invoice invoice) {
    final payment = invoice.payments
        .where((p) => p.id == _paymentId)
        .firstOrNull;
    if (payment == null) {
      // Not on the bill any more (it was reloaded): back to the choice.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retry();
      });
    }
    return payment;
  }

  /// The UPI payment to the restaurant being made: its panel while it waits,
  /// and a result once the restaurant has confirmed, refused or cancelled it.
  Widget _buildUpi(Invoice invoice, BillingController billing) {
    final payment = _shownPayment(invoice);
    if (payment == null) {
      return const SizedBox.shrink(key: ValueKey('upi-gone'));
    }
    return switch (payment.status) {
      PaymentStatus.pending => UpiPaymentPanel(
        key: const ValueKey('upi-pending'),
        header: _AmountHeader(invoice: invoice, amount: payment.amount),
        invoice: invoice,
        payment: payment,
        settings: billing.upiSettings,
        app: _payWith,
        openAtStart: _openAtStart,
        onClaim: (reference) =>
            billing.claimUpiPayment(payment.id, reference: reference),
        onCancel: () => billing.cancelUpiPayment(payment.id),
        onRefresh: () => billing.checkPending(invoice.id),
      ),
      PaymentStatus.succeeded => _Result(
        key: const ValueKey('upi-success'),
        success: true,
        title: 'Payment confirmed',
        message: 'The restaurant confirmed your UPI payment.',
        invoice: invoice,
        transaction: payment,
        onPrimary: () => Navigator.of(context).pop(),
        primaryLabel: 'Done',
        onSecondary: () => AppNav.openReceipt(context, invoice.id),
        secondaryLabel: 'View receipt',
      ),
      PaymentStatus.failed => _Result(
        key: const ValueKey('upi-failed'),
        success: false,
        title: 'Payment not received',
        message:
            '${payment.failureReason.isEmpty ? 'The restaurant did not receive this payment.' : payment.failureReason} '
            'Your bill is still unpaid. If money left your account, show '
            'your UPI receipt to the staff.',
        invoice: invoice,
        transaction: payment,
        onPrimary: _retry,
        primaryLabel: 'Try again',
        onSecondary: () => Navigator.of(context).pop(),
        secondaryLabel: 'Back to bill',
      ),
      PaymentStatus.cancelled => _Result(
        key: const ValueKey('upi-cancelled'),
        success: false,
        title: 'Payment cancelled',
        message:
            'Nothing was recorded on your bill. If money has left your '
            'account, show your UPI receipt to the staff.',
        invoice: invoice,
        transaction: payment,
        onPrimary: _retry,
        primaryLabel: 'Try again',
        onSecondary: () => Navigator.of(context).pop(),
        secondaryLabel: 'Back to bill',
      ),
    };
  }

  /// A UPI payment through the gateway: its panel while the gateway has not
  /// reported it, then the outcome the server recorded from that report.
  Widget _buildGateway(Invoice invoice, BillingController billing) {
    final payment = _shownPayment(invoice);
    if (payment == null) {
      return const SizedBox.shrink(key: ValueKey('gateway-gone'));
    }
    return switch (payment.status) {
      PaymentStatus.pending => GatewayPaymentPanel(
        key: ValueKey('gateway-pending-${payment.id}'),
        header: _AmountHeader(invoice: invoice, amount: payment.amount),
        invoice: invoice,
        payment: payment,
        app: _payWith,
        apps: _apps,
        openAtStart: _openAtStart,
        checkout: ({required bool qr}) =>
            billing.gatewayCheckout(payment.id, qr: qr),
        onRefresh: () => billing.checkPending(invoice.id),
        onCancel: () => billing.cancelPayment(payment.id),
      ),
      PaymentStatus.succeeded => _Result(
        key: const ValueKey('gateway-success'),
        success: true,
        title: payment.isSimulated
            ? 'Demo payment successful'
            : 'Payment successful',
        message:
            '${payment.provider} confirmed your UPI payment. Your bill is '
            'updated.',
        invoice: invoice,
        transaction: payment,
        onPrimary: () => Navigator.of(context).pop(),
        primaryLabel: 'Done',
        onSecondary: () => AppNav.openReceipt(context, invoice.id),
        secondaryLabel: 'View, print or share receipt',
      ),
      PaymentStatus.failed => _Result(
        key: const ValueKey('gateway-failed'),
        success: false,
        title: 'Payment failed',
        message: payment.failureReason.isEmpty
            ? 'The payment did not go through. No money was taken.'
            : payment.failureReason,
        invoice: invoice,
        transaction: payment,
        onPrimary: _retry,
        primaryLabel: 'Try again',
        onSecondary: () => Navigator.of(context).pop(),
        secondaryLabel: 'Back to bill',
      ),
      PaymentStatus.cancelled => _Result(
        key: const ValueKey('gateway-cancelled'),
        success: false,
        title: 'Payment not completed',
        message: payment.failureReason.isEmpty
            ? 'Nothing was charged. You can try again any time.'
            : payment.failureReason,
        invoice: invoice,
        transaction: payment,
        onPrimary: _retry,
        primaryLabel: 'Try again',
        onSecondary: () => Navigator.of(context).pop(),
        secondaryLabel: 'Back to bill',
      ),
    };
  }

  Widget _buildChoose(Invoice invoice, BillingController billing) {
    final payable = invoice.payableNow;
    if (payable.isZero) {
      return EmptyState(
        key: const ValueKey('nothing'),
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing to pay',
        message: invoice.hasPendingPayment
            ? 'A payment for this bill is still being confirmed.'
            : 'This bill has no balance due.',
      );
    }
    final options = billing.paymentOptions;
    final selected = _selected(billing);
    final direct = selected != null && billing.isDirectUpiOption(selected);
    final gateway = selected != null && billing.isGatewayOption(selected);
    // The demo simulator never applies to real-money UPI.
    final simulated = billing.isSimulated && !direct && !gateway;
    final amount = _amount(invoice);
    final shown = CurrencyFormatter.format(amount ?? payable);
    var index = 0;
    return ListView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        if (simulated) ...[
          FadeSlideIn(index: index++, child: const _DemoBanner()),
          const SizedBox(height: AppSpacing.lg),
        ],
        FadeSlideIn(
          index: index++,
          child: _AmountHeader(invoice: invoice, amount: amount ?? payable),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (billing.allowPartialPayments) ...[
          Text('Amount', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.sm),
          _AmountChoice(
            payable: payable,
            payFull: _payFull,
            controller: _amountField,
            error: _amountError,
            onFull: (full) => setState(() {
              _payFull = full;
              _amountError = null;
              _attemptKey = null;
            }),
            onChanged: () => setState(() {
              _amountError = null;
              _attemptKey = null;
            }),
          ),
          const SizedBox(height: AppSpacing.xl),
        ] else if (_amountError != null) ...[
          Text(
            _amountError!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text('Choose how to pay', style: AppTypography.sectionTitle),
        const SizedBox(height: AppSpacing.sm),
        if (!billing.onlinePaymentsAvailable) ...[
          Text(
            'Online payment is not available right now. Pay in cash or at '
            'the counter; staff record it and this bill updates.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _OptionList(
          options: options,
          selected: selected,
          demo: (option) =>
              billing.isSimulated &&
              option.isOnline &&
              !billing.isDirectUpiOption(option) &&
              !billing.isGatewayOption(option),
          describe: (option) => switch (option) {
            PaymentOption.upi when billing.isDirectUpiOption(option) =>
              'Pay ${billing.upiSettings.payeeName} directly',
            PaymentOption.upi => 'Google Pay, PhonePe, Paytm or any UPI app',
            PaymentOption.scanAndPay => 'Scan a QR code with any UPI app',
            _ => option.description,
          },
          details: {
            PaymentOption.upi: _UpiApps(
              apps: _apps,
              searching: _installed == null,
              chosen: _apps.isEmpty ? null : _chosenApp,
              amount: shown,
              prefills:
                  !billing.isDirectUpiOption(PaymentOption.upi) ||
                  billing.upiSettings.takesPaymentLinks,
              busy: _starting,
              onPick: (app) {
                setState(() => _app = app);
                _pay(invoice, PaymentOption.upi, app: app);
              },
            ),
            PaymentOption.scanAndPay: Text(
              'A QR code with $shown filled in appears next. Scan it with '
              'any UPI app, on this phone or another.',
              style: AppTypography.caption,
            ),
          },
          onSelect: _select,
        ),
        if (billing.canSplit) ...[
          const SizedBox(height: AppSpacing.md),
          _SplitCard(onTap: () => AppNav.openSplitPayment(context, invoice.id)),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          gateway
              ? 'Secured by ${billing.gateway.providerName}. Your bill updates '
                    'by itself once ${billing.gateway.providerName} confirms '
                    'the payment; there is nothing to show the staff.'
              : direct
              ? 'You pay ${billing.upiSettings.payeeName} directly from your '
                    'own UPI app. The bill is marked paid only after the '
                    'restaurant confirms the money arrived.'
              : simulated
              ? 'Demo mode: payments are simulated by DineQR and never reach a '
                    'bank. No money is charged, and every payment is labelled '
                    'as a demo.'
              : 'Payments are processed by ${billing.gateway.providerName}. '
                    'The bill updates only after the payment is verified.',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
      ],
    );
  }
}

/// Keeps content readable on tablets and desktops: centred, at most 640
/// wide, never scrolling sideways.
class _Constrained extends StatelessWidget {
  const _Constrained({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}

class _PayButtonBar extends StatelessWidget {
  const _PayButtonBar({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.md,
                AppSpacing.page,
                AppSpacing.md,
              ),
              child: PrimaryButton(
                label: label,
                icon: icon,
                isLoading: isLoading,
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Demo payment: nothing will be charged. Use it to try the '
              'payment flow.',
              style: AppTypography.label.copyWith(color: AppColors.info),
            ),
          ),
          const DemoTag(),
        ],
      ),
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.invoice, required this.amount});

  final Invoice invoice;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          const BoxShadow(color: AppColors.panelLip, offset: Offset(0, 3)),
          BoxShadow(
            color: AppColors.deepRed.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: BrandPanel(
        watermark: true,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AMOUNT TO PAY',
              style: AppTypography.overline.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 4),
            LayeredGradientText(
              CurrencyFormatter.format(amount),
              style: AppTypography.display.copyWith(
                fontSize: 36,
                fontWeight: FontWeight.w800,
              ),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, AppColors.peach],
              ),
              baseColor: AppColors.depthOnRed,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bill ${invoice.billNumber} · ${invoice.tableLabel} · '
              'Total ${CurrencyFormatter.format(invoice.total)}',
              style: AppTypography.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            if (!invoice.amountPaid.isZero)
              Text(
                'Already paid ${CurrencyFormatter.format(invoice.amountPaid)}'
                '${invoice.hasDemoPayments ? ' (demo)' : ''}',
                style: AppTypography.caption.copyWith(color: AppColors.peach),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountChoice extends StatelessWidget {
  const _AmountChoice({
    required this.payable,
    required this.payFull,
    required this.controller,
    required this.error,
    required this.onFull,
    required this.onChanged,
  });

  final Money payable;
  final bool payFull;
  final TextEditingController controller;
  final String? error;
  final ValueChanged<bool> onFull;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(bool full, String title, String subtitle) => Expanded(
      child: Pressable(
        onTap: () => onFull(full),
        scale: 0.97,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: payFull == full ? AppColors.primarySoft : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: payFull == full ? AppColors.primary : AppColors.border,
              width: payFull == full ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.cardTitle),
              Text(subtitle, style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            option(true, 'Full balance', CurrencyFormatter.format(payable)),
            const SizedBox(width: AppSpacing.md),
            option(false, 'Part payment', 'Pay the rest later'),
          ],
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.medium),
          child: payFull
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                    decoration: InputDecoration(
                      prefixText: '${CurrencyFormatter.symbol} ',
                      hintText:
                          'Amount (up to ${CurrencyFormatter.format(payable)})',
                      errorText: error,
                    ),
                  ),
                ),
        ),
        if (payFull && error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              error!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

/// The payment options one below another. The chosen one is marked and,
/// where it has more to offer ([details]: the UPI apps under UPI), opens up
/// beneath its row.
class _OptionList extends StatelessWidget {
  const _OptionList({
    required this.options,
    required this.selected,
    required this.demo,
    required this.describe,
    required this.details,
    required this.onSelect,
  });

  final List<PaymentOption> options;
  final PaymentOption? selected;

  /// Whether paying with an option is a demo payment (no money moves).
  final bool Function(PaymentOption option) demo;

  /// The line under an option's name.
  final String Function(PaymentOption option) describe;

  /// Shown under an option while it is chosen.
  final Map<PaymentOption, Widget> details;
  final ValueChanged<PaymentOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Payment options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, option) in options.indexed)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == options.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: FadeSlideIn(
                index: index,
                child: _OptionRow(
                  key: ValueKey('option-${option.name}'),
                  option: option,
                  selected: option == selected,
                  demo: demo(option),
                  description: describe(option),
                  details: details[option],
                  onTap: () => onSelect(option),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.option,
    required this.selected,
    required this.demo,
    required this.description,
    required this.details,
    required this.onTap,
  });

  final PaymentOption option;
  final bool selected;
  final bool demo;
  final String description;
  final Widget? details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final more = details;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      decoration: BoxDecoration(
        color: selected ? AppColors.primarySoft : Colors.white,
        borderRadius: AppRadii.card,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.6 : 1,
        ),
        boxShadow: selected ? AppShadows.soft : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            selected: selected,
            button: true,
            inMutuallyExclusiveGroup: true,
            child: Pressable(
              onTap: onTap,
              scale: 0.98,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : AppColors.softWhite,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(
                        option.icon,
                        size: 22,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                option.label,
                                style: AppTypography.cardTitle,
                              ),
                              if (demo) const DemoTag(),
                            ],
                          ),
                          Text(description, style: AppTypography.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 22,
                      color: selected ? AppColors.primary : AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            alignment: Alignment.topCenter,
            child: selected && more != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: more,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The UPI apps under the UPI option: the ones on this phone (Google Pay,
/// PhonePe and Paytm first, then any other UPI app, each with its own icon
/// where the phone gives one) and the phone's own list. Tapping one opens it
/// with the payee and [amount] filled in.
class _UpiApps extends StatelessWidget {
  const _UpiApps({
    required this.apps,
    required this.searching,
    required this.chosen,
    required this.amount,
    required this.busy,
    required this.onPick,
    this.prefills = true,
  });

  final List<InstalledUpiApp> apps;
  final bool searching;
  final InstalledUpiApp? chosen;
  final String amount;

  /// Whether the apps open with the payment filled in. A UPI app's own
  /// ID refuses payment links: the guest pays to it in the app instead.
  final bool prefills;
  final bool busy;
  final ValueChanged<InstalledUpiApp> onPick;

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return Text(
        'This device cannot open a UPI app. Choose QR Payment and scan the '
        'code with your phone.',
        style: AppTypography.caption,
      );
    }
    // Only the phone's own list: none could be found.
    final noneFound = !searching && apps.every((app) => app.isChooser);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        Text(
          searching ? 'Looking for UPI apps on this phone…' : 'Pay with',
          style: AppTypography.overline.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (noneFound) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No UPI app was found on this phone. Try the phone\'s own list '
            'below, or choose QR Payment and scan the code from another '
            'phone.',
            key: const ValueKey('upi-apps-none'),
            style: AppTypography.caption,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        for (final app in apps)
          _UpiAppTile(
            key: ValueKey('upi-app-${app.key}'),
            app: app,
            chosen: app == chosen,
            amount: amount,
            prefills: prefills,
            onTap: busy ? null : () => onPick(app),
          ),
      ],
    );
  }
}

class _UpiAppTile extends StatelessWidget {
  const _UpiAppTile({
    super.key,
    required this.app,
    required this.chosen,
    required this.amount,
    required this.prefills,
    required this.onTap,
  });

  final InstalledUpiApp app;
  final bool chosen;
  final String amount;
  final bool prefills;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      label: 'Pay $amount with ${app.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _UpiAppIcon(app: app),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label,
                    ),
                    Text(
                      app.isChooser
                          ? 'Choose from the UPI apps on this phone'
                          : prefills
                          ? 'Opens with $amount filled in'
                          : 'Pay $amount to the UPI ID shown next',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                chosen
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 22,
                color: chosen ? AppColors.primary : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An app's own icon where the phone lends it (Android); otherwise its
/// initial in its colours, or a plain mark for the phone's list.
class _UpiAppIcon extends StatelessWidget {
  const _UpiAppIcon({required this.app});

  final InstalledUpiApp app;

  static const _size = 36.0;

  // The apps' own colours, so guests find theirs at a glance.
  static const _colors = {
    UpiApp.googlePay: Color(0xFF1A73E8),
    UpiApp.phonePe: Color(0xFF5F259F),
    UpiApp.paytm: Color(0xFF00BAF2),
  };

  @override
  Widget build(BuildContext context) {
    final fallback = _fallback();
    final icon = app.icon;
    if (icon == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Image.memory(
        icon,
        width: _size,
        height: _size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _fallback() {
    if (app.isChooser) {
      return const CircleAvatar(
        radius: _size / 2,
        backgroundColor: AppColors.softWhite,
        child: Icon(
          Icons.apps_rounded,
          size: 20,
          color: AppColors.textSecondary,
        ),
      );
    }
    final color = _colors[app.known];
    return CircleAvatar(
      radius: _size / 2,
      backgroundColor: color ?? AppColors.softWhite,
      child: Text(
        app.label.isEmpty ? '?' : app.label.characters.first.toUpperCase(),
        style: AppTypography.cardTitle.copyWith(
          color: color == null ? AppColors.textSecondary : Colors.white,
        ),
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.card,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.orangeSoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: const Icon(
                Icons.call_split_rounded,
                size: 20,
                color: AppColors.orangeText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Split payment', style: AppTypography.cardTitle),
                  Text(
                    'Pay with two or more methods, e.g. cash + UPI',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key, required this.simulated, this.counter = false});

  final bool simulated;
  final bool counter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DineQrMark(size: 96, sheen: 0.5),
            const SizedBox(height: AppSpacing.xl),
            QrPulseLoader(
              size: 30,
              color: AppColors.primary,
              semanticLabel: counter
                  ? 'Letting staff know'
                  : 'Confirming payment',
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              counter
                  ? 'Letting the staff know…'
                  : simulated
                  ? 'Confirming your demo payment…'
                  : 'Confirming your payment…',
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              counter
                  ? 'Nothing is charged here.'
                  : simulated
                  ? 'The demo simulator is processing it. No money moves.'
                  : 'Please keep this screen open.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    super.key,
    required this.success,
    required this.title,
    required this.invoice,
    required this.transaction,
    required this.onPrimary,
    required this.primaryLabel,
    required this.onSecondary,
    required this.secondaryLabel,
    this.message,
  });

  final bool success;
  final String title;
  final String? message;
  final Invoice invoice;
  final PaymentTransaction? transaction;
  final VoidCallback onPrimary;
  final String primaryLabel;
  final VoidCallback onSecondary;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: success
              ? SuccessEmblem(size: 96, semanticLabel: title)
              : const IconHalo(icon: Icons.error_outline_rounded),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title, textAlign: TextAlign.center, style: AppTypography.headline),
        const SizedBox(height: AppSpacing.sm),
        if (message != null && message!.isNotEmpty)
          Text(
            message!,
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
        if (success && t != null) ...[
          Text(
            '${CurrencyFormatter.format(t.amount)} paid by ${t.methodLabel}',
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.isSimulated) ...[
                  const DemoTag(label: 'DEMO PAYMENT'),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _Fact(
                  t.isSimulated ? 'Demo transaction ref' : 'Reference',
                  t.reference.isEmpty ? '—' : t.reference,
                ),
                _Fact('Method', t.methodLabel),
                _Fact('Amount', CurrencyFormatter.format(t.amount)),
                _Fact('Bill', invoice.billNumber),
                _Fact('Paid at', AppFormat.dateTime(t.updatedAt)),
                _Fact(
                  'Balance due',
                  CurrencyFormatter.format(invoice.outstanding),
                ),
                if (t.isSimulated) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Simulated demo payment, not verified by any bank or '
                    'payment provider. No money was charged or transferred.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.info,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Center(child: PaymentStatusBadge(status: invoice.status)),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: primaryLabel, onPressed: onPrimary),
        const SizedBox(height: AppSpacing.md),
        SecondaryButton(label: secondaryLabel, onPressed: onSecondary),
      ],
    );
  }
}

/// After choosing cash or the counter: what happens next.
class _CounterResult extends StatelessWidget {
  const _CounterResult({
    super.key,
    required this.invoice,
    required this.simulated,
    required this.onDone,
    required this.onPayOnline,
  });

  final Invoice invoice;
  final bool simulated;
  final VoidCallback onDone;
  final VoidCallback? onPayOnline;

  @override
  Widget build(BuildContext context) {
    final request = invoice.openCounterRequest;
    final cash = request?.kind == CounterRequestKind.cash;
    final amount = CurrencyFormatter.format(
      request?.amount ?? invoice.payableNow,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xl,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: IconHalo(
            icon: cash ? Icons.payments_rounded : Icons.storefront_rounded,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          cash ? 'Pay $amount in cash' : 'Pay $amount at the counter',
          textAlign: TextAlign.center,
          style: AppTypography.headline,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          cash
              ? 'Hand the cash to your server or pay at the counter. Staff '
                    'have been told.'
              : 'Pay at the counter by any method they take. Staff have been '
                    'told.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.xl),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact('Bill', invoice.billNumber),
              _Fact('To pay at the counter', amount),
              _Fact('Status', invoice.status.label),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Nothing has been paid yet. The bill updates here as soon as '
                'the cashier records your payment.'
                '${simulated ? ' In demo mode their record is a demo payment '
                          'too.' : ''}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(child: PaymentStatusBadge(status: invoice.status)),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: 'Back to bill', onPressed: onDone),
        if (onPayOnline != null) ...[
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(label: 'Pay online instead', onPressed: onPayOnline),
        ],
      ],
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
