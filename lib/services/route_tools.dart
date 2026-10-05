import 'dart:math' as math;

import '../models/delivery_models.dart';

class RouteTools {
  static double _distance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;

  static bool canOptimize(List<PhysicalStop> stops) {
    final pending = stops.where((s) => !s.completed).toList();
    return pending.length >= 2 &&
        pending.where((s) => s.latitude != null && s.longitude != null).length >= 2;
  }

  /// Heurística nearest-neighbor com leve preferência por terminar perto
  /// do destino final quando ele possui coordenadas.
  static List<PhysicalStop> optimize({
    required List<PhysicalStop> stops,
    PhysicalStop? startFrom,
    double? finalLatitude,
    double? finalLongitude,
  }) {
    final completed = stops.where((s) => s.completed).toList();
    final pending = stops.where((s) => !s.completed).toList();

    final withCoordinates = pending
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();
    final withoutCoordinates = pending
        .where((s) => s.latitude == null || s.longitude == null)
        .toList();

    if (withCoordinates.length < 2) return List<PhysicalStop>.from(stops);

    PhysicalStop current = startFrom != null &&
            startFrom.latitude != null &&
            startFrom.longitude != null
        ? startFrom
        : withCoordinates.first;

    final remaining = List<PhysicalStop>.from(withCoordinates);
    final optimized = <PhysicalStop>[];

    if (remaining.remove(current)) {
      optimized.add(current);
    }

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final da = _distance(
          current.latitude!,
          current.longitude!,
          a.latitude!,
          a.longitude!,
        );
        final db = _distance(
          current.latitude!,
          current.longitude!,
          b.latitude!,
          b.longitude!,
        );

        double scoreA = da;
        double scoreB = db;

        if (finalLatitude != null && finalLongitude != null) {
          scoreA += 0.20 *
              _distance(a.latitude!, a.longitude!, finalLatitude, finalLongitude);
          scoreB += 0.20 *
              _distance(b.latitude!, b.longitude!, finalLatitude, finalLongitude);
        }

        return scoreA.compareTo(scoreB);
      });

      current = remaining.removeAt(0);
      optimized.add(current);
    }

    return [...completed, ...optimized, ...withoutCoordinates];
  }

  static int potentialDuplicateCount(List<PhysicalStop> stops) {
    final seen = <String>{};
    var duplicates = 0;
    for (final stop in stops) {
      final key = _normalize(stop.address, stop.complement);
      if (!seen.add(key)) duplicates++;
    }
    return duplicates;
  }

  static String _normalize(String address, String? complement) {
    return '$address ${complement ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áàâãéèêíìîóòôõúùûç ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
