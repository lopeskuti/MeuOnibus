import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/transit_models.dart';
import '../services/gtfs_repository.dart';
import '../services/olho_vivo_service.dart';

class RouteMapScreen extends StatefulWidget {
  final BusRoute route;
  final GtfsRepository gtfs;
  final OlhoVivoService api;
  const RouteMapScreen({super.key, required this.route, required this.gtfs, required this.api});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  List<VehiclePosition> _vehicles = const [];
  Timer? _timer;
  int? _lineCode;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _initRealtime();
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
      if (mounted) setState(() { _vehicles = vehicles; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final shape = widget.gtfs.shapeFor(widget.route);
    final center = shape.isNotEmpty ? shape[shape.length ~/ 2] : const LatLng(-23.55052, -46.633308);

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
          IconButton(onPressed: _loading ? null : _refresh, tooltip: 'Atualizar ônibus', icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 13, minZoom: 10, maxZoom: 19),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'br.com.lopeskuti.meuonibus'),
            if (shape.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: shape, strokeWidth: 7, color: Colors.white.withValues(alpha: .9)),
                Polyline(points: shape, strokeWidth: 4.5, color: const Color(0xFFE5252A)),
              ]),
            MarkerLayer(markers: _vehicles.map((v) => Marker(
              point: LatLng(v.lat, v.lon),
              width: 46,
              height: 46,
              child: _busMarker(v),
            )).toList()),
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
          bottom: 14,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(color: Color(0xFFE5252A), shape: BoxShape.circle),
                  child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Veículos em circulação', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('${_vehicles.length} ônibus • atualização a cada 15 s', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
