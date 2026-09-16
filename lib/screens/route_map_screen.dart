import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/transit_models.dart';
import '../services/gtfs_repository.dart';
import '../services/location_service.dart';
import '../services/olho_vivo_service.dart';

class RouteMapScreen extends StatefulWidget {
  final BusRoute route;
  final BusStop stop;
  final LatLng? initialLocation;
  final GtfsRepository gtfs;
  final OlhoVivoService api;

  const RouteMapScreen({
    super.key,
    required this.route,
    required this.stop,
    required this.gtfs,
    required this.api,
    this.initialLocation,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _map = MapController();
  final _location = LocationService();
  StreamSubscription<Position>? _locationSubscription;
  List<VehiclePosition> _vehicles = const [];
  List<ArrivalPrediction> _arrivals = const [];
  Timer? _timer;
  int? _lineCode;
  LatLng? _me;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _me = widget.initialLocation;
    _startLocationTracking();
    _initRealtime();
  }

  Future<void> _startLocationTracking() async {
    try {
      final current = await _location.current();
      _updateLocation(current);
      final stream = await _location.foregroundPositions();
      _locationSubscription = stream.listen(
        _updateLocation,
        onError: (Object e) {
          if (mounted) setState(() => _error ??= e.toString());
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error ??= e.toString());
    }
  }

  void _updateLocation(Position position) {
    final me = LatLng(position.latitude, position.longitude);
    if (!mounted) return;
    setState(() => _me = me);
    WidgetsBinding.instance.addPostFrameCallback((_) => _map.move(me, 16));
  }

  Future<void> _initRealtime() async {
    try {
      _lineCode = widget.route.sptransCode ?? await widget.api.resolveLineCode(widget.route);
      if (_lineCode == null) throw OlhoVivoException('Não encontrei esta linha na Olho Vivo.');
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _refresh() async {
    final code = _lineCode;
    if (code == null || _loading) return;
    _loading = true;
    try {
      final vehicles = await widget.api.vehicles(code);
      List<ArrivalPrediction> arrivals = const [];
      try {
        arrivals = await widget.api.arrivals(code, widget.stop.id);
      } catch (_) {
        // Mantém o mapa funcionando mesmo quando a previsão estiver indisponível.
      }
      if (mounted) setState(() { _vehicles = vehicles; _arrivals = arrivals; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  Widget _busMarker(VehiclePosition v) => Tooltip(
    message: 'Prefixo ${v.prefix}${v.accessible ? ' • acessível' : ''}',
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE5252A),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 24),
    ),
  );

  Widget _locationMarker() => Stack(alignment: Alignment.center, children: [
    Container(width: 54, height: 54, decoration: const BoxDecoration(color: Color(0x44087CCB), shape: BoxShape.circle)),
    Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: const Color(0xFF087CCB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)],
      ),
      child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 14),
    ),
  ]);

  Widget _selectedStopMarker() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF0B8F55),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(blurRadius: 7, color: Colors.black26)],
    ),
    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 25),
  );

  @override
  Widget build(BuildContext context) {
    final shape = widget.gtfs.shapeFor(widget.route);
    final initial = _me ?? LatLng(widget.stop.lat, widget.stop.lon);
    final nextArrival = _arrivals.isEmpty ? null : _arrivals.first;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        backgroundColor: const Color(0xFF087CCB),
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.route.shortName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
          Text(widget.route.longName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: Colors.white70)),
        ]),
        actions: [
          IconButton(onPressed: _me == null ? null : () => _map.move(_me!, 16), tooltip: 'Minha localização', icon: const Icon(Icons.my_location_rounded)),
          IconButton(onPressed: _loading ? null : _refresh, tooltip: 'Atualizar ônibus', icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: initial, initialZoom: 16, minZoom: 10, maxZoom: 19),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'br.com.lopeskuti.meuonibus'),
            if (shape.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: shape, strokeWidth: 7, color: Colors.white.withValues(alpha: .9)),
                Polyline(points: shape, strokeWidth: 4.5, color: const Color(0xFFE5252A)),
              ]),
            MarkerLayer(markers: [
              Marker(point: LatLng(widget.stop.lat, widget.stop.lon), width: 46, height: 46, child: Tooltip(message: widget.stop.name, child: _selectedStopMarker())),
              if (_me != null) Marker(point: _me!, width: 54, height: 54, child: Tooltip(message: 'Você está aqui', child: _locationMarker())),
              ..._vehicles.map((v) => Marker(
                point: LatLng(v.lat, v.lon),
                width: 46,
                height: 46,
                child: _busMarker(v),
              )),
            ]),
            RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        if (_error != null)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!)),
                ]),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 14,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: Color(0xFFE5252A), shape: BoxShape.circle),
                  child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.stop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (nextArrival != null)
                      Text(
                        nextArrival.minutes <= 1
                            ? 'Próximo ônibus chegando • ${nextArrival.expectedAt}'
                            : 'Próximo ônibus em ${nextArrival.minutes} min • ${nextArrival.expectedAt}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      )
                    else
                      Text('Sem previsão disponível para este ponto', style: Theme.of(context).textTheme.bodySmall),
                    Text('${_vehicles.length} ônibus em circulação • atualização a cada 15 s', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
