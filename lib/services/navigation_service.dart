import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

class NavigationRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const NavigationRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

class NavigationService {
  static const _baseUrl = 'https://router.project-osrm.org';

  static Future<NavigationRoute?> drivingRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    return routeThroughStops([
      (lat: fromLat, lng: fromLng),
      (lat: toLat, lng: toLng),
    ]);
  }

  static Future<NavigationRoute?> routeThroughStops(
    List<({double lat, double lng})> stops,
  ) async {
    if (stops.length < 2) return null;

    try {
      final coordinates = stops
          .map((p) => '${p.lng},${p.lat}')
          .join(';');

      final uri = Uri.parse(
        '$_baseUrl/route/v1/driving/$coordinates'
        '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http
          .get(uri, headers: const {'User-Agent': 'FelipeRoute/0.2'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;

      final first = routes.first;
      if (first is! Map<String, dynamic>) return null;

      final geometry = first['geometry'];
      if (geometry is! Map<String, dynamic>) return null;

      final coordinatesJson = geometry['coordinates'];
      if (coordinatesJson is! List) return null;

      final points = <LatLng>[];
      for (final coordinate in coordinatesJson) {
        if (coordinate is List && coordinate.length >= 2) {
          final lng = (coordinate[0] as num?)?.toDouble();
          final lat = (coordinate[1] as num?)?.toDouble();
          if (lat != null && lng != null) {
            points.add(LatLng(lat, lng));
          }
        }
      }

      if (points.length < 2) return null;

      return NavigationRoute(
        points: points,
        distanceMeters: (first['distance'] as num?)?.toDouble() ?? 0,
        durationSeconds: (first['duration'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<List<double?>>?> drivingDurationMatrix(
    List<({double lat, double lng})> points,
  ) async {
    if (points.length < 2) return null;

    try {
      final coordinates = points
          .map((p) => '${p.lng},${p.lat}')
          .join(';');

      final uri = Uri.parse(
        '$_baseUrl/table/v1/driving/$coordinates?annotations=duration',
      );

      final response = await http
          .get(uri, headers: const {'User-Agent': 'FelipeRoute/0.2'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final durations = decoded['durations'];
      if (durations is! List) return null;

      return durations.map<List<double?>>((row) {
        if (row is! List) return <double?>[];
        return row.map<double?>((value) {
          if (value == null) return null;
          return (value as num).toDouble();
        }).toList();
      }).toList();
    } catch (_) {
      return null;
    }
  }
}
