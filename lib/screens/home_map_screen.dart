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

  Future<void> _openStop(BusStop stop) async {
    final choices = widget.gtfs.routesForStop(stop.id);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stop.name, style: Theme.of(context).textTheme.titleLarge),
                Text('${choices.length} linha(s) neste ponto'),
              ]),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: choices.length,
                itemBuilder: (_, i) {
                  final route = choices[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text(route.shortName, style: const TextStyle(fontSize: 10))),
                    title: Text(route.shortName),
                    subtitle: Text(route.longName),
                    trailing: const Icon(Icons.chevron_right),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _me ?? const LatLng(-23.55052, -46.633308);
    return Scaffold(
      appBar: AppBar(title: const Text('Meu Ônibus'), actions: [
        IconButton(onPressed: _bootstrap, tooltip: 'Atualizar localização', icon: const Icon(Icons.my_location)),
      ]),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: initial, initialZoom: 13, minZoom: 10, maxZoom: 19),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'br.com.lopeskuti.meuonibus'),
            MarkerLayer(markers: [
              if (_me != null) Marker(point: _me!, width: 38, height: 38, child: const Icon(Icons.my_location, size: 34)),
              ..._nearby.map((stop) => Marker(
                    point: LatLng(stop.lat, stop.lon),
                    width: 44,
                    height: 44,
                    child: IconButton(tooltip: stop.name, onPressed: () => _openStop(stop), icon: const Icon(Icons.directions_bus_filled, size: 30)),
                  )),
            ]),
            RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) Positioned(left: 16, right: 16, bottom: 24, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))),
        if (!_loading && !widget.gtfs.hasData)
          const Positioned(left: 16, right: 16, bottom: 24, child: Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Base GTFS vazia. Gere os assets com tools/prepare_gtfs.py; veja o README.')))),
      ]),
    );
  }
}
