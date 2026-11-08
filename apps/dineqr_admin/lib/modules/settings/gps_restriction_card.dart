import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/admin_widgets.dart';
import 'maps/maps_loader.dart';

/// The Google Maps key, from `--dart-define=GOOGLE_MAPS_API_KEY=...` (the
/// Android build reads the same define; see build.gradle.kts).
const _mapsKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// Whether a map can be shown: a key, on the web or Android. iOS needs the
/// key in the native project as well, so it uses coordinates.
bool get _mapSupported =>
    _mapsKey.isNotEmpty &&
    (kIsWeb || defaultTargetPlatform == TargetPlatform.android);

/// GPS Location & Ordering Restrictions: guests may order only from within
/// a radius of the restaurant, measured by the server from the position the
/// guest's phone sends with each order. Independent of the Wi-Fi
/// restriction ([WifiRestrictionCard]): with both on, an order must pass
/// both. Saved separately from the rest of the page.
class GpsRestrictionCard extends StatefulWidget {
  const GpsRestrictionCard({super.key});

  @override
  State<GpsRestrictionCard> createState() => _GpsRestrictionCardState();
}

class _GpsRestrictionCardState extends State<GpsRestrictionCard> {
  late final GeofenceSettingsController _controller = context
      .read<GeofenceSettingsController>();

  bool _enabled = false;
  bool _takeaway = false;
  int _radius = 50;
  bool _custom = false;
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _customRadius = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  bool _locating = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _adopt(_controller.settings);
    if (_controller.isAvailable && !_controller.isLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    _customRadius.dispose();
    super.dispose();
  }

  void _adopt(GeofenceSettings settings) {
    _enabled = settings.enabled;
    _takeaway = settings.takeaway;
    _radius = settings.radius;
    _custom = !GeofenceSettings.presets.contains(settings.radius);
    _customRadius.text = _custom ? '${settings.radius}' : '';
    _latitude.text = settings.latitude?.toStringAsFixed(6) ?? '';
    _longitude.text = settings.longitude?.toStringAsFixed(6) ?? '';
  }

  double? get _lat => double.tryParse(_latitude.text.trim());
  double? get _lng => double.tryParse(_longitude.text.trim());

  /// A pin dropped on the map, or this device's position.
  void _setPoint(double latitude, double longitude) => setState(() {
    _latitude.text = latitude.toStringAsFixed(6);
    _longitude.text = longitude.toStringAsFixed(6);
  });

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _controller.load();
      if (mounted) setState(() => _adopt(_controller.settings));
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _loadError = switch (error) {
            ValidationException(:final message) => message,
            ApiException(:final message) => message,
            _ => 'The GPS restriction could not be loaded.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useThisDevice() async {
    setState(() => _locating = true);
    final reading = await context.read<LocationProvider>().current();
    if (!mounted) return;
    setState(() => _locating = false);
    final position = reading.position;
    if (position == null) {
      showAppSnackBar(context, switch (reading.failure!) {
        LocationFailure.serviceDisabled =>
          'Turn on location on this device, or pick the restaurant on the map.',
        LocationFailure.permissionDenied ||
        LocationFailure.permissionDeniedForever =>
          'Allow DineQR Admin to use this device\'s location, or enter the '
              'coordinates.',
        LocationFailure.unavailable =>
          'This device\'s location could not be read.',
      }, icon: Icons.location_off_rounded);
      return;
    }
    _setPoint(position.latitude, position.longitude);
    showAppSnackBar(
      context,
      'Location set (±${position.accuracy.round()} m). Check the pin before '
      'saving.',
      icon: Icons.my_location_rounded,
    );
  }

