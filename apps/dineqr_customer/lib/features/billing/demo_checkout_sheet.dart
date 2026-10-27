import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the guest chose in a demo checkout: the simulated outcome and the
/// method detail recorded with the payment (e.g. a bank name).
class DemoCheckout {
  const DemoCheckout(this.outcome, this.detail);

  final SimulatedOutcome outcome;
  final String detail;
}

/// Opens the demo checkout for an online [option]: a UPI ID or a Scan & Pay
/// QR code, a demo card, a bank or a wallet. The payment is only made after
/// the guest confirms here; closing the sheet records nothing.
///
/// Nothing in it can move money: the QR code is not a UPI payment request,
/// the UPI ID is not a real account, and it never asks for a card number,
/// CVV, UPI PIN or banking password.
Future<DemoCheckout?> showDemoCheckout(
  BuildContext context, {
  required PaymentOption option,
  required Money amount,
  required Invoice invoice,
}) => showBrandSheet<DemoCheckout>(
  context,
  builder: (_) =>
      _DemoCheckoutSheet(option: option, amount: amount, invoice: invoice),
);

/// The restaurant's UPI ID in demo mode: shown, never payable.
const demoUpiId = 'dineqr.demo@demo';

const _demoBanks = [
  'HDFC Bank',
  'ICICI Bank',
  'State Bank of India',
  'Axis Bank',
  'Kotak Mahindra Bank',
];

const _demoWallets = ['Paytm', 'PhonePe', 'Amazon Pay', 'MobiKwik'];

class _DemoCheckoutSheet extends StatefulWidget {
  const _DemoCheckoutSheet({
    required this.option,
    required this.amount,
    required this.invoice,
  });

  final PaymentOption option;
  final Money amount;
  final Invoice invoice;

  @override
  State<_DemoCheckoutSheet> createState() => _DemoCheckoutSheetState();
}

class _DemoCheckoutSheetState extends State<_DemoCheckoutSheet> {
  bool _credit = true;
  String _bank = _demoBanks.first;
  String _wallet = _demoWallets.first;

  // A fresh reference each time the sheet opens, so two QR codes never
  // look alike.
  final _qrRef = Ids.random(8);

  String get _detail => switch (widget.option) {
    PaymentOption.card => _credit ? 'Credit' : 'Debit',
    PaymentOption.netBanking => _bank,
    PaymentOption.wallet => _wallet,
    _ => widget.option.detail,
  };

