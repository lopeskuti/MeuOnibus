import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/transit_models.dart';

class OlhoVivoException implements Exception {
  final String message;
  OlhoVivoException(this.message);

  @override
  String toString() => message;
}

class OlhoVivoLine {
  final int code;
  final String number;
  final int direction;
  final String primaryTerminal;
  final String secondaryTerminal;

  const OlhoVivoLine({required this.code, required this.number, required this.direction, required this.primaryTerminal, required this.secondaryTerminal});

  String get destination => direction == 1 ? secondaryTerminal : primaryTerminal;

  factory OlhoVivoLine.fromJson(Map<String, dynamic> j) => OlhoVivoLine(
        code: (j['cl'] as num).toInt(),
        number: '${j['lt']}-${j['tl']}',
        direction: (j['sl'] as num).toInt(),
        primaryTerminal: (j['tp'] ?? '').toString(),
        secondaryTerminal: (j['ts'] ?? '').toString(),
      );
}

class OlhoVivoStop {
  final int code;
  final String name;
  final double lat;
  final double lon;
  const OlhoVivoStop({required this.code, required this.name, required this.lat, required this.lon});
  factory OlhoVivoStop.fromJson(Map<String, dynamic> json) => OlhoVivoStop(
        code: (json['cp'] as num).toInt(),
        name: (json['np'] ?? '').toString(),
        lat: (json['py'] as num).toDouble(),
        lon: (json['px'] as num).toDouble(),
      );
}

class ArrivalPrediction {
  final String prefix;
  final int minutes;
  final String expectedAt;
  final bool accessible;

  const ArrivalPrediction({required this.prefix, required this.minutes, required this.expectedAt, required this.accessible});
}

class OlhoVivoService {
  static const _baseUrl = 'https://api.olhovivo.sptrans.com.br/v2.1';
  final String token;
  final http.Client _client;
  bool _authenticated = false;
  String? _sessionCookie;

  OlhoVivoService({required this.token, http.Client? client}) : _client = client ?? http.Client();

  Future<void> _ensureAuthenticated() async {
    if (_authenticated && _sessionCookie != null) return;
    if (token.isEmpty) throw OlhoVivoException('Configure SPTRANS_TOKEN com --dart-define.');

    final uri = Uri.parse('$_baseUrl/Login/Autenticar').replace(queryParameters: {'token': token});
    final request = http.Request('POST', uri)
      ..headers['Content-Length'] = '0'
      ..body = '';
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200 || response.body.trim().toLowerCase() != 'true') {
      throw OlhoVivoException('Falha ao autenticar na API Olho Vivo (${response.statusCode}: ${response.body.trim()}).');
    }

