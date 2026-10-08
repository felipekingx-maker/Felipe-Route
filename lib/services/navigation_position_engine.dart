import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

class NavigationVisualState {
  final LatLng point;
  final double heading;
  final double speed;
  final DateTime updatedAt;
  final double routeDistanceMeters;

  const NavigationVisualState({
    required this.point,
    required this.heading,
    required this.speed,
    required this.updatedAt,
    required this.routeDistanceMeters,
  });
}

class NavigationPositionEngine {
  NavigationVisualState? _state;
  DateTime? _lastRawAt;
  LatLng? _lastRawPoint;

  NavigationVisualState? get state => _state;

  void reset() {
    _state = null;
    _lastRawAt = null;
    _lastRawPoint = null;
  }

  NavigationVisualState update({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double speed,
    required double heading,
    required DateTime timestamp,
    required List<LatLng> route,
  }) {
    final raw = LatLng(latitude, longitude);
    final previousRaw = _lastRawPoint;
    final previousRawAt = _lastRawAt;

    if (previousRaw != null && previousRawAt != null) {
      final dt = timestamp.difference(previousRawAt).inMilliseconds / 1000.0;
      if (dt > 0.15) {
        final jump = _distance(previousRaw, raw);
        final impliedSpeed = jump / dt;

        // Rejeita saltos claramente impossíveis. GPS urbano pode errar
        // dezenas de metros, então o limite é deliberadamente conservador.
        if (impliedSpeed > 70 && accuracy < 80) {
          return _state ??
              NavigationVisualState(
                point: raw,
                heading: _normalizeHeading(heading),
                speed: math.max(0, speed),
                updatedAt: timestamp,
                routeDistanceMeters: double.infinity,
              );
        }
      }
    }

    _lastRawPoint = raw;
    _lastRawAt = timestamp;

    final snapped = route.length >= 2
        ? _nearestPointOnRoute(raw, route)
        : _SnapResult(point: raw, distanceMeters: double.infinity);

    // Só prende o carro à rota quando o GPS está razoavelmente perto dela.
    // Isso evita "teletransportar" para uma rua errada/paralela.
    final snapLimit = accuracy.isFinite
        ? math.max(18.0, math.min(45.0, accuracy * 1.6))
        : 30.0;
    final target = snapped.distanceMeters <= snapLimit ? snapped.point : raw;

    final current = _state;
    if (current == null) {
      final initial = NavigationVisualState(
        point: target,
        heading: _normalizeHeading(heading),
        speed: math.max(0, speed),
        updatedAt: timestamp,
        routeDistanceMeters: snapped.distanceMeters,
      );
      _state = initial;
      return initial;
    }

    final quality = accuracy.isFinite ? accuracy : 30.0;
    final positionAlpha = quality <= 8
        ? 0.48
        : quality <= 15
            ? 0.34
            : quality <= 30
                ? 0.22
                : 0.14;

    final smoothedPoint = LatLng(
      _lerp(current.point.latitude, target.latitude, positionAlpha),
      _lerp(current.point.longitude, target.longitude, positionAlpha),
    );

    final rawHeading = heading.isFinite && heading >= 0
        ? _normalizeHeading(heading)
        : current.heading;
    final headingAlpha = speed > 5
        ? 0.28
        : speed > 1.5
            ? 0.18
            : 0.08;

    final visual = NavigationVisualState(
      point: smoothedPoint,
      heading: _lerpAngle(current.heading, rawHeading, headingAlpha),
      speed: _lerp(current.speed, math.max(0, speed), 0.30),
      updatedAt: timestamp,
      routeDistanceMeters: snapped.distanceMeters,
    );
    _state = visual;
    return visual;
  }

  NavigationVisualState? predict(DateTime now) {
    final current = _state;
    if (current == null) return null;

    final age = now.difference(current.updatedAt).inMilliseconds / 1000.0;
    if (age <= 0) return current;

    // Previsão curta apenas para preencher o intervalo entre leituras do GPS.
    final predictionSeconds = math.min(age, 1.2);
    final meters = current.speed * predictionSeconds;
    if (meters < 0.08) return current;

    return NavigationVisualState(
      point: _pointAhead(current.point, current.heading, meters),
      heading: current.heading,
      speed: current.speed,
      updatedAt: current.updatedAt,
      routeDistanceMeters: current.routeDistanceMeters,
    );
  }

  _SnapResult _nearestPointOnRoute(LatLng point, List<LatLng> route) {
    var bestPoint = route.first;
    var bestDistance = double.infinity;

    for (var i = 0; i < route.length - 1; i++) {
      final candidate = _projectOnSegment(point, route[i], route[i + 1]);
      final distance = _distance(point, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = candidate;
      }
    }

    return _SnapResult(point: bestPoint, distanceMeters: bestDistance);
  }

  LatLng _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    final meanLat = (a.latitude + b.latitude + p.latitude) / 3;
    final cosLat = math.cos(meanLat * math.pi / 180);

    double x(double lon) => lon * cosLat;
    double y(double lat) => lat;

    final ax = x(a.longitude);
    final ay = y(a.latitude);
    final bx = x(b.longitude);
    final by = y(b.latitude);
    final px = x(p.longitude);
    final py = y(p.latitude);

    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 <= 1e-18) return a;

    final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final projX = ax + dx * t;
    final projY = ay + dy * t;

    return LatLng(projY, projX / cosLat);
  }

  LatLng _pointAhead(LatLng start, double bearingDegrees, double meters) {
    const earthRadius = 6378137.0;
    final bearing = bearingDegrees * math.pi / 180;
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
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

  double _distance(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  double _normalizeHeading(double value) {
    var result = value % 360;
    if (result < 0) result += 360;
    return result;
  }

  double _lerpAngle(double a, double b, double t) {
    final delta = ((b - a + 540) % 360) - 180;
    return _normalizeHeading(a + delta * t);
  }
}

class _SnapResult {
  final LatLng point;
  final double distanceMeters;

  const _SnapResult({
    required this.point,
    required this.distanceMeters,
  });
}
