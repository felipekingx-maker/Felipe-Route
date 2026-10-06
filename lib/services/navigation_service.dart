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
  static const _valhallaBaseUrl = 'https://valhalla1.openstreetmap.de';
  static const _osrmBaseUrl = 'https://router.project-osrm.org';

  static const _headers = <String, String>{
    'Content-Type': 'application/json',
    'User-Agent': 'FelipeRoute/0.3',
    'X-Client-Id': 'felipe-route-beta',
  };

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

    final valhalla = await _routeWithValhalla(stops);
    if (valhalla != null) return valhalla;

    return _routeWithOsrm(stops);
  }

  static Future<NavigationRoute?> _routeWithValhalla(
    List<({double lat, double lng})> stops,
  ) async {
    try {
      final body = jsonEncode({
        'locations': stops
            .map((p) => {
                  'lat': p.lat,
                  'lon': p.lng,
                  'type': 'break',
                })
            .toList(),
        'costing': 'auto',
        'units': 'kilometers',
        'directions_options': {
          'units': 'kilometers',
          'language': 'pt-BR',
        },
      });

      final response = await http
          .post(
            Uri.parse('$_valhallaBaseUrl/route'),
            headers: _headers,
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final trip = decoded['trip'];
      if (trip is! Map<String, dynamic>) return null;

      final summary = trip['summary'];
      final legs = trip['legs'];
      if (summary is! Map<String, dynamic> || legs is! List) return null;

      final points = <LatLng>[];
      for (final leg in legs) {
        if (leg is! Map<String, dynamic>) continue;
        final shape = leg['shape']?.toString();
        if (shape == null || shape.isEmpty) continue;

        final legPoints = _decodeValhallaPolyline(shape);
        if (legPoints.isEmpty) continue;

        if (points.isNotEmpty &&
            points.last.latitude == legPoints.first.latitude &&
            points.last.longitude == legPoints.first.longitude) {
          points.addAll(legPoints.skip(1));
        } else {
          points.addAll(legPoints);
        }
      }

      if (points.length < 2) return null;

      final lengthKm = (summary['length'] as num?)?.toDouble() ?? 0;
      final timeSeconds = (summary['time'] as num?)?.toDouble() ?? 0;

      return NavigationRoute(
        points: points,
        distanceMeters: lengthKm * 1000,
        durationSeconds: timeSeconds,
      );
    } catch (_) {
      return null;
    }
  }

  static List<LatLng> _decodeValhallaPolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    int decodeValue() {
      var result = 0;
      var shift = 0;
      int byte;

      do {
        if (index >= encoded.length) return 0;
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    }

    while (index < encoded.length) {
      latitude += decodeValue();
      longitude += decodeValue();
      points.add(LatLng(latitude / 1e6, longitude / 1e6));
    }

    return points;
  }

  static Future<NavigationRoute?> _routeWithOsrm(
    List<({double lat, double lng})> stops,
  ) async {
    try {
      final coordinates =
          stops.map((p) => '${p.lng},${p.lat}').join(';');

      final uri = Uri.parse(
        '$_osrmBaseUrl/route/v1/driving/$coordinates'
        '?overview=full&geometries=geojson&steps=false',
      );

      final response = await http
          .get(uri, headers: const {'User-Agent': 'FelipeRoute/0.3'})
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

    final valhalla = await _matrixWithValhalla(points);
    if (valhalla != null) return valhalla;

    return _matrixWithOsrm(points);
  }

  static Future<List<List<double?>>?> _matrixWithValhalla(
    List<({double lat, double lng})> points,
  ) async {
    try {
      final locations = points
          .map((p) => {
                'lat': p.lat,
                'lon': p.lng,
              })
          .toList();

      final body = jsonEncode({
        'sources': locations,
        'targets': locations,
        'costing': 'auto',
        'units': 'kilometers',
      });

      final response = await http
          .post(
            Uri.parse('$_valhallaBaseUrl/sources_to_targets'),
            headers: _headers,
            body: body,
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final rows = decoded['sources_to_targets'];
      if (rows is! List || rows.length != points.length) return null;

      return rows.map<List<double?>>((row) {
        if (row is! List) return <double?>[];

        return row.map<double?>((cell) {
          if (cell is! Map) return null;
          final time = cell['time'];
          return time is num ? time.toDouble() : null;
        }).toList();
      }).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<List<double?>>?> _matrixWithOsrm(
    List<({double lat, double lng})> points,
  ) async {
    try {
      final coordinates =
          points.map((p) => '${p.lng},${p.lat}').join(';');

      final uri = Uri.parse(
        '$_osrmBaseUrl/table/v1/driving/$coordinates?annotations=duration',
      );

      final response = await http
          .get(uri, headers: const {'User-Agent': 'FelipeRoute/0.3'})
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