  Future<void> _openInMaps() async {
    final lat = _lat;
    final lng = _lng;
    if (!GeofenceSettings.isValidPoint(lat, lng)) return;
    await launchUrl(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$lat,$lng',
      }),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _save() async {
    final radius = _custom
        ? int.tryParse(_customRadius.text.trim()) ?? 0
        : _radius;
    final lat = _lat;
    final lng = _lng;
    final next = GeofenceSettings(
      enabled: _enabled,
      latitude: lat,
      longitude: lng,
      radius: radius,
      takeaway: _takeaway,
    );
    if (_enabled && !_controller.settings.enabled) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Switch the GPS restriction on?',
        message:
            'Guests will have to allow location and be within $radius m of '
            'the pin to place an order. Check the pin is on the restaurant: '
            'phones are often 10–30 m off indoors, so a very small radius may '
            'refuse guests at the far tables.',
        confirmLabel: 'Switch on',
        icon: Icons.location_on_rounded,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _saving = true);
    final ok = await runAdminAction(
      context,
      () => _controller.save(next),
      success: 'GPS configuration saved',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _adopt(_controller.settings);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<GeofenceSettingsController>();
    const title = 'GPS Location & Ordering Restrictions';
    const subtitle =
        "Guests can place orders only within a set distance of the "
        "restaurant, measured by the server from the guest's GPS position. "
        'Works alongside the Wi-Fi restriction: with both on, an order must '
        'pass both.';
    if (!_controller.isAvailable) {
      return const SectionCard(
        title: title,
        subtitle: subtitle,
        child: Text(
          'Needs the DineQR server, which checks every order. It is not part '
          'of the offline demo.',
        ),
      );
    }
    if (_loading && !_controller.isLoaded) {
      return const SectionCard(
        title: title,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null && !_controller.isLoaded) {
      return SectionCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_loadError!, style: AppTypography.caption),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final saved = _controller.settings;
    final lat = _lat;
    final lng = _lng;
    final point = GeofenceSettings.isValidPoint(lat, lng)
        ? LatLng(lat!, lng!)
        : null;
    final radius = _custom
        ? int.tryParse(_customRadius.text.trim()) ?? _radius
        : _radius;
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            'Restaurant',
            saved.restaurantName.isEmpty ? '—' : saved.restaurantName,
          ),
          Text(
            'The name is changed under Restaurant details above.',
            style: AppTypography.caption,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            activeThumbColor: AppColors.primary,
            onChanged: (value) => setState(() => _enabled = value),
            title: Text(
              'Enable GPS restriction',
              style: AppTypography.cardTitle,
            ),
            subtitle: Text(
              'Off: guests order from anywhere, as before.',
              style: AppTypography.caption,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _takeaway,
            activeThumbColor: AppColors.primary,
            onChanged: (value) => setState(() => _takeaway = value),
            title: Text(
              'Include takeaway orders',
              style: AppTypography.cardTitle,
            ),
            subtitle: Text(
              'Off: takeaway guests can order from anywhere.',
              style: AppTypography.caption,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Restaurant location', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _mapSupported
                ? 'Tap the map (or drag the pin) to drop it on the restaurant; '
                      'the coordinates fill in by themselves.'
                : 'Enter the coordinates, or use this device\'s location while '
                      'at the restaurant. (A map appears when the app is built '
                      'with a Google Maps API key.)',
            style: AppTypography.caption,
          ),
          if (_mapSupported) ...[
            const SizedBox(height: AppSpacing.sm),
            _MapPicker(point: point, radius: radius, onPick: _setPoint),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    hintText: 'e.g. 13.082700',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    hintText: 'e.g. 80.270700',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: _locating ? null : _useThisDevice,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: const Text("Use this device's location"),
              ),
              if (point != null)
                TextButton.icon(
                  onPressed: _openInMaps,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Open in Google Maps'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Ordering radius', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final preset in GeofenceSettings.presets)
                ChoiceChip(
                  label: Text('$preset m'),
                  selected: !_custom && _radius == preset,
                  onSelected: (_) => setState(() {
                    _custom = false;
                    _radius = preset;
                  }),
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _custom,
                onSelected: (_) => setState(() {
                  _custom = true;
                  if (_customRadius.text.isEmpty) {
                    _customRadius.text = '$_radius';
                  }
                }),
              ),
            ],
          ),
          if (_custom)
            TextField(
              controller: _customRadius,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Radius in metres (10 to 1000)',
                suffixText: 'm',
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Phones are usually accurate to 5–20 m outdoors and less indoors, '
            'so 30–50 m suits most restaurants. The server allows for part of '
            'that uncertainty, refuses readings that are too vague, out of '
            'date or from a mock-location app, and never stores positions.',
            style: AppTypography.caption,
          ),
          if (saved.updatedAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Last saved ${AppFormat.dateTime(saved.updatedAt!)}'
              '${saved.updatedBy.isEmpty ? '' : ' by ${saved.updatedBy}'}'
              '${saved.createdAt == null ? '' : ' · set up ${AppFormat.date(saved.createdAt!)}'}',
              style: AppTypography.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Save GPS configuration',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Google Maps with a draggable pin and the radius drawn around it.
class _MapPicker extends StatefulWidget {
  const _MapPicker({
    required this.point,
    required this.radius,
    required this.onPick,
  });

  final LatLng? point;
  final int radius;
  final void Function(double latitude, double longitude) onPick;

  @override
  State<_MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<_MapPicker> {
  late final Future<bool> _ready = ensureGoogleMapsLoaded(_mapsKey);
  GoogleMapController? _map;

  /// India, when no location is set yet.
  static const _fallback = LatLng(20.5937, 78.9629);

  @override
  void didUpdateWidget(_MapPicker old) {
    super.didUpdateWidget(old);
    final point = widget.point;
    // Coordinates typed in, or this device's location: follow them.
    if (point != null && point != old.point) {
      _map?.animateCamera(CameraUpdate.newLatLng(point));
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  void _pick(LatLng at) => widget.onPick(at.latitude, at.longitude);

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: SizedBox(
        height: 300,
        child: FutureBuilder<bool>(
          future: _ready,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data != true) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Google Maps could not be loaded (check the API key and '
                    'the connection). Enter the coordinates below instead.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return GoogleMap(
              initialCameraPosition: CameraPosition(
                target: point ?? _fallback,
                zoom: point == null ? 4 : 18,
              ),
              onMapCreated: (controller) => _map = controller,
              onTap: _pick,
              myLocationButtonEnabled: false,
              // Scroll and zoom the map, not the page around it.
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
              markers: {
                if (point != null)
                  Marker(
                    markerId: const MarkerId('restaurant'),
                    position: point,
                    draggable: true,
                    onDragEnd: _pick,
                    infoWindow: const InfoWindow(title: 'Restaurant'),
                  ),
              },
              circles: {
                if (point != null)
                  Circle(
                    circleId: const CircleId('radius'),
                    center: point,
                    radius: widget.radius.toDouble(),
                    strokeWidth: 2,
                    strokeColor: AppColors.primary,
                    fillColor: AppColors.primary.withValues(alpha: 0.12),
                  ),
              },
            );
          },
        ),
      ),
    );
  }
}
