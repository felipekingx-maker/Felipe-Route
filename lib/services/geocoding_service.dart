import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/delivery_models.dart';

class GeocodingProgress {
  final int done;
  final int total;
  final int found;

  const GeocodingProgress({
    required this.done,
    required this.total,
    required this.found,
  });
}

class GeocodingService {
  static Future<({double lat, double lng})?> geocodeAddress(
    String address,
  ) async {
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': address,
          'format': 'jsonv2',
          'limit': '1',
          'countrycodes': 'br',
          'addressdetails': '0',
        },
      );

      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'FelipeRoute/0.2 (delivery route beta)',
              'Accept-Language': 'pt-BR,pt;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! List || data.isEmpty) return null;

      final first = data.first;
      if (first is! Map) return null;

      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;

      return (lat: lat, lng: lng);
    } catch (_) {
      return null;
    }
  }

  static Future<int> fillMissingCoordinates(
    DeliveryRoute route, {
    void Function(GeocodingProgress progress)? onProgress,
  }) async {
    final missing = route.stops
        .where((stop) => stop.latitude == null || stop.longitude == null)
        .toList();

    var found = 0;

    for (var i = 0; i < missing.length; i++) {
      final stop = missing[i];

      final query = [
        stop.address,
        if (stop.complement != null && stop.complement!.trim().isNotEmpty)
          stop.complement!,
        'Brasil',
      ].join(', ');

      final result = await geocodeAddress(query);

      if (result != null) {
        stop.latitude = result.lat;
        stop.longitude = result.lng;

        for (final package in stop.packages) {
          package.latitude = result.lat;
          package.longitude = result.lng;
        }

        found++;
      }

      onProgress?.call(
        GeocodingProgress(
          done: i + 1,
          total: missing.length,
          found: found,
        ),
      );

      if (i < missing.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
    }

    return found;
  }
}