    final setCookie = response.headers['set-cookie'];
    final cookie = setCookie?.split(';').first.trim();
    if (cookie == null || cookie.isEmpty) {
      throw OlhoVivoException('A API Olho Vivo autenticou, mas não retornou o cookie de sessão.');
    }
    _sessionCookie = cookie;
    _authenticated = true;
  }

  Future<http.Response> _get(Uri uri) async {
    await _ensureAuthenticated();
    var response = await _client.get(uri, headers: {'Cookie': _sessionCookie!});
    if (response.statusCode == 401) {
      _authenticated = false;
      _sessionCookie = null;
      await _ensureAuthenticated();
      response = await _client.get(uri, headers: {'Cookie': _sessionCookie!});
    }
    return response;
  }

  Future<List<OlhoVivoLine>> searchLines(String term) async {
    final uri = Uri.parse('$_baseUrl/Linha/Buscar').replace(queryParameters: {'termosBusca': term});
    final response = await _get(uri);
    if (response.statusCode != 200) throw OlhoVivoException('Erro ao buscar linha (${response.statusCode}).');
    return (jsonDecode(response.body) as List).map((e) => OlhoVivoLine.fromJson(Map<String, dynamic>.from(e))).toList(growable: false);
  }

  Future<int?> resolveLineCode(BusRoute route) async {
    final candidates = await searchLines(route.shortName.split('-').first);
    if (candidates.isEmpty) return null;
    final wantedNumber = _digits(route.shortName);
    final exact = candidates.where((candidate) => _digits(candidate.number) == wantedNumber).toList();
    final pool = exact.isEmpty ? candidates : exact;
    if (pool.length == 1) return pool.first.code;
    final target = _normalize(route.longName);
    pool.sort((a, b) => _score(target, _normalize(b.destination)).compareTo(_score(target, _normalize(a.destination))));
    return pool.first.code;
  }

  int _score(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.contains(b) || b.contains(a)) return 1000 + math.min(a.length, b.length);
    return a.split(' ').toSet().intersection(b.split(' ').toSet()).length * 10;
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
  String _normalize(String s) => s.toUpperCase().replaceAll(RegExp(r'[ÁÀÂÃ]'), 'A').replaceAll(RegExp(r'[ÉÈÊ]'), 'E').replaceAll(RegExp(r'[ÍÌÎ]'), 'I').replaceAll(RegExp(r'[ÓÒÔÕ]'), 'O').replaceAll(RegExp(r'[ÚÙÛ]'), 'U').replaceAll('Ç', 'C').replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<List<OlhoVivoStop>> stopsForLine(int lineCode) async {
    final uri = Uri.parse('$_baseUrl/Parada/BuscarParadasPorLinha').replace(queryParameters: {'codigoLinha': '$lineCode'});
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw OlhoVivoException('Erro ao localizar paradas da linha (${response.statusCode}).');
    }
    final data = jsonDecode(response.body);
    if (data is! List) return const [];
    return data.whereType<Map>().map((item) => OlhoVivoStop.fromJson(Map<String, dynamic>.from(item))).toList(growable: false);
  }

  Future<int?> resolveStopCode(int lineCode, BusStop stop) async {
    final stops = await stopsForLine(lineCode);
    if (stops.isEmpty) return null;

    // GTFS e Olho Vivo possuem cadastros independentes. A proximidade é o
    // critério principal: nomes de vias podem se repetir em bairros distintos.
    // A comparação de nome apenas desempata pontos próximos.
    const maxDistanceMeters = 550.0;
    final wantedName = _normalize(stop.name);
    OlhoVivoStop? best;
    var bestScore = -double.infinity;
    for (final candidate in stops) {
      final meters = _distanceMeters(stop.lat, stop.lon, candidate.lat, candidate.lon);
      if (meters > maxDistanceMeters) continue;
      final nameScore = _score(wantedName, _normalize(candidate.name));
      final score = -meters + math.min(nameScore * 20.0, 300.0);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best?.code;
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) * math.cos(_radians(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  Future<List<VehiclePosition>> vehicles(int lineCode) async {
    final uri = Uri.parse('$_baseUrl/Posicao/Linha').replace(queryParameters: {'codigoLinha': '$lineCode'});
    final response = await _get(uri);
    if (response.statusCode != 200) throw OlhoVivoException('Erro ao carregar veículos (${response.statusCode}).');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ((data['vs'] ?? const []) as List).map((e) => VehiclePosition.fromJson(Map<String, dynamic>.from(e))).toList(growable: false);
  }

  Future<List<ArrivalPrediction>> arrivals(int lineCode, String stopCode) async {
    if (int.tryParse(stopCode) == null) return const [];
    // A API não expõe previsão por meio de /Previsao genérico. Para uma
    // linha e um ponto específicos, o endpoint oficial é Previsao/Linha.
    final uri = Uri.parse('$_baseUrl/Previsao/Linha').replace(queryParameters: {
      'codigoParada': stopCode,
      'codigoLinha': '$lineCode',
    });
    final response = await _get(uri);
    if (response.statusCode != 200) throw OlhoVivoException('Erro ao carregar previsão (${response.statusCode}).');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final serverTime = (data['hr'] ?? '').toString();
    final point = data['p'];
    if (point is! Map) return const [];
    final lines = point['l'];
    if (lines is! List) return const [];

    final result = <ArrivalPrediction>[];
    for (final rawLine in lines) {
      if (rawLine is! Map) continue;
      final line = Map<String, dynamic>.from(rawLine);
      final code = (line['cl'] as num?)?.toInt();
      if (code != null && code != lineCode) continue;
      final vehicles = line['vs'];
      if (vehicles is! List) continue;
      for (final rawVehicle in vehicles) {
        if (rawVehicle is! Map) continue;
        final vehicle = Map<String, dynamic>.from(rawVehicle);
        final expectedAt = (vehicle['t'] ?? '').toString();
        final minutes = _minutesUntil(serverTime, expectedAt);
        if (minutes == null) continue;
        result.add(ArrivalPrediction(
          prefix: (vehicle['p'] ?? '').toString(),
          minutes: minutes,
          expectedAt: expectedAt,
          accessible: vehicle['a'] == true,
        ));
      }
    }
    result.sort((a, b) => a.minutes.compareTo(b.minutes));
    return result;
  }

  int? _minutesUntil(String current, String arrival) {
    int? parseMinutes(String value) {
      final parts = value.split(':');
      if (parts.length < 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      return hour * 60 + minute;
    }

    final now = parseMinutes(current);
    final eta = parseMinutes(arrival);
    if (eta == null) return null;
    final currentTime = DateTime.now();
    final base = now ?? (currentTime.hour * 60 + currentTime.minute);
    var diff = eta - base;
    if (diff < 0) diff += 24 * 60;
    return diff;
  }
}
