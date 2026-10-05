
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/delivery_models.dart';
import '../services/geocoding_service.dart';
import '../services/navigation_service.dart';
import '../services/route_persistence_service.dart';

class RouteMapScreen extends StatefulWidget {
  final DeliveryRoute route;
  final int? currentIndex;
  final int? navigationTargetIndex;

  const RouteMapScreen({
    super.key,
    required this.route,
    this.currentIndex,
    this.navigationTargetIndex,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  MapLibreMapController? _controller;
  StreamSubscription<Position>? _positionSubscription;

  bool _styleLoaded = false;
  bool _gpsEnabled = false;
  bool _following = true;
  bool _is3D = true;
  bool _locatingAddresses = false;
  String? _gpsError;
  Position? _lastPosition;
  GeocodingProgress? _progress;
  int? _navigationTargetIndex;
  NavigationRoute? _navigationRoute;
  bool _loadingNavigation = false;

  @override
  void initState() {
    super.initState();
    _navigationTargetIndex = widget.navigationTargetIndex;
    _startGps();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _gpsError = 'Ative a localização/GPS do celular.';
          _gpsEnabled = false;
        });
      }
      return;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _gpsError = permission == LocationPermission.deniedForever
              ? 'Permissão de localização bloqueada. Libere nas configurações do Android.'
              : 'Permissão de localização negada.';
          _gpsEnabled = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _gpsEnabled = true;
        _gpsError = null;
      });
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    await _positionSubscription?.cancel();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _pushPosition,
      onError: (Object error) {
        if (mounted) {
          setState(() => _gpsError = 'Erro ao ler GPS: $error');
        }
      },
    );

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      ).timeout(const Duration(seconds: 12));

      await _pushPosition(current);
    } catch (_) {
      // O stream continua tentando obter a localização.
    }
  }

  Future<void> _pushPosition(Position position) async {
    _lastPosition = position;

    final controller = _controller;
    if (controller != null && _styleLoaded) {
      await controller.updateManualLocation(
        ManualLocationUpdate(
          target: LatLng(position.latitude, position.longitude),
          horizontalAccuracy: position.accuracy,
          altitude: position.altitude,
          bearing: position.heading,
          speed: position.speed,
        ),
      );

      if (_following) {
        await controller.updateMyLocationTrackingMode(
          MyLocationTrackingMode.trackingGps,
        );

        await controller.setTrackingCameraOptions(
          tilt: _is3D ? 55 : 0,
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    if (mounted) setState(() {});

    if (_styleLoaded &&
        _navigationTargetIndex != null &&
        _navigationRoute == null &&
        !_loadingNavigation) {
      await _startNavigation(_navigationTargetIndex!);
    }
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    final controller = _controller;
    if (controller == null) return;

    await controller.setSymbolTextAllowOverlap(true);
    await controller.setSymbolTextIgnorePlacement(true);

    final routePoints = widget.route.stops
        .where((s) => s.latitude != null && s.longitude != null)
        .map((s) => LatLng(s.latitude!, s.longitude!))
        .toList();

    if (routePoints.length > 1) {
      await controller.addLine(
        LineOptions(
          geometry: routePoints,
          lineColor: '#1565C0',
          lineWidth: 5,
          lineOpacity: 0.9,
        ),
      );
    }

    for (var i = 0; i < widget.route.stops.length; i++) {
      final stop = widget.route.stops[i];
      if (stop.latitude == null || stop.longitude == null) continue;

      final isCurrent = widget.currentIndex == i;
      final isDelivered = stop.completed;

      await controller.addCircle(
        CircleOptions(
          geometry: LatLng(stop.latitude!, stop.longitude!),
          circleRadius: isCurrent ? 11 : 9,
          circleColor: isDelivered
              ? '#9E9E9E'
              : (isCurrent ? '#F57C00' : '#1565C0'),
          circleOpacity: isDelivered ? 0.55 : 1.0,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
      );

      await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(stop.latitude!, stop.longitude!),
          textField: '${i + 1}',
          textColor: '#FFFFFF',
          textSize: 13,
          textOpacity: isDelivered ? 0.75 : 1.0,
          textHaloColor: isDelivered
              ? '#9E9E9E'
              : (isCurrent ? '#F57C00' : '#1565C0'),
          textHaloWidth: 1,
        ),
      );
    }

    try {
      await controller.addFillExtrusionLayer(
        'openmaptiles',
        'felipe-route-3d-buildings',
        const FillExtrusionLayerProperties(
          fillExtrusionColor: '#D7D9DC',
          fillExtrusionOpacity: 0.86,
          fillExtrusionHeight: [
            'coalesce',
            ['get', 'render_height'],
            ['get', 'height'],
            6
          ],
          fillExtrusionBase: [
            'coalesce',
            ['get', 'render_min_height'],
            ['get', 'min_height'],
            0
          ],
          fillExtrusionVerticalGradient: true,
        ),
        sourceLayer: 'building',
        minzoom: 14,
      );
    } catch (_) {
      // O estilo continua em 3D inclinado mesmo onde não houver
      // dados de altura de prédios.
    }

    final position = _lastPosition;
    if (position != null) {
      await _pushPosition(position);
      if (_navigationTargetIndex != null && _navigationRoute == null) {
        await _startNavigation(_navigationTargetIndex!);
      }
    } else {
      await controller.easeCamera(
        CameraUpdate.tiltTo(_is3D ? 50 : 0),
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Future<void> _startNavigation(int index) async {
    if (_loadingNavigation || index < 0 || index >= widget.route.stops.length) {
      return;
    }

    final position = _lastPosition;
    final stop = widget.route.stops[index];

    if (position == null) {
      await _startGps();
      if (mounted && _lastPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aguardando localização do GPS.')),
        );
      }
      return;
    }

    if (stop.latitude == null || stop.longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta parada ainda não possui coordenadas.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _loadingNavigation = true;
      _navigationTargetIndex = index;
      _following = true;
    });

    final route = await NavigationService.drivingRoute(
      fromLat: position.latitude,
      fromLng: position.longitude,
      toLat: stop.latitude!,
      toLng: stop.longitude!,
    );

    if (!mounted) return;

    setState(() {
      _loadingNavigation = false;
      _navigationRoute = route;
    });

    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível calcular a rota pelas ruas.'),
        ),
      );
      return;
    }

    final controller = _controller;
    if (controller != null && _styleLoaded) {
      await controller.addLine(
        LineOptions(
          geometry: route.points,
          lineColor: '#0B57D0',
          lineWidth: 7,
          lineOpacity: 0.95,
        ),
      );

      await controller.updateMyLocationTrackingMode(
        MyLocationTrackingMode.trackingGps,
      );
      await controller.setTrackingCameraOptions(
        tilt: _is3D ? 58 : 0,
        duration: const Duration(milliseconds: 300),
      );
      await controller.easeCamera(
        CameraUpdate.zoomTo(17.5),
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  String _navigationSummary() {
    final route = _navigationRoute;
    final index = _navigationTargetIndex;

    if (index == null) {
      return 'Números do mapa = ordem otimizada da rota';
    }

    if (_loadingNavigation) {
      return 'Calculando rota para a parada ${index + 1}...';
    }

    if (route == null) {
      return 'Parada ${index + 1} selecionada';
    }

    final km = route.distanceMeters / 1000;
    final minutes = (route.durationSeconds / 60).round();

    return 'Parada ${index + 1} • ${km.toStringAsFixed(km < 10 ? 1 : 0)} km • ~$minutes min';
  }
  Future<void> _centerOnUser() async {
    final controller = _controller;
    if (controller == null) return;

    if (_lastPosition == null) {
      await _startGps();
      return;
    }

    setState(() => _following = true);

    await controller.updateMyLocationTrackingMode(
      MyLocationTrackingMode.trackingGps,
    );

    await controller.setTrackingCameraOptions(
      tilt: _is3D ? 55 : 0,
      duration: const Duration(milliseconds: 250),
    );

    await controller.easeCamera(
      CameraUpdate.zoomTo(17),
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _toggle3D() async {
    setState(() => _is3D = !_is3D);

    final controller = _controller;
    if (controller == null) return;

    if (_following && _lastPosition != null) {
      await controller.updateMyLocationTrackingMode(
        MyLocationTrackingMode.trackingGps,
      );
      await controller.setTrackingCameraOptions(
        tilt: _is3D ? 55 : 0,
        duration: const Duration(milliseconds: 300),
      );
    } else {
      await controller.easeCamera(
        CameraUpdate.tiltTo(_is3D ? 50 : 0),
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Future<void> _locateMissingAddresses() async {
    if (_locatingAddresses) return;

    setState(() {
      _locatingAddresses = true;
      _progress = null;
    });

    final found = await GeocodingService.fillMissingCoordinates(
      widget.route,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );

    if (!mounted) return;

    setState(() => _locatingAddresses = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          found == 0
              ? 'Não foi possível localizar novos endereços.'
              : '$found endereço(s) localizado(s). Reabra o mapa para atualizar os pontos.',
        ),
      ),
    );
  }

  void _handleMapTap(LatLng coordinates) {
    var nearestIndex = -1;
    var nearestDistance = double.infinity;

    for (var i = 0; i < widget.route.stops.length; i++) {
      final stop = widget.route.stops[i];
      if (stop.latitude == null || stop.longitude == null) continue;

      final distance = Geolocator.distanceBetween(
        coordinates.latitude,
        coordinates.longitude,
        stop.latitude!,
        stop.longitude!,
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    // Área de toque maior para facilitar o uso durante a rota.
    if (nearestIndex >= 0 && nearestDistance <= 90) {
      _showStopDetails(nearestIndex);
    }
  }

  Future<void> _showStopDetails(int index) async {
    final stop = widget.route.stops[index];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Text('${index + 1}'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parada ${index + 1}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              stop.address,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (stop.complement != null)
                              Text(stop.complement!),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (stop.completed) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ENTREGUE',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    '${stop.totalPackages} pacote${stop.totalPackages == 1 ? '' : 's'} neste local',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...stop.packagesByStop.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            'Parada Shopee ${entry.key}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${entry.value} pacote${entry.value == 1 ? '' : 's'}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text(
                    'Pacotes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...stop.packages.map(
                    (package) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.qr_code_2_rounded),
                      title: Text(package.code),
                      subtitle: package.recipient == null
                          ? null
                          : Text(package.recipient!),
                      trailing: Text('P. ${package.stopLabel}'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (stop.completed)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        for (final package in stop.packages) {
                          package.status = DeliveryStatus.pending;
                        }
                        await RoutePersistenceService.saveRoute(widget.route);
                        if (!mounted) return;
                        Navigator.pop(sheetContext);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Entrega desfeita.')),
                        );
                      },
                      icon: const Icon(Icons.undo_rounded),
                      label: const Text('DESFAZER ENTREGA'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _startNavigation(index);
                      },
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('NAVEGAR NO APP'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        for (final package in stop.packages) {
                          package.status = DeliveryStatus.delivered;
                        }
                        await RoutePersistenceService.saveRoute(widget.route);
                        if (!mounted) return;
                        Navigator.pop(sheetContext);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Parada marcada como entregue.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('MARCAR COMO ENTREGUE'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openGoogleMaps(stop),
                          icon: const Icon(Icons.map_rounded),
                          label: const Text('GOOGLE MAPS'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openWaze(stop),
                          icon: const Icon(Icons.directions_car_rounded),
                          label: const Text('WAZE'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openGoogleMaps(PhysicalStop stop) async {
    final lat = stop.latitude;
    final lng = stop.longitude;

    final uri = lat != null && lng != null
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
          )
        : Uri.https(
            'www.google.com',
            '/maps/dir/',
            {'api': '1', 'destination': stop.address},
          );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o Google Maps.')),
      );
    }
  }

  Future<void> _openWaze(PhysicalStop stop) async {
    final lat = stop.latitude;
    final lng = stop.longitude;

    final uri = lat != null && lng != null
        ? Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes')
        : Uri.parse(
            'https://waze.com/ul?q=${Uri.encodeComponent(stop.address)}&navigate=yes',
          );

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o Waze.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeStops = widget.route.stops
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();

    final missingCount = widget.route.stops.length - routeStops.length;

    LatLng initialTarget;
    if (_lastPosition != null) {
      initialTarget = LatLng(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
      );
    } else if (routeStops.isNotEmpty) {
      initialTarget = LatLng(
        routeStops.first.latitude!,
        routeStops.first.longitude!,
      );
    } else {
      initialTarget = const LatLng(-14.2350, -51.9253);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mapa da rota',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: _is3D ? 'Mudar para 2D' : 'Mudar para 3D',
            onPressed: _toggle3D,
            icon: Icon(_is3D ? Icons.view_in_ar_rounded : Icons.map_rounded),
          ),
          if (missingCount > 0)
            IconButton(
              tooltip: 'Localizar endereços',
              onPressed:
                  _locatingAddresses ? null : _locateMissingAddresses,
              icon: const Icon(Icons.location_searching_rounded),
            ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: MapLibreStyles.openfreemapLiberty,
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: routeStops.isEmpty ? 4 : 14,
              tilt: _is3D ? 50 : 0,
            ),
            onMapCreated: (controller) {
              _controller = controller;
            },
            onStyleLoadedCallback: _onStyleLoaded,
            myLocationEnabled: _gpsEnabled,
            locationSource: const ManualLocationSource(),
            myLocationTrackingMode: _following
                ? MyLocationTrackingMode.trackingGps
                : MyLocationTrackingMode.none,
            myLocationRenderMode: MyLocationRenderMode.gps,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            annotationConsumeTapEvents: const [],
            onMapClick: (_, coordinates) => _handleMapTap(coordinates),
            onCameraTrackingDismissed: () {
              if (mounted) setState(() => _following = false);
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              color: Colors.white.withValues(alpha: 0.94),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _gpsEnabled
                          ? Icons.gps_fixed_rounded
                          : Icons.gps_off_rounded,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _gpsError ??
                            (_lastPosition == null
                                ? 'Procurando sua localização...'
                                : _navigationSummary()),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 28,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'gps-center',
                  onPressed: _centerOnUser,
                  tooltip: 'Minha posição',
                  child: const Icon(Icons.my_location_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'map-3d',
                  onPressed: _toggle3D,
                  tooltip: _is3D ? '2D' : '3D',
                  child: Icon(
                    _is3D ? Icons.layers_rounded : Icons.view_in_ar_rounded,
                  ),
                ),
              ],
            ),
          ),
          if (_locatingAddresses)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _progress == null
                        ? 'Localizando endereços...'
                        : 'Endereços: ${_progress!.done}/${_progress!.total} • ${_progress!.found} encontrados',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
