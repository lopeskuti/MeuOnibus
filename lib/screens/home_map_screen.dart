import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/transit_models.dart';
import '../services/gtfs_repository.dart';
import '../services/location_service.dart';
import '../services/olho_vivo_service.dart';
import 'route_map_screen.dart';

class HomeMapScreen extends StatefulWidget {
  final GtfsRepository gtfs;
  final OlhoVivoService api;
  const HomeMapScreen({super.key, required this.gtfs, required this.api});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final _map = MapController();
  final _location = LocationService();
  LatLng? _me;
  List<BusStop> _nearby = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.gtfs.load();
      final p = await _location.current();
      final me = LatLng(p.latitude, p.longitude);
      final stops = widget.gtfs.nearby(p.latitude, p.longitude, radiusMeters: 1200);
      if (!mounted) return;
      setState(() { _me = me; _nearby = stops; _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) => _map.move(me, 16));
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _distanceLabel(BusStop stop) {
    final me = _me;
    if (me == null) return '';
    const distance = Distance();
    final meters = distance(me, LatLng(stop.lat, stop.lon)).round();
    return meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _openStop(BusStop stop) async {
    final choices = widget.gtfs.routesForStop(stop.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(stop.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${choices.length} linha(s) neste ponto • ${_distanceLabel(stop)}', style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: choices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                  itemBuilder: (_, i) {
                    final route = choices[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      leading: Container(
                        width: 52,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                        child: Text(route.shortName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      title: Text(route.longName.isEmpty ? route.shortName : route.longName, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Linha ${route.shortName}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RouteMapScreen(route: route, gtfs: widget.gtfs, api: widget.api)));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stopMarker(BusStop stop) => GestureDetector(
    onTap: () => _openStop(stop),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF087CCB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 22),
    ),
  );

  Widget _locationMarker() => Stack(alignment: Alignment.center, children: [
    Container(width: 40, height: 40, decoration: const BoxDecoration(color: Color(0x33087CCB), shape: BoxShape.circle)),
    Container(width: 18, height: 18, decoration: BoxDecoration(color: const Color(0xFF087CCB), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)])),
  ]);

  @override
  Widget build(BuildContext context) {
    final initial = _me ?? const LatLng(-23.55052, -46.633308);
    final visibleStops = _nearby.take(3).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: const Color(0xFF087CCB), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Meu Ônibus', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('Seu próximo ônibus, mais perto de você', style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
        actions: [
          IconButton(onPressed: _bootstrap, tooltip: 'Atualizar localização', icon: const Icon(Icons.my_location_rounded)),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: initial, initialZoom: 13, minZoom: 10, maxZoom: 19),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'br.com.lopeskuti.meuonibus'),
            MarkerLayer(markers: [
              if (_me != null) Marker(point: _me!, width: 40, height: 40, child: _locationMarker()),
              ..._nearby.map((stop) => Marker(point: LatLng(stop.lat, stop.lon), width: 42, height: 42, child: _stopMarker(stop))),
            ]),
            RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        if (!_loading && visibleStops.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Text('Pontos próximos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${_nearby.length} encontrados', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 6),
                  ...visibleStops.map((stop) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(radius: 18, child: Icon(Icons.directions_bus_filled_rounded, size: 18)),
                    title: Text(stop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_distanceLabel(stop)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openStop(stop),
                  )),
                ]),
              ),
            ),
          ),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) Positioned(left: 16, right: 16, bottom: 24, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))),
        if (!_loading && !widget.gtfs.hasData)
          const Positioned(left: 16, right: 16, bottom: 24, child: Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Base GTFS vazia. Gere os assets com tools/prepare_gtfs.py; veja o README.')))),
      ]),
    );
  }
}
