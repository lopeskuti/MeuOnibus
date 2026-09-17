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


class BusTerminalPlatform {
  final String name;
  final List<String> stopIds;
  final List<String> outboundRouteIds;
  const BusTerminalPlatform({required this.name, required this.stopIds, this.outboundRouteIds = const []});
  factory BusTerminalPlatform.fromJson(Map<String, dynamic> json) => BusTerminalPlatform(
        name: (json['name'] ?? 'Plataforma').toString(),
        stopIds: (json['stopIds'] as List? ?? const []).map((id) => id.toString()).toList(growable: false),
        outboundRouteIds: (json['outboundRouteIds'] as List? ?? const []).map((id) => id.toString()).toList(growable: false),
      );
}

class BusTerminal {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final List<BusTerminalPlatform> platforms;
  const BusTerminal({required this.id, required this.name, required this.lat, required this.lon, required this.platforms});
  factory BusTerminal.fromJson(Map<String, dynamic> json) => BusTerminal(
        id: json['id'].toString(),
        name: (json['name'] ?? 'Terminal').toString(),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        platforms: (json['platforms'] as List? ?? const [])
            .map((item) => BusTerminalPlatform.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
}


class RouteSchedule {
  final String operatingDays;
  final String firstDeparture;
  final String lastDeparture;
  final int? averageHeadwayMinutes;

  const RouteSchedule({
    required this.operatingDays,
    required this.firstDeparture,
    required this.lastDeparture,
    this.averageHeadwayMinutes,
  });

  factory RouteSchedule.fromJson(Map<String, dynamic> json) => RouteSchedule(
        operatingDays: (json['operatingDays'] ?? 'Consulte a operação').toString(),
        firstDeparture: (json['firstDeparture'] ?? '--:--').toString(),
        lastDeparture: (json['lastDeparture'] ?? '--:--').toString(),
        averageHeadwayMinutes: (json['averageHeadwayMinutes'] as num?)?.round(),
      );
}
