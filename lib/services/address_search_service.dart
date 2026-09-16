import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressSearchException implements Exception {
  final String message;
  const AddressSearchException(this.message);
  @override
  String toString() => message;
}

class AddressResult {
  final String label;
  final double latitude;
  final double longitude;

  const AddressResult({required this.label, required this.latitude, required this.longitude});

  factory AddressResult.fromJson(Map<String, dynamic> json) => AddressResult(
        label: (json['display_name'] ?? 'Endereço').toString(),
        latitude: double.parse(json['lat'].toString()),
        longitude: double.parse(json['lon'].toString()),
      );
}

/// Pesquisa endereços no geocodificador público do OpenStreetMap.
/// A busca fica limitada ao município de São Paulo para evitar resultados
/// de outras cidades com nomes de rua semelhantes.
class AddressSearchService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org/search';
  final http.Client _client;

  AddressSearchService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<AddressResult>> search(String query) async {
    final text = query.trim();
    if (text.length < 3) return const [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'q': '$text, São Paulo, SP',
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '8',
      'countrycodes': 'br',
      // Limites aproximados do município de São Paulo: esquerda, topo, direita, baixo.
      'viewbox': '-46.826,-23.356,-46.365,-23.763',
      'bounded': '1',
    });

    final response = await _client.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'MeuOnibus/1.0 (https://github.com/lopeskuti/MeuOnibus)',
    });

    if (response.statusCode != 200) {
      throw AddressSearchException(
        'Não foi possível pesquisar o endereço agora (${response.statusCode}).',
      );
    }

    try {
      final data = jsonDecode(response.body) as List;
      return data
          .whereType<Map>()
          .map((item) => AddressResult.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on FormatException {
      throw const AddressSearchException('A busca de endereço retornou uma resposta inválida.');
    }
  }
}
