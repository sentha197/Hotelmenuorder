import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/app_typography.dart';
import '../../core/animations/brand_effects.dart';
import '../../core/animations/motion.dart';
import '../../core/brand/dineqr_logo.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/table_qr_code.dart';
import '../../state/session_controller.dart';
import 'demo_qr_sheet.dart';
import 'table_qr_parser.dart';

enum _CameraIssue { unsupported, permissionDenied, failed }

/// Screen 2: scans the table QR code with the camera, or lets the guest pick
/// a demo code when no camera / code is available.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, this.enableCamera});

  /// Forces the camera on or off. Defaults to on for platforms supported by
  /// mobile_scanner (Android, iOS, macOS, web).
  final bool? enableCamera;

  static bool get platformHasCamera =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _controller;
  late final AnimationController _scanLine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  bool _handled = false;
  int? _detectedTable;
  String? _error;
  int _errorCount = 0;
  Timer? _errorTimer;
  String? _lastInvalid;
  DateTime? _lastInvalidAt;

  @override
  void initState() {
    super.initState();
    final enable =
        widget.enableCamera ??
        (context.read<AppConfig>().enableCamera &&
            QrScannerScreen.platformHasCamera);
    if (enable) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _scanLine.stop();
    } else if (!_scanLine.isAnimating && _detectedTable == null) {
      _scanLine.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _scanLine.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handlePayload(raw);
        return;
      }
    }
  }

  Future<void> _handlePayload(String? raw) async {
    if (_handled) return;
    switch (TableQrParser.parse(raw)) {
      case ValidTableQr(:final tableNumber):
        _handled = true;
        _errorTimer?.cancel();
        HapticFeedback.mediumImpact();
        _scanLine.stop();
        setState(() {
          _detectedTable = tableNumber;
          _error = null;
        });
        final controller = _controller;
        if (controller != null && controller.value.isRunning) {
          unawaited(controller.stop().catchError((Object _) {}));
        }
        await Future<void>.delayed(
          Motion.reduced(context)
              ? const Duration(milliseconds: 300)
              : const Duration(milliseconds: 900),
        );
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacementNamed(Routes.welcome, arguments: tableNumber);
      case InvalidTableQr(:final error):
        // The camera keeps reporting the same wrong code; only react once
        // every few seconds.
        final now = DateTime.now();
        if (raw == _lastInvalid &&
            _lastInvalidAt != null &&
            now.difference(_lastInvalidAt!) < const Duration(seconds: 3)) {
          return;
        }
        _lastInvalid = raw;
        _lastInvalidAt = now;
        HapticFeedback.heavyImpact();
        _showError(error.message);
    }
  }

  void _showError(String message) {
    setState(() {
      _error = message;
      _errorCount++;
    });
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _error = null);
    });
  }

  Future<void> _toggleTorch(bool running) async {
    final controller = _controller;
    if (controller == null || !running) {
      showAppSnackBar(
        context,
        'The flashlight works while the camera is active.',
        icon: Icons.flashlight_off_rounded,
      );
      return;
    }
    try {
      await controller.toggleTorch();
    } on Object {
      if (mounted) {
        showAppSnackBar(context, 'This device has no flashlight available.');
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final controller = _controller;
    if (controller == null || kIsWeb) {
      showAppSnackBar(
        context,
        'Scanning from photos needs the Android or iOS app. Try a demo QR code.',
        icon: Icons.photo_library_outlined,
        actionLabel: 'DEMO',
        onAction: _openDemoCodes,
      );
      return;
    }
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final capture = await controller.analyzeImage(file.path);
      final raw = capture?.barcodes
          .map((barcode) => barcode.rawValue)
          .firstWhere((value) => value != null, orElse: () => null);
      if (!mounted) return;
      if (raw == null) {
        _showError('No QR code was found in that photo.');
        return;
      }
      await _handlePayload(raw);
    } on Object {
      if (mounted) _showError('That photo could not be read. Try another one.');
    }
  }

  void _openDemoCodes() {
    if (_handled) return;
    showDemoQrSheet(context, onSelect: _handlePayload);
  }

  Future<void> _retryCamera() async {
    try {
      await _controller?.start();
    } on Object {
      // The error state is reported through the controller value.
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedTable = context.watch<SessionController>().tableNumber;
    final controller = _controller;
    if (controller == null) {
      return _buildBody(
        issue: _CameraIssue.unsupported,
        running: false,
        savedTable: savedTable,
      );
    }
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final error = state.error;
        final issue = error == null
            ? null
            : switch (error.errorCode) {
                MobileScannerErrorCode.permissionDenied =>
                  _CameraIssue.permissionDenied,
                MobileScannerErrorCode.unsupported => _CameraIssue.unsupported,
                _ => _CameraIssue.failed,
              };
        return _buildBody(
          issue: issue,
          running: state.isRunning,
          torchOn: state.torchState == TorchState.on,
          savedTable: savedTable,
        );
      },
    );
  }

  Widget _buildBody({
    required _CameraIssue? issue,
    required bool running,
    required int? savedTable,
    bool torchOn = false,
  }) {
    final controller = _controller;
    final demoMode = issue != null;
    final canPop = Navigator.of(context).canPop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final side = (constraints.maxWidth * 0.72).clamp(220.0, 300.0);
            final frame = Rect.fromCenter(
              center: Offset(
                constraints.maxWidth / 2,
                constraints.maxHeight * 0.44,
              ),
              width: side,
              height: side * 1.12,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null)
                  MobileScanner(
                    controller: controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => const _DemoBackdrop(),
                    placeholderBuilder: (context) =>
                        const ColoredBox(color: Colors.black),
                  )
                else
                  const _DemoBackdrop(),
                CustomPaint(painter: _ScrimPainter(frame)),
                Positioned.fromRect(
                  rect: frame,
                  child: _ScanFrame(
                    scanLine: _scanLine,
                    detectedTable: _detectedTable,
                    child: demoMode
                        ? _DemoTableCard(
                            onTap: () =>
                                _handlePayload(TableQrParser.payloadFor(5)),
                          )
                        : null,
                  ),
                ),
                // Header: brand lockup, title and instruction.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                if (canPop)
                                  const AppBackButton(color: Colors.white)
                                else
                                  const SizedBox(width: 48),
                                const Expanded(
                                  child: Center(
                                    child: FadeSlideIn(
                                      offset: Offset(0, -0.3),
                                      child: DineQrLockup(
                                        height: 30,
                                        onDark: true,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 48),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FadeSlideIn(
                            index: 1,
                            child: Text(
                              'Scan QR Code',
                              textAlign: TextAlign.center,
                              style: AppTypography.screenTitle.copyWith(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          FadeSlideIn(
                            index: 2,
                            child: Text(
                              'Point your camera at the table QR code',
                              textAlign: TextAlign.center,
                              style: AppTypography.bodySecondary.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Error / camera notices under the frame.
                Positioned(
                  left: AppSpacing.page,
                  right: AppSpacing.page,
                  top: frame.bottom + AppSpacing.lg,
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.medium),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        child: child,
                      ),
                    ),
                    child: _error != null
                        ? ShakeOnChange(
                            key: const ValueKey('error'),
                            trigger: _errorCount,
                            child: _Notice(
                              icon: Icons.error_outline_rounded,
                              color: AppColors.error,
                              message: _error!,
                              actionLabel: 'Try again',
                              onAction: () => setState(() => _error = null),
                            ),
                          )
                        : issue != null && _detectedTable == null
                        ? _Notice(
                            key: ValueKey(issue),
                            icon: Icons.no_photography_outlined,
                            color: Colors.white,
                            message: switch (issue) {
                              _CameraIssue.unsupported =>
                                'No camera here. Tap the table card or use a demo code.',
                              _CameraIssue.permissionDenied =>
                                'Camera access is off. Allow it in Settings, or use a demo code.',
                              _CameraIssue.failed =>
                                'The camera could not start. Retry or use a demo code.',
                            },
                            actionLabel: issue == _CameraIssue.unsupported
                                ? null
                                : 'Retry',
                            onAction: _retryCamera,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                // Bottom controls.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        0,
                        AppSpacing.page,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _RoundControl(
                                icon: torchOn
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                label: torchOn
                                    ? 'Turn flash off'
                                    : 'Turn flash on',
                                active: torchOn,
                                onTap: () => _toggleTorch(running),
                              ),
                              const SizedBox(width: 56),
                              _RoundControl(
                                icon: Icons.photo_library_outlined,
                                label: 'Scan from photos',
                                onTap: _pickFromGallery,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _GlassButton(
                            icon: Icons.qr_code_2_rounded,
                            label: 'Use a demo QR code',
                            onTap: _openDemoCodes,
                          ),
                          if (savedTable != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            TextButton(
                              onPressed: () => _handlePayload(
                                TableQrParser.payloadFor(savedTable),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                textStyle: AppTypography.label,
                              ),
                              child: Text(
                                'Continue at Table ${AppFormat.table(savedTable)}',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Blurred restaurant photo used when there is no live camera feed.
class _DemoBackdrop extends StatelessWidget {
  const _DemoBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Image.asset(
            'assets/images/splash_bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: AppColors.ember),
          ),
        ),
        ColoredBox(color: AppColors.scrim.withValues(alpha: 0.55)),
      ],
    );
  }
}

/// Darkens everything outside the scan window.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(22)));
    canvas.drawPath(
      path,
      Paint()..color = AppColors.scrim.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) => oldDelegate.frame != frame;
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame({
    required this.scanLine,
    required this.detectedTable,
    this.child,
  });

  final Animation<double> scanLine;
  final int? detectedTable;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final success = detectedTable != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (child != null)
          AnimatedOpacity(
            opacity: success ? 0 : 1,
            duration: Motion.of(context, Motion.fast),
            child: Center(child: child),
          ),
        // Red-orange scan line with a soft wake behind it.
        if (!success)
          AnimatedBuilder(
            animation: scanLine,
            builder: (context, _) => CustomPaint(
              painter: _ScanLinePainter(
                Curves.easeInOut.transform(scanLine.value),
                downward: scanLine.status != AnimationStatus.reverse,
              ),
            ),
          ),
        // Corners draw in once, then turn green on success.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Motion.brand,
          builder: (context, draw, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: success ? 1 : 0),
            duration: Motion.of(context, Motion.medium),
            builder: (context, done, _) => CustomPaint(
              painter: _CornerPainter(draw: draw, success: done),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.medium),
          child: success
              ? Container(
                  key: const ValueKey('success'),
                  decoration: BoxDecoration(
                    color: AppColors.scrim.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SuccessEmblem.green(
                        size: 70,
                        semanticLabel: 'Table detected',
                      ),
                      Text(
                        'Table ${AppFormat.table(detectedTable!)} detected',
                        style: AppTypography.sectionTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Opening your table…',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter(this.t, {required this.downward});

  final double t;
  final bool downward;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 16.0;
    final y = inset + (size.height - inset * 2) * t;
    // Wake: a faint gradient trailing behind the direction of travel.
    const wake = 46.0;
    final wakeRect = downward
        ? Rect.fromLTRB(inset, y - wake, size.width - inset, y)
        : Rect.fromLTRB(inset, y, size.width - inset, y + wake);
    canvas.drawRect(
      wakeRect,
      Paint()
        ..shader = LinearGradient(
          begin: downward ? Alignment.bottomCenter : Alignment.topCenter,
          end: downward ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            AppColors.vibrantOrange.withValues(alpha: 0.22),
            AppColors.vibrantOrange.withValues(alpha: 0),
          ],
        ).createShader(wakeRect),
    );
    final line = Rect.fromLTRB(inset, y - 1.5, size.width - inset, y + 1.5);
    final gradient = LinearGradient(
      colors: [
        AppColors.accentRed.withValues(alpha: 0),
        AppColors.accentRed,
        AppColors.warmOrange,
        AppColors.accentRed,
        AppColors.accentRed.withValues(alpha: 0),
      ],
      stops: const [0, 0.25, 0.5, 0.75, 1],
    ).createShader(line);
    canvas.drawRRect(
      RRect.fromRectAndRadius(line.inflate(3), const Radius.circular(4)),
      Paint()
        ..shader = gradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(line, const Radius.circular(2)),
      Paint()..shader = gradient,
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.downward != downward;
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.draw, required this.success});

  /// 0-1: how much of each corner bracket is drawn.
  final double draw;

  /// 0-1: blend from the brand gradient to success green.
  final double success;

  @override
  void paint(Canvas canvas, Size size) {
    if (draw <= 0) return;
    const length = 38.0;
    const radius = 22.0;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final from = Color.lerp(AppColors.accentRed, AppColors.success, success)!;
    final to = Color.lerp(
      AppColors.warmOrange,
      AppColors.successLight,
      success,
    )!;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [from, to],
      ).createShader(rect);

    // Each bracket grows outward from its corner.
    final reach = radius + (length - radius) * draw;
    void bracket(Offset start, Offset arcFrom, Offset arcTo, Offset end) {
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(arcFrom.dx, arcFrom.dy)
        ..arcToPoint(arcTo, radius: const Radius.circular(radius))
        ..lineTo(end.dx, end.dy);
      final metric = path.computeMetrics().first;
      final visible = metric.length * draw.clamp(0.0, 1.0);
      final offset = (metric.length - visible) / 2;
      canvas.drawPath(metric.extractPath(offset, offset + visible), paint);
    }

    bracket(
      Offset(0, reach),
      const Offset(0, radius),
      const Offset(radius, 0),
      Offset(reach, 0),
    );
    bracket(
      Offset(w - reach, 0),
      Offset(w - radius, 0),
      Offset(w, radius),
      Offset(w, reach),
    );
    bracket(
      Offset(w, h - reach),
      Offset(w, h - radius),
      Offset(w - radius, h),
      Offset(w - reach, h),
    );
    bracket(
      Offset(reach, h),
      Offset(radius, h),
      Offset(0, h - radius),
      Offset(0, h - reach),
    );
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) =>
      oldDelegate.draw != draw || oldDelegate.success != success;
}

/// The DineQR table tent shown inside the frame in demo mode, carrying a
/// real Table 05 code. Tapping it simulates scanning that code.
class _DemoTableCard extends StatelessWidget {
  const _DemoTableCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Simulate scanning the Table 05 QR code',
      child: FractionallySizedBox(
        widthFactor: 0.74,
        heightFactor: 0.86,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            boxShadow: AppShadows.floating,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                height: 6,
                decoration: const BoxDecoration(
                  gradient: AppColors.emberGradient,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const DineQrLockup(height: 26),
                        const SizedBox(height: 8),
                        TableQrCode(
                          payload: TableQrParser.payloadFor(5),
                          size: 112,
                          semanticLabel: 'Table 05 QR code',
                        ),
                        const SizedBox(height: 6),
                        Text('Scan to Order', style: AppTypography.cardTitle),
                        Text(
                          'Table 05 · Tap to simulate',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isError = color == AppColors.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: isError ? Colors.white : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: isError
                ? AppColors.error
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTypography.label.copyWith(
                  color: isError ? AppColors.textPrimary : Colors.white,
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: isError ? AppColors.primary : AppColors.gold,
                  textStyle: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      scale: 0.9,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Icon(
          icon,
          color: active ? AppColors.textPrimary : Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        decoration: BoxDecoration(
          gradient: AppColors.ctaGradient,
          borderRadius: AppRadii.pill,
          boxShadow: [
            const BoxShadow(color: AppColors.lip, offset: Offset(0, 3)),
            ...AppShadows.glow(AppColors.vibrantOrange),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
