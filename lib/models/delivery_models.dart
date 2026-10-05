enum DeliveryStatus { pending, delivered, problem, skipped }

class DeliveryPackage {
  final String code;
  final String stopLabel;
  final String address;
  final String? recipient;
  final String? complement;
  final String? physicalStopId;
  final double? latitude;
  final double? longitude;
  DeliveryStatus status;

  DeliveryPackage({
    required this.code,
    required this.stopLabel,
    required this.address,
    this.recipient,
    this.complement,
    this.physicalStopId,
    this.latitude,
    this.longitude,
    this.status = DeliveryStatus.pending,
  });
}

class PhysicalStop {
  final String id;
  final String address;
  final String? complement;
  final double? latitude;
  final double? longitude;
  final List<DeliveryPackage> packages;

  PhysicalStop({
    required this.id,
    required this.address,
    required this.packages,
    this.complement,
    this.latitude,
    this.longitude,
  });

  int get totalPackages => packages.length;

  Map<String, int> get packagesByStop {
    final result = <String, int>{};
    for (final package in packages) {
      result.update(package.stopLabel, (value) => value + 1, ifAbsent: () => 1);
    }
    return result;
  }

  bool get hasGroupedStops => packagesByStop.length > 1;

  bool get completed => packages.every(
        (package) => package.status == DeliveryStatus.delivered,
      );
}

class DeliveryRoute {
  final String name;
  final List<PhysicalStop> stops;

  DeliveryRoute({
    required this.name,
    required this.stops,
  });

  int get totalPackages =>
      stops.fold(0, (sum, stop) => sum + stop.totalPackages);

  int get deliveredPackages => stops
      .expand((stop) => stop.packages)
      .where((package) => package.status == DeliveryStatus.delivered)
      .length;

  int get deliveredStops => stops.where((stop) => stop.completed).length;
}