  void _finish(SimulatedOutcome outcome) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(DemoCheckout(outcome, _detail));
  }

  /// A demo payload: deliberately not a `upi://pay` request, so no UPI app
  /// can start a real transfer from it.
  String get _qrPayload =>
      'DINEQR-DEMO-PAYMENT|NOT-A-REAL-PAYMENT-REQUEST'
      '|bill=${widget.invoice.billNumber}'
      '|amount=${CurrencyFormatter.plain(widget.amount)}'
      '|currency=${CurrencyFormatter.code}|ref=$_qrRef';

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(option.icon, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option == PaymentOption.scanAndPay
                            ? 'Scan & Pay'
                            : 'Pay by ${option.label}',
                        style: AppTypography.sectionTitle,
                      ),
                      Text(
                        '${CurrencyFormatter.format(widget.amount)} · '
                        'Bill ${widget.invoice.billNumber}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                const DemoTag(label: 'DEMO PAYMENT'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            switch (option) {
              PaymentOption.upi => _UpiBody(
                payload: _qrPayload,
                amount: widget.amount,
              ),
              PaymentOption.scanAndPay => _ScanBody(
                payload: _qrPayload,
                amount: widget.amount,
              ),
              PaymentOption.card => _CardBody(
                credit: _credit,
                onChanged: (credit) => setState(() => _credit = credit),
              ),
              PaymentOption.netBanking => _ChoiceList(
                title: 'Choose your bank',
                choices: _demoBanks,
                selected: _bank,
                icon: Icons.account_balance_rounded,
                onChanged: (bank) => setState(() => _bank = bank),
              ),
              PaymentOption.wallet => _ChoiceList(
                title: 'Choose your wallet',
                choices: _demoWallets,
                selected: _wallet,
                icon: Icons.account_balance_wallet_rounded,
                onChanged: (wallet) => setState(() => _wallet = wallet),
              ),
              PaymentOption.cash ||
              PaymentOption.payAtCounter => const SizedBox.shrink(),
            },
            const SizedBox(height: AppSpacing.lg),
            _SafetyNote(option: option),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Confirm demo payment',
              icon: Icons.check_circle_rounded,
              onPressed: () => _finish(SimulatedOutcome.success),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.md,
              children: [
                TextButton.icon(
                  onPressed: () => _finish(SimulatedOutcome.failure),
                  icon: const Icon(Icons.error_outline_rounded, size: 18),
                  label: const Text('Simulate failure'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
                TextButton.icon(
                  onPressed: () => _finish(SimulatedOutcome.cancel),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Cancel payment'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpiBody extends StatelessWidget {
  const _UpiBody({required this.payload, required this.amount});

  final String payload;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pay to this UPI ID', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.softWhite,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  demoUpiId,
                  style: AppTypography.cardTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copy UPI ID',
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: demoUpiId));
                  if (context.mounted) {
                    showAppSnackBar(
                      context,
                      'Demo UPI ID copied',
                      icon: Icons.copy_rounded,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            TableQrCode(
              payload: payload,
              size: 112,
              semanticLabel: 'Demo payment QR code',
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Open any UPI app, pay '
                '${CurrencyFormatter.format(amount)} to the ID above, then '
                'confirm below. Or scan the code.',
                style: AppTypography.bodySecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScanBody extends StatelessWidget {
  const _ScanBody({required this.payload, required this.amount});

  final String payload;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.sizeOf(context).width * 0.55).clamp(160.0, 220.0);
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            boxShadow: AppShadows.soft,
          ),
          child: TableQrCode(
            payload: payload,
            size: size,
            semanticLabel: 'Demo Scan and Pay QR code',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Scan with any UPI app',
          style: AppTypography.cardTitle,
          textAlign: TextAlign.center,
        ),
        Text(
          '${CurrencyFormatter.format(amount)} to $demoUpiId',
          style: AppTypography.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.credit, required this.onChanged});

  final bool credit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Credit card'),
              icon: Icon(Icons.credit_card_rounded),
            ),
            ButtonSegment(
              value: false,
              label: Text('Debit card'),
              icon: Icon(Icons.payment_rounded),
            ),
          ],
          selected: {credit},
          showSelectedIcon: false,
          onSelectionChanged: (value) => onChanged(value.first),
        ),
        const SizedBox(height: AppSpacing.md),
        // A test card, shown read-only: nothing here is typed in.
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.emberGradient,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.soft,
          ),
          child: DefaultTextStyle(
            style: AppTypography.label.copyWith(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      credit ? 'DEMO CREDIT CARD' : 'DEMO DEBIT CARD',
                      style: AppTypography.overline.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    const DemoTag(onDark: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '4111  1111  1111  1111',
                  style: AppTypography.sectionTitle.copyWith(
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('DINEQR DEMO GUEST   ·   12/30   ·   CVV •••'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChoiceList extends StatelessWidget {
  const _ChoiceList({
    required this.title,
    required this.choices,
    required this.selected,
    required this.icon,
    required this.onChanged,
  });

  final String title;
  final List<String> choices;
  final String selected;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (value) => onChanged(value ?? selected),
          child: Column(
            children: [
              for (final choice in choices)
                RadioListTile<String>(
                  value: choice,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.primary,
                  secondary: Icon(icon, color: AppColors.textSecondary),
                  title: Text(choice, style: AppTypography.label),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.option});

  final PaymentOption option;

  @override
  Widget build(BuildContext context) {
    final text = switch (option) {
      PaymentOption.upi || PaymentOption.scanAndPay =>
        'Demo UPI ID and QR code: not a real account or payment request. '
            'Scanning it cannot start a payment, and no UPI PIN is asked for.',
      PaymentOption.card =>
        'Demo card: no real card number, expiry date or CVV is asked for or '
            'stored.',
      PaymentOption.netBanking =>
        'No bank is contacted and no banking password is asked for.',
      PaymentOption.wallet =>
        'No wallet is contacted and nothing is debited from it.',
      _ => '',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$text Confirming records a demo payment: no money is charged '
              'or transferred.',
              style: AppTypography.caption.copyWith(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }
}
