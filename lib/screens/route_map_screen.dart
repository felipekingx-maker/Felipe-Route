
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  Timer? _resumeFollowingTimer;
  Timer? _smoothNavigationTimer;
  DateTime? _lastGpsUpdateAt;

  bool _styleLoaded = false;
  bool _gpsEnabled = false;
  bool _following = true;
  bool _is3D = true;
  bool _locatingAddresses = false;
  String? _gpsError;
  Position? _lastPosition;
  Position? _previousPosition;
  GeocodingProgress? _progress;
  int? _navigationTargetIndex;
  NavigationRoute? _navigationRoute;
  bool _loadingNavigation = false;
  bool _cameraFrameBusy = false;
  final Map<int, Circle> _stopCircles = {};
  final Map<int, Symbol> _stopSymbols = {};

  @override
  void initState() {
    super.initState();
    _navigationTargetIndex = widget.navigationTargetIndex;
    if (_navigationTargetIndex != null) {
      WakelockPlus.enable();
    }
    _startGps();
    _startSmoothNavigationLoop();
  }

  @override
  void dispose() {
    _resumeFollowingTimer?.cancel();
    _smoothNavigationTimer?.cancel();
    _positionSubscription?.cancel();
    WakelockPlus.disable();
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
    final previous = _lastPosition;
    _previousPosition = previous;
    _lastPosition = position;
    _lastGpsUpdateAt = DateTime.now();

    final controller = _controller;
    if (controller != null && _styleLoaded) {
      if (_navigationTargetIndex == null) {
        await controller.updateManualLocation(
          ManualLocationUpdate(
            target: LatLng(position.latitude, position.longitude),
            horizontalAccuracy: position.accuracy,
            altitude: position.altitude,
            bearing: position.heading,
            speed: position.speed,
          ),
        );
      }

      if (_following) {
        if (_navigationTargetIndex == null) {
          await controller.updateMyLocationTrackingMode(
            MyLocationTrackingMode.trackingGps,
          );
          await controller.easeCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(position.latitude, position.longitude),
                zoom: 16.5,
                bearing: 0,
                tilt: _is3D ? 55 : 0,
              ),
            ),
            duration: const Duration(milliseconds: 300),
          );
        }
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

  void _startSmoothNavigationLoop() {
    _smoothNavigationTimer?.cancel();
    _smoothNavigationTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _updateSmoothNavigationCamera(),
    );
  }

  Future<void> _updateSmoothNavigationCamera() async {
    if (_cameraFrameBusy ||
        !_following ||
        _navigationTargetIndex == null ||
        !_styleLoaded ||
        _controller == null ||
        _lastPosition == null) {
      return;
    }

    _cameraFrameBusy = true;
    try {
      final position = _lastPosition!;
      final heading = _navigationHeading(position);
      final speed = position.speed.isFinite && position.speed > 0
          ? position.speed
          : 0.0;

      final updatedAt = _lastGpsUpdateAt ?? DateTime.now();
      final ageSeconds = DateTime.now()
              .difference(updatedAt)
              .inMilliseconds
              .clamp(0, 1200) /
          1000.0;

      final predictedMeters = speed * ageSeconds;
      final predicted = predictedMeters > 0.15
          ? _pointAhead(
              position.latitude,
              position.longitude,
              heading,
              predictedMeters,
            )
          : LatLng(position.latitude, position.longitude);

      // O alvo fica adiantado em relação ao carro. Como o mapa gira
      // junto com o heading, o carro permanece visualmente na parte
      // inferior da tela enquanto o mapa se desloca por baixo.
      final cameraTarget = _pointAhead(
        predicted.latitude,
        predicted.longitude,
        heading,
        55,
      );

      final controller = _controller!;

      // Durante a navegação a câmera é 100% manual. Não usamos
      // trackingGps, pois ele disputa o controle da câmera.
      await controller.updateMyLocationTrackingMode(
        MyLocationTrackingMode.none,
      );

      // Atualização direta em pequenos passos (~30 fps), evitando
      // acumular animações easeCamera entre uma leitura de GPS e outra.
      await controller.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: cameraTarget,
            zoom: 18.2,
            bearing: heading,
            tilt: _is3D ? 60 : 0,
          ),
        ),
      );
    } finally {
      _cameraFrameBusy = false;
    }
  }

  double _navigationHeading(Position position) {
    final gpsHeading = position.heading;
    if (gpsHeading.isFinite && gpsHeading >= 0 && position.speed > 1.2) {
      return gpsHeading;
    }

    final previous = _previousPosition;
    if (previous != null) {
      final moved = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );

      if (moved >= 2) {
        return Geolocator.bearingBetween(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }

    return _controller?.cameraPosition?.bearing ?? 0;
  }

  LatLng _pointAhead(
    double latitude,
    double longitude,
    double bearingDegrees,
    double meters,
  ) {
    const earthRadius = 6378137.0;
    final bearing = bearingDegrees * math.pi / 180;
    final lat1 = latitude * math.pi / 180;
    final lon1 = longitude * math.pi / 180;
    final angularDistance = meters / earthRadius;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  void _handleTrackingDismissed() {
    if (!mounted) return;

    _resumeFollowingTimer?.cancel();
    setState(() => _following = false);
  }

  void _handleMapInteraction() {
    if (!mounted || _navigationTargetIndex == null || !_following) return;

    _resumeFollowingTimer?.cancel();
    setState(() => _following = false);
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    final controller = _controller;
    if (controller == null) return;

    await controller.setSymbolTextAllowOverlap(true);
    await controller.setSymbolTextIgnorePlacement(true);

    final routeStops = widget.route.stops
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();

    if (routeStops.length > 1) {
      final roadRoute = await NavigationService.routeThroughStops(
        routeStops
            .map(
              (s) => (
                lat: s.latitude!,
                lng: s.longitude!,
              ),
            )
            .toList(),
      );

      if (roadRoute != null) {
        await controller.addLine(
          LineOptions(
            geometry: roadRoute.points,
            lineColor: '#1565C0',
            lineWidth: 5,
            lineOpacity: 0.9,
          ),
        );
      }
    }

    for (var i = 0; i < widget.route.stops.length; i++) {
      final stop = widget.route.stops[i];
      if (stop.latitude == null || stop.longitude == null) continue;

      final isCurrent = widget.currentIndex == i;
      final isDelivered = stop.completed;

      final circle = await controller.addCircle(
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
      _stopCircles[i] = circle;

      final symbol = await controller.addSymbol(
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
      _stopSymbols[i] = symbol;
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

  Future<void> _refreshStopMarker(int index) async {
    final controller = _controller;
    if (controller == null || !_styleLoaded) return;
    if (index < 0 || index >= widget.route.stops.length) return;

    final stop = widget.route.stops[index];
    final delivered = stop.completed;
    final isCurrent = widget.currentIndex == index;

    final circle = _stopCircles[index];
    if (circle != null) {
      await controller.updateCircle(
        circle,
        CircleOptions(
          circleColor: delivered
              ? '#9E9E9E'
              : (isCurrent ? '#F57C00' : '#1565C0'),
          circleOpacity: delivered ? 0.55 : 1.0,
        ),
      );
    }

    final symbol = _stopSymbols[index];
    if (symbol != null) {
      await controller.updateSymbol(
        symbol,
        SymbolOptions(
          textOpacity: delivered ? 0.75 : 1.0,
          textHaloColor: delivered
              ? '#9E9E9E'
              : (isCurrent ? '#F57C00' : '#1565C0'),
        ),
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

    _resumeFollowingTimer?.cancel();
    await WakelockPlus.enable();
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
        MyLocationTrackingMode.none,
      );
      await _pushPosition(position);
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

    if (_navigationTargetIndex != null) {
      await controller.updateMyLocationTrackingMode(
        MyLocationTrackingMode.none,
      );
      await _updateSmoothNavigationCamera();
    } else {
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
                    (package) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.qr_code_2_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  package.code,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (package.recipient != null &&
                                    package.recipient!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Destinatário: ${package.recipient}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (package.notes != null &&
                                    package.notes!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Obs.: ${package.notes}',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('P. ${package.stopLabel}'),
                        ],
                      ),
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
                        await _refreshStopMarker(index);
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
                        await _refreshStopMarker(index);
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

  String _navigationEtaText() {
    final route = _navigationRoute;
    if (route == null) return '-- min';
    return '~${(route.durationSeconds / 60).round()} min';
  }

  String _navigationDistanceText() {
    final route = _navigationRoute;
    if (route == null) return '-- km';
    final km = route.distanceMeters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  String _navigationDestinationText() {
    final index = _navigationTargetIndex;
    if (index == null || index < 0 || index >= widget.route.stops.length) {
      return 'Rota de entregas';
    }
    return widget.route.stops[index].address;
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _navigationTargetIndex == null
                  ? 'Mapa da rota'
                  : 'Parada ${_navigationTargetIndex! + 1}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            if (_navigationTargetIndex != null)
              Text(
                _navigationDestinationText(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
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
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _handleMapInteraction(),
            child: MapLibreMap(
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
              myLocationEnabled:
                  _gpsEnabled && _navigationTargetIndex == null,
              locationSource: const ManualLocationSource(),
              myLocationTrackingMode:
                  _following && _navigationTargetIndex == null
                      ? MyLocationTrackingMode.trackingGps
                      : MyLocationTrackingMode.none,
              myLocationRenderMode: MyLocationRenderMode.gps,
              compassEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              annotationConsumeTapEvents: const [],
              onMapClick: (_, coordinates) => _handleMapTap(coordinates),
              onCameraTrackingDismissed: _handleTrackingDismissed,
            ),
          ),
          if (_navigationTargetIndex != null && _following)
            Positioned(
              left: 0,
              right: 0,
              bottom: 150,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 8,
                          offset: Offset(0, 2),
                          color: Color(0x33000000),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              color: _navigationTargetIndex != null
                  ? const Color(0xFF1A73E8)
                  : Colors.white.withValues(alpha: 0.96),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _navigationTargetIndex != null
                            ? Colors.white.withValues(alpha: 0.18)
                            : const Color(0xFFE8F0FE),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _gpsEnabled
                            ? Icons.navigation_rounded
                            : Icons.gps_off_rounded,
                        color: _navigationTargetIndex != null
                            ? Colors.white
                            : const Color(0xFF1A73E8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _gpsError ??
                            (_lastPosition == null
                                ? 'Procurando sua localização...'
                                : _navigationSummary()),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _navigationTargetIndex != null
                              ? Colors.white
                              : const Color(0xFF202124),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: _navigationTargetIndex != null ? 106 : 28,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'gps-center',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF202124),
                  elevation: 4,
                  onPressed: _centerOnUser,
                  tooltip: 'Minha posição',
                  child: const Icon(Icons.my_location_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'map-3d',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF202124),
                  elevation: 4,
                  onPressed: _toggle3D,
                  tooltip: _is3D ? '2D' : '3D',
                  child: Icon(
                    _is3D ? Icons.layers_rounded : Icons.view_in_ar_rounded,
                  ),
                ),
              ],
            ),
          ),
          if (_navigationTargetIndex != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: Material(
                elevation: 5,
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _navigationEtaText(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF188038),
                              ),
                            ),
                            Text(
                              '${_navigationDistanceText()} • Parada ${_navigationTargetIndex! + 1}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5F6368),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _centerOnUser,
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text('CENTRALIZAR'),
                      ),
                    ],
                  ),
                ),
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
