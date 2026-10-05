
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/delivery_models.dart';

class RouteMapScreen extends StatelessWidget {
  final DeliveryRoute route;
  final int? currentIndex;

  const RouteMapScreen({
    super.key,
    required this.route,
    this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final withCoords = <({PhysicalStop stop, int index})>[];
    for (var i = 0; i < route.stops.length; i++) {
      final stop = route.stops[i];
      if (stop.latitude != null && stop.longitude != null) {
        withCoords.add((stop: stop, index: i));
      }
    }

    if (withCoords.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Mapa da rota',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Ainda não há coordenadas nas paradas.',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'O mapa será preenchido quando o romaneio trouxer latitude/longitude ou quando adicionarmos a geocodificação automática dos endereços.',
                    textAlign: TextAlign.center,
                  ),
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
                  final isCurrent = currentIndex == entry.index;

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
                    if (withCoords.length < route.stops.length)
                      Text(
                        '${route.stops.length - withCoords.length} sem coordenada',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
