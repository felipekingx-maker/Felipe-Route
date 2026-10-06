enum DeliveryStatus { pending, delivered, problem, skipped }

class DeliveryPackage {
  String code;
  String stopLabel;
  String address;
  String? recipient;
  String? complement;
  String? notes;
  String? physicalStopId;
  double? latitude;
  double? longitude;
  DeliveryStatus status;

  DeliveryPackage({
    required this.code,
    required this.stopLabel,
    required this.address,
    this.recipient,
    this.complement,
    this.notes,
    this.physicalStopId,
    this.latitude,
    this.longitude,
    this.status = DeliveryStatus.pending,
  });
}

class PhysicalStop {
  String id;
  String address;
  String? complement;
  double? latitude;
  double? longitude;
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

  bool get completed => packages.isNotEmpty &&
      packages.every((package) => package.status == DeliveryStatus.delivered);
}

class DeliveryRoute {
  String name;
  final List<PhysicalStop> stops;
  int stopDurationMinutes;
  String? finalDestinationAddress;
  double? finalDestinationLatitude;
  double? finalDestinationLongitude;

  DeliveryRoute({
    required this.name,
    required this.stops,
    this.stopDurationMinutes = 3,
    this.finalDestinationAddress,
    this.finalDestinationLatitude,
    this.finalDestinationLongitude,
  });

  int get totalPackages =>
      stops.fold(0, (sum, stop) => sum + stop.totalPackages);

  int get deliveredPackages => stops
      .expand((stop) => stop.packages)
      .where((package) => package.status == DeliveryStatus.delivered)
      .length;

  int get deliveredStops => stops.where((stop) => stop.completed).length;

  int get remainingStops => stops.length - deliveredStops;

  Duration get estimatedServiceTime =>
      Duration(minutes: remainingStops * stopDurationMinutes);
}
