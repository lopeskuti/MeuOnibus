import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transit_models.dart';

/// The public itinerary data used by SPTrans's own line information page.
/// This endpoint is distinct from Olho Vivo and may change without notice.
class SptransTimetableService {
  static const _base = 'https://itinerariosapi.sptrans.com.br';
  final http.Client _client;
  Future<Map<String, int>>? _lines;
  final Map<String, Future<LineTimetable?>> _cache = {};

  SptransTimetableService({http.Client? client})
    : _client = client ?? http.Client();

  Future<Map<String, int>> _loadLines() async {
    final response = await _client
        .post(
          Uri.parse('$_base/RetornarLinhasTeste'),
          headers: _headers,
          body: '{}',
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200)
      throw Exception('Quadro horário indisponível (${response.statusCode}).');
    final lines = jsonDecode(response.body) as List;
    return {
      for (final raw in lines)
        if (raw is Map && raw['codigo'] is String && raw['CdPjOID'] is num)
          (raw['codigo'] as String).trim().toUpperCase():
              (raw['CdPjOID'] as num).toInt(),
    };
  }

  Future<LineTimetable?> forRoute(BusRoute route) =>
      _cache.putIfAbsent(route.shortName, () async {
        try {
          final lines = await (_lines ??= _loadLines());
          final code = lines[route.shortName.toUpperCase()];
          if (code == null) return null;
          final response = await _client
              .post(
                Uri.parse('$_base/BuscarDetalheLinhaTeste'),
                headers: _headers,
                body: jsonEncode({'codPlanejamento': code}),
              )
              .timeout(const Duration(seconds: 20));
          if (response.statusCode != 200)
            throw Exception(
              'Quadro horário indisponível (${response.statusCode}).',
            );
          final data = Map<String, dynamic>.from(
            jsonDecode(response.body) as Map,
          );
          if ((data['codigo'] ?? '').toString().toUpperCase() !=
              route.shortName.toUpperCase())
            return null;
          return LineTimetable.fromJson(data);
        } catch (_) {
          // Retry transient network failures when the line is opened again.
          _cache.remove(route.shortName);
          _lines = null;
          rethrow;
        }
      });

  static const _headers = {
    'Content-Type': 'application/json',
    'Origin': 'https://www.sptrans.com.br',
    'Referer': 'https://www.sptrans.com.br/itinerarios/linha/',
  };
}

class LineTimetable {
  final String outboundDestination;
  final String inboundDestination;
  final Map<int, List<int>> outbound;
  final Map<int, List<int>> inbound;

  const LineTimetable(
    this.outboundDestination,
    this.inboundDestination,
    this.outbound,
    this.inbound,
  );

  factory LineTimetable.fromJson(Map<String, dynamic> data) => LineTimetable(
    (data['letreiroIda'] ?? '').toString(),
    (data['letreiroVolta'] ?? '').toString(),
    _departures(data['partidasIda']),
    _departures(data['partidasVolta']),
  );

  static Map<int, List<int>> _departures(dynamic raw) {
    final result = <int, List<int>>{};
    if (raw is! List) return const {};
    for (final group in raw) {
      if (group is! Map ||
          group['tipoDia'] is! num ||
          group['horariosProgramados'] is! List)
        continue;
      final day = (group['tipoDia'] as num).toInt();
      if (day < 0 || day > 2) continue;
      for (final departure in group['horariosProgramados'] as List) {
        if (departure is! Map) continue;
        final time = parseTime((departure['horario'] ?? '').toString());
        if (time != null) {
          final times = result.putIfAbsent(day, () => []);
          // SPTrans lists departures in service order: 23:xx then 00:xx.
          // Preserve that order and mark the rollover as the next calendar day.
          final normalized = times.isNotEmpty && time < times.first % 1440
              ? time + 1440
              : time;
          if (!times.contains(normalized)) times.add(normalized);
        }
      }
    }
    return result.map((day, times) => MapEntry(day, times..sort()));
  }

  static int? parseTime(String time) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
    if (match == null) return null;
    final h = int.parse(match[1]!);
    final m = int.parse(match[2]!);
    if (h > 29 || m > 59) return null;
    return h * 60 + m;
  }

  static String formatTime(int minutes) =>
      '${(minutes ~/ 60) % 24}'.padLeft(2, '0') +
      ':${(minutes % 60).toString().padLeft(2, '0')}';

  Map<int, List<int>> forDirection(BusRoute route) {
    final target = _normalize(route.longName);
    final ida = _normalize(outboundDestination);
    final volta = _normalize(inboundDestination);
    if (target.isEmpty || (ida.isEmpty && volta.isEmpty)) return const {};
    final idaScore = _similarity(target, ida);
    final voltaScore = _similarity(target, volta);
    if (idaScore == voltaScore) return const {};
    return idaScore > voltaScore ? outbound : inbound;
  }

  static String _normalize(String input) {
    var s = input.toUpperCase();
    const from = 'ÁÀÂÃÉÈÊÍÌÎÓÒÔÕÚÙÛÇ';
    const to = 'AAAAEEEIIIOOOOUUUC';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s
        .replaceAll(RegExp(r'[^A-Z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _similarity(String a, String b) {
    if (a == b) return 1000;
    if (a.contains(b) || b.contains(a)) return 500;
    return a.split(' ').toSet().intersection(b.split(' ').toSet()).length;
  }

  RouteSchedule? scheduleFor(BusRoute route, DateTime date) {
    final byDay = forDirection(route);
    final day = date.weekday == DateTime.saturday
        ? 1
        : date.weekday == DateTime.sunday
        ? 2
        : 0;
    final departures = byDay[day];
    if (departures == null || departures.isEmpty) return null;
    final gaps = <int>[];
    for (var i = 1; i < departures.length; i++) {
      final gap = departures[i] - departures[i - 1];
      if (gap > 0 && gap <= 120) gaps.add(gap);
    }
    return RouteSchedule(
      operatingDays: operatingDaysFor(route),
      firstDeparture: formatTime(departures.first),
      lastDeparture: formatTime(departures.last),
      averageHeadwayMinutes: gaps.isEmpty
          ? null
          : (gaps.reduce((a, b) => a + b) / gaps.length).round(),
    );
  }

  String operatingDaysFor(BusRoute route) {
    final active = forDirection(route).entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => entry.key)
        .toSet();
    return _daysLabel(active);
  }

  static String _daysLabel(Set<int> active) => active.length == 3
      ? 'Todos os dias'
      : [
          if (active.contains(0)) 'Segunda a sexta',
          if (active.contains(1)) 'sábado',
          if (active.contains(2)) 'domingo',
        ].join(', ');

  String? nextTerminalDeparture(BusRoute route, DateTime now) {
    final byDay = forDirection(route);
    for (var offset = -1; offset <= 1; offset++) {
      final serviceDate = DateTime(now.year, now.month, now.day + offset);
      final day = serviceDate.weekday == DateTime.saturday
          ? 1
          : serviceDate.weekday == DateTime.sunday
          ? 2
          : 0;
      for (final departure in byDay[day] ?? const <int>[]) {
        final at = serviceDate.add(Duration(minutes: departure));
        if (!at.isBefore(now)) {
          return '${at.day == now.day ? 'Hoje' : 'Amanhã'} • ${formatTime(departure)}';
        }
      }
    }
    return null;
  }
}
