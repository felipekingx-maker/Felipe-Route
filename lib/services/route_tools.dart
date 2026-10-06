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

    if (startLatitude == null || startLongitude == null) {
      return null;
    }

    final points = <({double lat, double lng})>[
      (lat: startLatitude, lng: startLongitude),
    ];

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

    var currentMatrixIndex = 0;

    while (remaining.isNotEmpty) {
      int? bestStopIndex;
      double? bestScore;

      for (final candidateStopIndex in remaining) {
        final candidateMatrixIndex = stopOffset + candidateStopIndex;
        final duration =
            _matrixValue(matrix, currentMatrixIndex, candidateMatrixIndex);
        if (duration == null) continue;

        var score = duration;

        // A primeira parada deve ser SEMPRE a mais rápida de alcançar
        // a partir do GPS atual. A preferência pelo destino final só entra
        // depois que a primeira parada já foi escolhida.
        if (optimizedIndices.isNotEmpty && finalDestinationIndex != null) {
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

    // Refina a sequência inteira para evitar retornos desnecessários
    // causados pela heurística gulosa (ex.: passar perto de uma parada e
    // voltar para ela muito depois). A primeira parada permanece fixa.
    var improved = true;
    var passes = 0;
    var bestOrder = List<int>.from(optimizedIndices);
    var bestCost = _routeCost(
      bestOrder,
      matrix,
      stopOffset,
      finalDestinationIndex,
    );

    while (improved && passes < 6) {
      improved = false;
      passes++;

      // Tenta realocar cada parada (exceto a primeira) para outra posição.
      for (var from = 1; from < bestOrder.length; from++) {
        for (var to = 1; to < bestOrder.length; to++) {
          if (from == to) continue;

          final candidate = List<int>.from(bestOrder);
          final item = candidate.removeAt(from);
          candidate.insert(to, item);

          final cost = _routeCost(
            candidate,
            matrix,
            stopOffset,
            finalDestinationIndex,
          );

          if (cost + 0.5 < bestCost) {
            bestOrder = candidate;
            bestCost = cost;
            improved = true;
          }
        }
      }

      // Também testa inverter pequenos/longos trechos, sempre preservando
      // a primeira parada escolhida pelo GPS.
      for (var i = 1; i < bestOrder.length - 1; i++) {
        for (var j = i + 1; j < bestOrder.length; j++) {
          final candidate = List<int>.from(bestOrder);
          final reversed = candidate.sublist(i, j + 1).reversed.toList();
          candidate.replaceRange(i, j + 1, reversed);

          final cost = _routeCost(
            candidate,
            matrix,
            stopOffset,
            finalDestinationIndex,
          );

          if (cost + 0.5 < bestCost) {
            bestOrder = candidate;
            bestCost = cost;
            improved = true;
          }
        }
      }
    }

    final optimized =
        bestOrder.map((index) => withCoordinates[index]).toList();

    return [...completed, ...optimized, ...withoutCoordinates];
  }

  static double _routeCost(
    List<int> order,
    List<List<double?>> matrix,
    int stopOffset,
    int? finalDestinationIndex,
  ) {
    if (order.isEmpty) return double.infinity;

    var total = 0.0;
    var fromMatrixIndex = 0;

    for (final stopIndex in order) {
      final toMatrixIndex = stopOffset + stopIndex;
      final leg = _matrixValue(matrix, fromMatrixIndex, toMatrixIndex);
      if (leg == null) return double.infinity;
      total += leg;
      fromMatrixIndex = toMatrixIndex;
    }

    if (finalDestinationIndex != null) {
      final lastLeg =
          _matrixValue(matrix, fromMatrixIndex, finalDestinationIndex);
      if (lastLeg == null) return double.infinity;
      total += lastLeg;
    }

    return total;
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

  static Future<double?> calculateRoadDistance({
    required List<PhysicalStop> stops,
    required double startLatitude,
    required double startLongitude,
    double? finalLatitude,
    double? finalLongitude,
  }) async {
    final pending = stops
        .where(
          (stop) =>
              !stop.completed &&
              stop.latitude != null &&
              stop.longitude != null,
        )
        .toList();

    if (pending.isEmpty) return 0;

    final points = <({double lat, double lng})>[
      (lat: startLatitude, lng: startLongitude),
      ...pending.map(
        (stop) => (lat: stop.latitude!, lng: stop.longitude!),
      ),
    ];

    if (finalLatitude != null && finalLongitude != null) {
      points.add((lat: finalLatitude, lng: finalLongitude));
    }

    final roadRoute = await NavigationService.routeThroughStops(points);
    return roadRoute?.distanceMeters;
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
