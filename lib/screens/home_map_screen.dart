import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/transit_models.dart';
import '../services/address_search_service.dart';
import '../services/gtfs_repository.dart';
import '../services/location_service.dart';
import '../services/olho_vivo_service.dart';
import '../services/rail_repository.dart';
import 'route_map_screen.dart';

class HomeMapScreen extends StatefulWidget {
  final GtfsRepository gtfs;
  final RailRepository rail;
  final OlhoVivoService api;
  const HomeMapScreen({super.key, required this.gtfs, required this.rail, required this.api});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final _map = MapController();
  final _location = LocationService();
  final _addressSearch = AddressSearchService();
  StreamSubscription<Position>? _locationSubscription;
  Timer? _mapMoveDebounce;
  LatLng? _me;
  LatLng? _nearbyCenter;
  LatLng? _addressLocation;
  String? _addressLabel;
  List<BusStop> _nearby = const [];
  List<BusTerminal> _nearbyTerminals = const [];
  List<RailStation> _nearbyRail = const [];
  String? _error;
  bool _loading = true;
  bool _hasCenteredOnLocation = false;
  bool _userHasInteractedWithMap = false;

  static const _followZoom = 17.4;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.gtfs.load();
      await widget.rail.load();
      final p = await _location.current();
      _applyLocation(p, moveMap: true);
      await _locationSubscription?.cancel();
      final stream = await _location.foregroundPositions();
      _locationSubscription = stream.listen(
        (position) => _applyLocation(position, moveMap: true),
        onError: (Object e) {
          if (mounted) setState(() => _error = e.toString());
        },
      );
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _recenterOnMyLocation() async {
    try {
      final position = await _location.current();
      _applyLocation(position, moveMap: false);
      if (!mounted) return;
      final me = LatLng(position.latitude, position.longitude);
      _map.move(me, _followZoom);
      _loadStopsAround(me);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _applyLocation(Position p, {required bool moveMap}) {
    final me = LatLng(p.latitude, p.longitude);
    final stops = widget.gtfs.nearby(p.latitude, p.longitude, radiusMeters: 1200);
    final terminals = widget.gtfs.terminalsNearby(p.latitude, p.longitude, radiusMeters: 1200);
    final rail = widget.rail.nearby(p.latitude, p.longitude, radiusMeters: 1200);
    if (!mounted) return;
    setState(() {
      _me = me;
      if (_nearbyCenter == null) {
        _nearbyCenter = me;
        _nearby = stops.where((stop) => !widget.gtfs.isTerminalStop(stop)).toList(growable: false);
        _nearbyTerminals = terminals;
        _nearbyRail = rail;
      }
    });
    // A câmera é posicionada somente uma vez, na abertura da tela.
    // Depois disso, inclusive após qualquer gesto manual, somente o cursor muda.
    if (moveMap && !_hasCenteredOnLocation && !_userHasInteractedWithMap) {
      _hasCenteredOnLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_userHasInteractedWithMap) _map.move(me, _followZoom);
      });
    }
  }

  void _loadStopsAround(LatLng center) {
    final stops = widget.gtfs.nearby(center.latitude, center.longitude, radiusMeters: 1200);
    final terminals = widget.gtfs.terminalsNearby(center.latitude, center.longitude, radiusMeters: 1200);
    final rail = widget.rail.nearby(center.latitude, center.longitude, radiusMeters: 1200);
    if (!mounted) return;
    setState(() {
      _nearbyCenter = center;
      _nearby = stops.where((stop) => !widget.gtfs.isTerminalStop(stop)).toList(growable: false);
      _nearbyTerminals = terminals;
      _nearbyRail = rail;
      _addressLocation = null;
      _addressLabel = null;
    });
  }

  String _distanceLabel(BusStop stop) {
    final reference = _nearbyCenter ?? _me;
    if (reference == null) return '';
    const distance = Distance();
    final meters = distance(reference, LatLng(stop.lat, stop.lon)).round();
    return meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _openRoute(BusRoute route) async {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => RouteMapScreen(
      route: route,
      initialLocation: _me,
      gtfs: widget.gtfs,
      api: widget.api,
    )));
  }

  Future<void> _openRouteSearch() async {
    final controller = TextEditingController();
    var results = const <BusRoute>[];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .74,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Buscar linha', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Pesquise pelo número ou pelo nome do destino.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Ex.: 748R ou Barra Funda',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) => setSheetState(() => results = widget.gtfs.searchRoutes(query)),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: controller.text.trim().isEmpty
                      ? const Center(child: Text('Digite uma linha ou destino para pesquisar.'))
                      : results.isEmpty
                          ? const Center(child: Text('Nenhuma linha encontrada.'))
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                              itemBuilder: (_, index) {
                                final route = results[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 5),
                                  leading: Container(
                                    width: 52,
                                    height: 42,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0B82D4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(route.shortName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                  ),
                                  title: Text(route.longName.isEmpty ? route.shortName : route.longName, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  subtitle: const Text('Ver trajeto e ônibus em tempo real'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    _openRoute(route);
                                  },
                                );
                              },
                            ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _openAddressSearch() async {
    final controller = TextEditingController();
    var results = const <AddressResult>[];
    var loading = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .74,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Buscar endereço', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Veja os pontos e as linhas próximos de qualquer endereço em São Paulo.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Rua, número, bairro ou CEP',
                    prefixIcon: Icon(Icons.location_searching_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) async {
                    final query = controller.text.trim();
                    if (query.length < 3) {
                      setSheetState(() => error = 'Digite pelo menos 3 caracteres.');
                      return;
                    }

                    setSheetState(() {
                      loading = true;
                      error = null;
                      results = const [];
                    });
                    try {
                      final found = await _addressSearch.search(query);
                      if (sheetContext.mounted) {
                        setSheetState(() => results = found);
                      }
                    } catch (e) {
                      if (sheetContext.mounted) {
                        setSheetState(() => error = e.toString());
                      }
                    } finally {
                      if (sheetContext.mounted) {
                        setSheetState(() => loading = false);
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? Center(child: Text(error!, textAlign: TextAlign.center))
                          : results.isEmpty
                              ? const Center(child: Text('Digite o endereço e toque em Buscar no teclado.'))
                              : ListView.separated(
                                  itemCount: results.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                                  itemBuilder: (_, index) {
                                    final result = results[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                                      leading: const CircleAvatar(child: Icon(Icons.location_on_rounded)),
                                      title: Text(result.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      subtitle: const Text('Ver pontos e linhas próximos'),
                                      trailing: const Icon(Icons.chevron_right_rounded),
                                      onTap: () {
                                        final location = LatLng(result.latitude, result.longitude);
                                        final stops = widget.gtfs.nearby(
                                          result.latitude,
                                          result.longitude,
                                          radiusMeters: 1200,
                                        );
                                        final terminals = widget.gtfs.terminalsNearby(
                                          result.latitude,
                                          result.longitude,
                                          radiusMeters: 1200,
                                        );
                                        final rail = widget.rail.nearby(
                                          result.latitude,
                                          result.longitude,
                                          radiusMeters: 1200,
                                        );
                                        Navigator.pop(sheetContext);
                                        if (!mounted) return;
                                        setState(() {
                                          _addressLocation = location;
                                          _addressLabel = result.label;
                                          _nearbyCenter = location;
                                          _nearby = stops.where((stop) => !widget.gtfs.isTerminalStop(stop)).toList(growable: false);
                                          _nearbyTerminals = terminals;
                                          _nearbyRail = rail;
                                        });
                                        _map.move(location, 16.5);
                                      },
                                    );
                                  },
                                ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _openTerminal(BusTerminal terminal) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .76,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(terminal.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${terminal.platforms.length} plataforma(s)', style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: terminal.platforms.length,
                itemBuilder: (_, index) {
                  final platform = terminal.platforms[index];
                  final routes = widget.gtfs.routesForPlatform(platform);
                  return ExpansionTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(platform.name),
                    subtitle: Text('${routes.length} linha(s)'),
                    children: routes.map((route) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      leading: Container(
                        width: 52, height: 40, alignment: Alignment.center,
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                        child: Text(route.shortName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      title: Text(route.longName.isEmpty ? route.shortName : route.longName, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        final stop = widget.gtfs.stopForRoute(platform, route);
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RouteMapScreen(route: route, stop: stop, initialLocation: _me, gtfs: widget.gtfs, api: widget.api)));
                      },
                    )).toList(growable: false),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
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
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RouteMapScreen(
                          route: route,
                          stop: stop,
                          initialLocation: _me,
                          gtfs: widget.gtfs,
                          api: widget.api,
                        )));
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

  Future<void> _openRailStation(RailStation station) async {
    final lines = widget.rail.linesFor(station);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(station.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Metrô e trem • dados estáticos'),
            const SizedBox(height: 14),
            ...lines.map((line) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: Color(line.color), child: const Icon(Icons.train_rounded, color: Colors.white)),
              title: Text(line.name),
              subtitle: Text(line.mode == 'metro' ? 'Metrô' : 'Trem metropolitano'),
            )),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Previsão em tempo real ainda não é disponibilizada por uma fonte pública integrada.', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _railMarker(RailStation station) => GestureDetector(
    onTap: () => _openRailStation(station),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF5A3D92),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(blurRadius: 5, offset: Offset(0, 2), color: Colors.black26)],
      ),
      child: const Icon(Icons.train_rounded, color: Colors.white, size: 15),
    ),
  );

  Widget _terminalMarker(BusTerminal terminal) => GestureDetector(
    onTap: () => _openTerminal(terminal),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF075D9E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 5, offset: Offset(0, 2), color: Colors.black26)],
      ),
      child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 23),
    ),
  );

  Widget _stopMarker(BusStop stop) => GestureDetector(
    onTap: () => _openStop(stop),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B82D4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(blurRadius: 5, offset: Offset(0, 2), color: Colors.black26)],
      ),
      child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 14),
    ),
  );

  Widget _addressMarker() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFE5252A),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
    ),
    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
  );

  Widget _locationMarker() => Stack(alignment: Alignment.center, children: [
    Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0x380B82D4), shape: BoxShape.circle)),
    Container(width: 19, height: 19, decoration: BoxDecoration(color: const Color(0xFF0B82D4), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38)])),
  ]);

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapMoveDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _me ?? const LatLng(-23.55052, -46.633308);
    final visibleTerminals = _nearbyTerminals.take(2).toList(growable: false);
    final visibleStops = _nearby.take(3 - visibleTerminals.length).toList(growable: false);
    final nearbyRailLineIds = _nearbyRail.expand((station) => station.lineIds).toSet();
    final nearbyRailLines = nearbyRailLineIds.map((lineId) => widget.rail.lineForId(lineId)).whereType<RailLine>().toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 84,
        titleSpacing: 20,
        title: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF0B82D4),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [BoxShadow(color: Color(0x330B82D4), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: const Icon(Icons.directions_bus_filled_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Meu Ônibus', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('Sua localização acompanha o mapa em tempo real', style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
        actions: [
          IconButton.filledTonal(
            onPressed: _loading ? null : _openAddressSearch,
            tooltip: 'Buscar endereço',
            icon: const Icon(Icons.location_searching_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: _loading ? null : _openRouteSearch,
            tooltip: 'Buscar linha',
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: _loading ? null : _recenterOnMyLocation,
            tooltip: 'Voltar para minha localização',
            icon: const Icon(Icons.my_location_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: initial,
            initialZoom: _followZoom,
            minZoom: 10,
            maxZoom: 19,
            onPositionChanged: (camera, hasGesture) {
              if (!hasGesture) return;
              _userHasInteractedWithMap = true;
              _mapMoveDebounce?.cancel();
              _mapMoveDebounce = Timer(const Duration(milliseconds: 250), () => _loadStopsAround(camera.center));
            },
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'br.com.lopeskuti.meuonibus'),
            if (nearbyRailLines.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final line in nearbyRailLines)
                    for (final path in line.paths) ...[
                      Polyline(points: path, strokeWidth: 6, color: const Color(0xFFFFFFFF)),
                      Polyline(points: path, strokeWidth: 3.5, color: Color(line.color)),
                    ],
                ],
              ),
            MarkerLayer(markers: [
              if (_addressLocation != null) Marker(point: _addressLocation!, width: 42, height: 42, child: _addressMarker()),
              if (_me != null) Marker(point: _me!, width: 46, height: 46, child: _locationMarker()),
              ..._nearbyTerminals.map((terminal) => Marker(point: LatLng(terminal.lat, terminal.lon), width: 42, height: 42, child: _terminalMarker(terminal))),
              ..._nearby.map((stop) => Marker(point: LatLng(stop.lat, stop.lon), width: 26, height: 26, child: _stopMarker(stop))),
              ..._nearbyRail.map((station) => Marker(point: LatLng(station.lat, station.lon), width: 28, height: 28, child: _railMarker(station))),
            ]),
            RichAttributionWidget(attributions: const [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        if (!_loading && (visibleTerminals.isNotEmpty || visibleStops.isNotEmpty))
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Text(_addressLabel == null ? 'Pontos próximos' : 'Pontos perto do endereço', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${_nearby.length + _nearbyTerminals.length} encontrados', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  if (_addressLabel != null) ...[
                    const SizedBox(height: 3),
                    Text(_addressLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 6),
                  ...visibleTerminals.map((terminal) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(radius: 20, child: Icon(Icons.directions_bus_rounded, size: 19)),
                    title: Text(terminal.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${terminal.platforms.length} plataforma(s)'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openTerminal(terminal),
                  )),
                  ...visibleStops.map((stop) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(radius: 20, child: Icon(Icons.directions_bus_filled_rounded, size: 19)),
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
