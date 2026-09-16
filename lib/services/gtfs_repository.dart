import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/transit_models.dart';

class GtfsRepository {
  List<BusStop> _stops = const [];
  Map<String, List<String>> _stopRoutes = const {};
  Map<String, BusRoute> _routes = const {};
  Map<String, List<LatLng>> _shapes = const {};
  List<BusTerminal> _terminals = const [];
  Set<String> _terminalStopIds = const {};
  Map<String, RouteSchedule> _schedules = const {};

  bool get hasData => _stops.isNotEmpty;

  Future<void> load() async {
    final stopsRaw = jsonDecode(await rootBundle.loadString('assets/gtfs/stops.json')) as List;
    final stopRoutesRaw = jsonDecode(await rootBundle.loadString('assets/gtfs/stop_routes.json')) as Map<String, dynamic>;
    final routesRaw = jsonDecode(await rootBundle.loadString('assets/gtfs/routes.json')) as Map<String, dynamic>;
    final shapesRaw = jsonDecode(await rootBundle.loadString('assets/gtfs/shapes.json')) as Map<String, dynamic>;
    final terminalsRaw = jsonDecode(await rootBundle.loadString('assets/gtfs/terminals.json')) as List;
    final schedulesRaw = jsonDecode(await rootBundle.loadString('assets/gtfs/schedules.json')) as Map<String, dynamic>;

    _stops = stopsRaw.map((e) => BusStop.fromJson(Map<String, dynamic>.from(e))).toList(growable: false);
    _stopRoutes = stopRoutesRaw.map((k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList(growable: false)));
    _routes = routesRaw.map((k, v) => MapEntry(k, BusRoute.fromJson(k, Map<String, dynamic>.from(v))));
    _terminals = terminalsRaw.map((item) => BusTerminal.fromJson(Map<String, dynamic>.from(item))).toList(growable: false);
    _terminalStopIds = _terminals.expand((terminal) => terminal.platforms).expand((platform) => platform.stopIds).toSet();
    _schedules = schedulesRaw.map((id, value) => MapEntry(id, RouteSchedule.fromJson(Map<String, dynamic>.from(value))));
    _shapes = shapesRaw.map((k, v) => MapEntry(k, (v as List).map((p) {
      final pair = p as List;
      return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
    }).toList(growable: false)));
  }

  List<BusStop> nearby(double lat, double lon, {double radiusMeters = 900}) {
    const distance = Distance();
    final here = LatLng(lat, lon);
    final result = _stops.where((s) => distance(here, LatLng(s.lat, s.lon)) <= radiusMeters).toList();
    result.sort((a, b) => distance(here, LatLng(a.lat, a.lon)).compareTo(distance(here, LatLng(b.lat, b.lon))));
    return result;
  }

  List<BusTerminal> terminalsNearby(double lat, double lon, {double radiusMeters = 900}) {
    const distance = Distance();
    final here = LatLng(lat, lon);
    final result = _terminals.where((terminal) => distance(here, LatLng(terminal.lat, terminal.lon)) <= radiusMeters).toList();
    result.sort((a, b) => distance(here, LatLng(a.lat, a.lon)).compareTo(distance(here, LatLng(b.lat, b.lon))));
    return result;
  }

  bool isTerminalStop(BusStop stop) => _terminalStopIds.contains(stop.id);

  List<BusRoute> routesForPlatform(BusTerminalPlatform platform) {
    final routes = <String, BusRoute>{};
    for (final stopId in platform.stopIds) {
      for (final route in routesForStop(stopId)) { routes[route.id] = route; }
    }
    final result = routes.values.toList()..sort((a, b) => a.shortName.compareTo(b.shortName));
    return result;
  }

  BusStop? stopForRoute(BusTerminalPlatform platform, BusRoute route) {
    for (final stopId in platform.stopIds) {
      if ((_stopRoutes[stopId] ?? const []).contains(route.id)) {
        for (final stop in _stops) { if (stop.id == stopId) return stop; }
      }
    }
    return null;
  }

  List<BusRoute> routesForStop(String stopId) => (_stopRoutes[stopId] ?? const [])
      .map((id) => _routes[id])
      .whereType<BusRoute>()
      .toList(growable: false);

  List<BusRoute> searchRoutes(String query, {int limit = 40}) {
    final terms = _normalise(query).split(' ').where((term) => term.isNotEmpty).toList();
    if (terms.isEmpty) return const [];

    final matches = _routes.values.where((route) {
      final searchable = _normalise('${route.shortName} ${route.longName}');
      return terms.every(searchable.contains);
    }).toList();
    matches.sort((a, b) {
      final aExact = _normalise(a.shortName) == terms.join(' ');
      final bExact = _normalise(b.shortName) == terms.join(' ');
      if (aExact != bExact) return aExact ? -1 : 1;
      return a.shortName.compareTo(b.shortName);
    });
    return matches.take(limit).toList(growable: false);
  }

  String _normalise(String value) {
    const accented = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const plain = 'aaaaaeeeeiiiiooooouuuuc';
    var result = value.toLowerCase();
    for (var i = 0; i < accented.length; i++) {
      result = result.replaceAll(accented[i], plain[i]);
    }
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  RouteSchedule? scheduleFor(BusRoute route) => _schedules[route.id];

  List<LatLng> shapeFor(BusRoute route) => route.shapeId == null ? const [] : (_shapes[route.shapeId!] ?? const []);
}
