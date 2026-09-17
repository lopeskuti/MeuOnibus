import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class RailLine {
  final String id;
  final String name;
  final String mode;
  final int color;
  final List<List<LatLng>> paths;

  const RailLine({required this.id, required this.name, required this.mode, required this.color, required this.paths});

  factory RailLine.fromJson(Map<String, dynamic> json) => RailLine(
        id: json['id'].toString(),
        name: json['name'].toString(),
        mode: json['mode'].toString(),
        color: int.parse((json['color'] ?? '0xff455a64').toString()),
        paths: (json['paths'] as List? ?? const [])
            .whereType<List>()
            .map((path) => path
                .whereType<List>()
                .where((point) => point.length >= 2)
                .map((point) => LatLng((point[0] as num).toDouble(), (point[1] as num).toDouble()))
                .toList(growable: false))
            .where((path) => path.length >= 2)
            .toList(growable: false),
      );
}

class RailStation {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final List<String> lineIds;

  const RailStation({required this.id, required this.name, required this.lat, required this.lon, required this.lineIds});

  factory RailStation.fromJson(Map<String, dynamic> json) => RailStation(
        id: json['id'].toString(),
        name: json['name'].toString(),
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        lineIds: (json['lineIds'] as List? ?? const []).map((item) => item.toString()).toList(growable: false),
      );
}

class RailRepository {
  List<RailStation> _stations = const [];
  Map<String, RailLine> _lines = const {};

  bool get hasData => _stations.isNotEmpty;

  Future<void> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/rail/rail_network.json')) as Map<String, dynamic>;
    _stations = (raw['stations'] as List? ?? const [])
        .map((item) => RailStation.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    _lines = {
      for (final item in (raw['lines'] as List? ?? const []))
        (item as Map)['id'].toString(): RailLine.fromJson(Map<String, dynamic>.from(item)),
    };
  }

  List<RailStation> nearby(double lat, double lon, {double radiusMeters = 1200}) {
    const distance = Distance();
    final here = LatLng(lat, lon);
    final result = _stations.where((station) => distance(here, LatLng(station.lat, station.lon)) <= radiusMeters).toList();
    result.sort((a, b) => distance(here, LatLng(a.lat, a.lon)).compareTo(distance(here, LatLng(b.lat, b.lon))));
    return result;
  }

  List<RailLine> linesFor(RailStation station) =>
      station.lineIds.map((id) => _lines[id]).whereType<RailLine>().toList(growable: false);

  RailLine? lineForId(String id) => _lines[id];
}
