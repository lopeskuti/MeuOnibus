class BusStop {
  final String id;
  final String name;
  final double lat;
  final double lon;

  const BusStop({required this.id, required this.name, required this.lat, required this.lon});

  factory BusStop.fromJson(Map<String, dynamic> json) => BusStop(
        id: json['id'].toString(),
        name: (json['name'] ?? 'Ponto').toString(),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );
}

class BusRoute {
  final String id;
  final String shortName;
  final String longName;
  final String? shapeId;
  final int? sptransCode;

  const BusRoute({required this.id, required this.shortName, required this.longName, this.shapeId, this.sptransCode});

  factory BusRoute.fromJson(String id, Map<String, dynamic> json) => BusRoute(
        id: id,
        shortName: (json['shortName'] ?? id).toString(),
        longName: (json['longName'] ?? '').toString(),
        shapeId: json['shapeId']?.toString(),
        sptransCode: (json['sptransCode'] as num?)?.toInt(),
      );
}

class VehiclePosition {
  final String prefix;
  final bool accessible;
  final DateTime? capturedAt;
  final double lat;
  final double lon;

  const VehiclePosition({required this.prefix, required this.accessible, required this.capturedAt, required this.lat, required this.lon});

  factory VehiclePosition.fromJson(Map<String, dynamic> json) => VehiclePosition(
        prefix: json['p'].toString(),
        accessible: json['a'] == true,
        capturedAt: DateTime.tryParse((json['ta'] ?? '').toString()),
        lat: (json['py'] as num).toDouble(),
        lon: (json['px'] as num).toDouble(),
      );
}

class StopLine {
  final int sptransCode;
  final String display;
  final String destination;
  final int direction;

  const StopLine({required this.sptransCode, required this.display, required this.destination, required this.direction});
}
