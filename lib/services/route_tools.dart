import '../models/delivery_models.dart';
import 'navigation_service.dart';

class RouteTools {
  static bool canOptimize(List<PhysicalStop> stops) {
    final pending = stops.where((s) => !s.completed).toList();
    return pending.length >= 2 &&
        pending.where((s) => s.latitude != null && s.longitude != null).length >= 2;
  }

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
      ...withCoordinates.map(
        (stop) => (lat: stop.latitude!, lng: stop.longitude!),
      ),
    ];

    int? finalDestinationIndex;
    if (finalLatitude != null && finalLongitude != null) {
      finalDestinationIndex = points.length;
      points.add((lat: finalLatitude, lng: finalLongitude));
    }

    final matrix = await NavigationService.drivingDurationMatrix(points);
    if (matrix == null || matrix.length < points.length) {
      return null;
    }

    const stopOffset = 1;
    final count = withCoordinates.length;

    final firstStop = _nearestFromGps(matrix, stopOffset, count);
    if (firstStop == null) return null;

    final candidateOrders = <List<int>>[];

    candidateOrders.add(
      _greedyOrder(
        firstStop: firstStop,
        matrix: matrix,
        stopOffset: stopOffset,
        count: count,
      ),
    );

    candidateOrders.add(
      _cheapestInsertionOrder(
        firstStop: firstStop,
        matrix: matrix,
        stopOffset: stopOffset,
        count: count,
        finalDestinationIndex: finalDestinationIndex,
      ),
    );

    final secondCandidates = <({int stop, double duration})>[];
    for (var i = 0; i < count; i++) {
      if (i == firstStop) continue;
      final duration =
          _matrixValue(matrix, stopOffset + firstStop, stopOffset + i);
      if (duration != null) {
        secondCandidates.add((stop: i, duration: duration));
      }
    }
    secondCandidates.sort((a, b) => a.duration.compareTo(b.duration));

    for (final option in secondCandidates.take(4)) {
      candidateOrders.add(
        _greedyOrder(
          firstStop: firstStop,
          forcedSecondStop: option.stop,
          matrix: matrix,
          stopOffset: stopOffset,
          count: count,
        ),
      );
    }

    List<int>? bestOrder;
    var bestCost = double.infinity;

    for (final seed in candidateOrders) {
      if (seed.length != count) continue;

      final refined = _refineOrder(
        seed,
        matrix,
        stopOffset,
        finalDestinationIndex,
      );

      final cost = _routeCost(
        refined,
        matrix,
        stopOffset,
        finalDestinationIndex,
      );

      if (cost < bestCost) {
        bestCost = cost;
        bestOrder = refined;
      }
    }

    if (bestOrder == null) return null;

    final optimized =
        bestOrder.map((index) => withCoordinates[index]).toList();

    return [...completed, ...optimized, ...withoutCoordinates];
  }

  static int? _nearestFromGps(
    List<List<double?>> matrix,
    int stopOffset,
    int count,
  ) {
    int? best;
    double? bestDuration;

    for (var i = 0; i < count; i++) {
      final duration = _matrixValue(matrix, 0, stopOffset + i);
      if (duration == null) continue;

      if (bestDuration == null || duration < bestDuration) {
        bestDuration = duration;
        best = i;
      }
    }

    return best;
  }

  static List<int> _greedyOrder({
    required int firstStop,
    int? forcedSecondStop,
    required List<List<double?>> matrix,
    required int stopOffset,
    required int count,
  }) {
    final remaining = <int>{
      for (var i = 0; i < count; i++) i,
    };

    final order = <int>[firstStop];
    remaining.remove(firstStop);

    var current = firstStop;

    if (forcedSecondStop != null &&
        forcedSecondStop != firstStop &&
        remaining.remove(forcedSecondStop)) {
      order.add(forcedSecondStop);
      current = forcedSecondStop;
    }

    while (remaining.isNotEmpty) {
      int? best;
      double? bestDuration;

      for (final candidate in remaining) {
        final duration = _matrixValue(
          matrix,
          stopOffset + current,
          stopOffset + candidate,
        );
        if (duration == null) continue;

        if (bestDuration == null || duration < bestDuration) {
          bestDuration = duration;
          best = candidate;
        }
      }

      if (best == null) {
        order.addAll(remaining);
        break;
      }

      order.add(best);
      remaining.remove(best);
      current = best;
    }

    return order;
  }

  static List<int> _cheapestInsertionOrder({
    required int firstStop,
    required List<List<double?>> matrix,
    required int stopOffset,
    required int count,
    required int? finalDestinationIndex,
  }) {
    final remaining = <int>{
      for (var i = 0; i < count; i++) i,
    }..remove(firstStop);

    final order = <int>[firstStop];

    while (remaining.isNotEmpty) {
      int? bestStop;
      int? bestPosition;
      var bestCost = double.infinity;

      for (final stop in remaining) {
        for (var position = 1; position <= order.length; position++) {
          final candidate = List<int>.from(order)..insert(position, stop);
          final cost = _routeCost(
            candidate,
            matrix,
            stopOffset,
            finalDestinationIndex,
          );

          if (cost < bestCost) {
            bestCost = cost;
            bestStop = stop;
            bestPosition = position;
          }
        }
      }

      if (bestStop == null || bestPosition == null) {
        order.addAll(remaining);
        break;
      }

      order.insert(bestPosition, bestStop);
      remaining.remove(bestStop);
    }

    return order;
  }

  static List<int> _refineOrder(
    List<int> seed,
    List<List<double?>> matrix,
    int stopOffset,
    int? finalDestinationIndex,
  ) {
    var best = List<int>.from(seed);
    var bestCost = _routeCost(
      best,
      matrix,
      stopOffset,
      finalDestinationIndex,
    );

    var improved = true;
    var passes = 0;

    while (improved && passes < 8) {
      improved = false;
      passes++;

      List<int>? passBest;
      var passBestCost = bestCost;

      for (var from = 1; from < best.length; from++) {
        for (var to = 1; to < best.length; to++) {
          if (from == to) continue;

          final candidate = List<int>.from(best);
          final item = candidate.removeAt(from);
          candidate.insert(to, item);

          final cost = _routeCost(
            candidate,
            matrix,
            stopOffset,
            finalDestinationIndex,
          );

          if (cost + 0.5 < passBestCost) {
            passBest = candidate;
            passBestCost = cost;
          }
        }
      }

      for (var i = 1; i < best.length - 1; i++) {
        for (var j = i + 1; j < best.length; j++) {
          final candidate = List<int>.from(best);
          final temp = candidate[i];
          candidate[i] = candidate[j];
          candidate[j] = temp;

          final cost = _routeCost(
            candidate,
            matrix,
            stopOffset,
            finalDestinationIndex,
          );

          if (cost + 0.5 < passBestCost) {
            passBest = candidate;
            passBestCost = cost;
          }
        }
      }

      for (var i = 1; i < best.length - 1; i++) {
        for (var j = i + 1; j < best.length; j++) {
          final candidate = List<int>.from(best);
          candidate.replaceRange(
            i,
            j + 1,
            candidate.sublist(i, j + 1).reversed,
          );

          final cost = _routeCost(
            candidate,
            matrix,
            stopOffset,
            finalDestinationIndex,
          );

          if (cost + 0.5 < passBestCost) {
            passBest = candidate;
            passBestCost = cost;
          }
        }
      }

      if (passBest != null) {
        best = passBest;
        bestCost = passBestCost;
        improved = true;
      }
    }

    return best;
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
