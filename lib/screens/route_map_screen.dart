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

  @override
  Widget build(BuildContext context) {
    final shape = widget.gtfs.shapeFor(widget.route);
    final center = shape.isNotEmpty ? shape[shape.length ~/ 2] : const LatLng(-23.55052, -46.633308);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.route.shortName),
          Text(widget.route.longName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ]),
        actions: [IconButton(onPressed: _refresh, tooltip: 'Atualizar ônibus', icon: const Icon(Icons.refresh))],
      ),
      body: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 13, minZoom: 10, maxZoom: 19),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'br.com.lopeskuti.meuonibus'),
            if (shape.length > 1) PolylineLayer(polylines: [Polyline(points: shape, strokeWidth: 5)]),
            MarkerLayer(markers: _vehicles.map((v) => Marker(
              point: LatLng(v.lat, v.lon), width: 46, height: 46,
              child: Tooltip(message: 'Prefixo ${v.prefix}${v.accessible ? ' • acessível' : ''}', child: const Icon(Icons.directions_bus, size: 36)),
            )).toList()),
            RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        if (_error != null) Positioned(left: 12, right: 12, top: 12, child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)))),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Text('${_vehicles.length} veículo(s) no trajeto • atualização a cada 15 s', textAlign: TextAlign.center))),
    );
  }
}
