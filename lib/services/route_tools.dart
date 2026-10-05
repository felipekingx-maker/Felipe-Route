import '../models/delivery_models.dart';
import 'navigation_service.dart';

class RouteTools {
  static bool canOptimize(List<PhysicalStop> stops) {
    final pending = stops.where((s) => !s.completed).toList();
    return pending.length >= 2 &&
        pending.where((s) => s.latitude != null && s.longitude != null).length >= 2;
  }

  /// Otimiza usando tempo real de condução pela malha viária.
  /// A matriz respeita vias dirigíveis, sentidos e mão da via.
  static Future<List<PhysicalStop>?> optimizeByRoads({
    required List<PhysicalStop> stops,
    double? startLatitude,
    double? startLongitude,
    double? finalLatitude,
    double? finalLongitude,
  }) async {
    final completed = stops.where((s) => s.completed).toList();
    final pending = stops.where((s) => !s.completed).toList();

    final withCoordinates = pending
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();
    final withoutCoordinates = pending
        .where((s) => s.latitude == null || s.longitude == null)
        .toList();

    if (withCoordinates.length < 2) {
      return List<PhysicalStop>.from(stops);
    }

    final points = <({double lat, double lng})>[];
    final hasStart = startLatitude != null && startLongitude != null;

    if (hasStart) {
      points.add((lat: startLatitude, lng: startLongitude));
    }

    final stopOffset = points.length;
    points.addAll(
      withCoordinates.map(
        (stop) => (lat: stop.latitude!, lng: stop.longitude!),
      ),
    );

    int? finalDestinationIndex;
    if (finalLatitude != null && finalLongitude != null) {
      finalDestinationIndex = points.length;
      points.add((lat: finalLatitude, lng: finalLongitude));
    }

    final matrix = await NavigationService.drivingDurationMatrix(points);
    if (matrix == null || matrix.length < points.length) {
      return null;
    }

    final remaining = <int>{
      for (var i = 0; i < withCoordinates.length; i++) i,
    };
    final optimizedIndices = <int>[];

    int currentMatrixIndex;
    if (hasStart) {
      currentMatrixIndex = 0;
    } else {
      final firstStop = 0;
      remaining.remove(firstStop);
      optimizedIndices.add(firstStop);
      currentMatrixIndex = stopOffset + firstStop;
    }

    while (remaining.isNotEmpty) {
      int? bestStopIndex;
      double? bestScore;

      for (final candidateStopIndex in remaining) {
        final candidateMatrixIndex = stopOffset + candidateStopIndex;
        final duration =
            _matrixValue(matrix, currentMatrixIndex, candidateMatrixIndex);
        if (duration == null) continue;

        var score = duration;

        if (finalDestinationIndex != null) {
          final towardFinal = _matrixValue(
            matrix,
            candidateMatrixIndex,
            finalDestinationIndex,
          );
          if (towardFinal != null) {
            score += towardFinal * 0.15;
          }
        }

        if (bestScore == null || score < bestScore) {
          bestScore = score;
          bestStopIndex = candidateStopIndex;
        }
      }

      if (bestStopIndex == null) {
        optimizedIndices.addAll(remaining);
        break;
      }

      optimizedIndices.add(bestStopIndex);
      remaining.remove(bestStopIndex);
      currentMatrixIndex = stopOffset + bestStopIndex;
    }

    final optimized =
        optimizedIndices.map((index) => withCoordinates[index]).toList();

    return [...completed, ...optimized, ...withoutCoordinates];
  }

  static double? _matrixValue(
    List<List<double?>> matrix,
    int from,
    int to,
  ) {
    if (from < 0 || from >= matrix.length) return null;
    final row = matrix[from];
    if (to < 0 || to >= row.length) return null;
    return row[to];
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
