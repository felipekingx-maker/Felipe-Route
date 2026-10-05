import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery_models.dart';

class RoutePersistenceService {
  static const _routeKey = 'felipe_route.saved_route';
  static const _indexKey = 'felipe_route.current_index';

  static Future<void> saveRoute(
    DeliveryRoute route, {
    int? currentIndex,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeKey, jsonEncode(_routeToJson(route)));

    if (currentIndex != null) {
      await prefs.setInt(_indexKey, currentIndex);
    }
  }

  static Future<({DeliveryRoute route, int currentIndex})?> loadRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routeKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final route = _routeFromJson(decoded);
      final index = prefs.getInt(_indexKey) ?? 0;
      final safeIndex = route.stops.isEmpty
          ? 0
          : index.clamp(0, route.stops.length - 1);

      return (route: route, currentIndex: safeIndex);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_routeKey);
    await prefs.remove(_indexKey);
  }

  static Map<String, dynamic> _routeToJson(DeliveryRoute route) => {
        'name': route.name,
        'stopDurationMinutes': route.stopDurationMinutes,
        'finalDestinationAddress': route.finalDestinationAddress,
        'finalDestinationLatitude': route.finalDestinationLatitude,
        'finalDestinationLongitude': route.finalDestinationLongitude,
        'stops': route.stops.map(_stopToJson).toList(),
      };

  static DeliveryRoute _routeFromJson(Map<String, dynamic> json) {
    final stopsJson = json['stops'];
    final stops = stopsJson is List
        ? stopsJson
            .whereType<Map>()
            .map((item) => _stopFromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <PhysicalStop>[];

    return DeliveryRoute(
      name: json['name']?.toString() ?? 'Rota salva',
      stops: stops,
      stopDurationMinutes:
          int.tryParse(json['stopDurationMinutes']?.toString() ?? '') ?? 3,
      finalDestinationAddress: json['finalDestinationAddress']?.toString(),
      finalDestinationLatitude:
          (json['finalDestinationLatitude'] as num?)?.toDouble(),
      finalDestinationLongitude:
          (json['finalDestinationLongitude'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic> _stopToJson(PhysicalStop stop) => {
        'id': stop.id,
        'address': stop.address,
        'complement': stop.complement,
        'latitude': stop.latitude,
        'longitude': stop.longitude,
        'packages': stop.packages.map(_packageToJson).toList(),
      };

  static PhysicalStop _stopFromJson(Map<String, dynamic> json) {
    final packagesJson = json['packages'];
    final packages = packagesJson is List
        ? packagesJson
            .whereType<Map>()
            .map((item) => _packageFromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <DeliveryPackage>[];

    return PhysicalStop(
      id: json['id']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      complement: json['complement']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      packages: packages,
    );
  }

  static Map<String, dynamic> _packageToJson(DeliveryPackage package) => {
        'code': package.code,
        'stopLabel': package.stopLabel,
        'address': package.address,
        'recipient': package.recipient,
        'complement': package.complement,
        'physicalStopId': package.physicalStopId,
        'latitude': package.latitude,
        'longitude': package.longitude,
        'status': package.status.name,
      };

  static DeliveryPackage _packageFromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString();
    final status = DeliveryStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => DeliveryStatus.pending,
    );

    return DeliveryPackage(
      code: json['code']?.toString() ?? '',
      stopLabel: json['stopLabel']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      recipient: json['recipient']?.toString(),
      complement: json['complement']?.toString(),
      physicalStopId: json['physicalStopId']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      status: status,
    );
  }
}
