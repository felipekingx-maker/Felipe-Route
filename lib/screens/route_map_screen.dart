
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/delivery_models.dart';
import '../services/geocoding_service.dart';

class RouteMapScreen extends StatefulWidget {
  final DeliveryRoute route;
  final int? currentIndex;

  const RouteMapScreen({
    super.key,
    required this.route,
    this.currentIndex,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  bool _locating = false;
  GeocodingProgress? _progress;

  Future<void> _locateMissing() async {
    if (_locating) return;

    setState(() {
      _locating = true;
      _progress = null;
    });

    final found = await GeocodingService.fillMissingCoordinates(
      widget.route,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      },
    );

    if (!mounted) return;

    setState(() => _locating = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          found == 0
              ? 'Não foi possível localizar novos endereços.'
              : '$found endereço(s) localizado(s) no mapa.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final withCoords = <({PhysicalStop stop, int index})>[];

    for (var i = 0; i < route.stops.length; i++) {
      final stop = route.stops[i];
      if (stop.latitude != null && stop.longitude != null) {
        withCoords.add((stop: stop, index: i));
      }
    }

    final missingCount = route.stops.length - withCoords.length;

    if (withCoords.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Mapa da rota',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'As paradas ainda não têm coordenadas.',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'O Felipe Route pode tentar localizar os endereços do romaneio automaticamente.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _locating ? null : _locateMissing,
                    icon: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.location_searching_rounded),
                    label: Text(
                      _locating ? 'LOCALIZANDO...' : 'LOCALIZAR PARADAS',
                    ),
                  ),
                  if (_progress != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${_progress!.done}/${_progress!.total} • ${_progress!.found} encontradas',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final avgLat =
        withCoords.map((e) => e.stop.latitude!).reduce((a, b) => a + b) /
            withCoords.length;
    final avgLng =
        withCoords.map((e) => e.stop.longitude!).reduce((a, b) => a + b) /
            withCoords.length;

    final points = withCoords
        .map((e) => LatLng(e.stop.latitude!, e.stop.longitude!))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mapa da rota',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (missingCount > 0)
            IconButton(
              tooltip: 'Localizar endereços sem coordenada',
              onPressed: _locating ? null : _locateMissing,
              icon: const Icon(Icons.location_searching_rounded),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(avgLat, avgLng),
              initialZoom: 12.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.feliperoute.felipe_route',
              ),
              if (points.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      strokeWidth: 5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: withCoords.map((entry) {
                  final stopNumber = entry.index + 1;
                  final isCurrent = widget.currentIndex == entry.index;

                  return Marker(
                    point: LatLng(
                      entry.stop.latitude!,
                      entry.stop.longitude!,
                    ),
                    width: 54,
                    height: 54,
                    child: Tooltip(
                      message:
                          'Parada $stopNumber\n${entry.stop.address}\n${entry.stop.totalPackages} pacote(s)',
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.primary,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 6,
                              color: Colors.black26,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$stopNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              RichAttributionWidget(
                attributions: const [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.route_rounded),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${withCoords.length} de ${route.stops.length} paradas no mapa',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (_locating)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (missingCount > 0)
                      Text('$missingCount sem coordenada'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
