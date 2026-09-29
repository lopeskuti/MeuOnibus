import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:meu_onibus/models/transit_models.dart';
import 'package:meu_onibus/services/olho_vivo_service.dart';

class _SequenceClient extends http.BaseClient {
  _SequenceClient(this._responses);

  final List<http.Response> _responses;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  test('matches each Olho Vivo direction to its destination', () async {
    final client = _SequenceClient([
      http.Response(
        'true',
        200,
        headers: const {'set-cookie': 'session=ok; Path=/'},
      ),
      http.Response(
        '[{"cl":111,"lt":"748R","tl":10,"sl":1,"tp":"METRÔ BARRA FUNDA","ts":"JD. JOÃO XXIII"},{"cl":222,"lt":"748R","tl":10,"sl":2,"tp":"METRÔ BARRA FUNDA","ts":"JD. JOÃO XXIII"}]',
        200,
      ),
      http.Response(
        '[{"cl":111,"lt":"748R","tl":10,"sl":1,"tp":"METRÔ BARRA FUNDA","ts":"JD. JOÃO XXIII"},{"cl":222,"lt":"748R","tl":10,"sl":2,"tp":"METRÔ BARRA FUNDA","ts":"JD. JOÃO XXIII"}]',
        200,
      ),
    ]);
    final service = OlhoVivoService(token: 'test', client: client);
    expect(
      await service.resolveLineCode(
        const BusRoute(
          id: '748R-10:0',
          shortName: '748R-10',
          longName: 'Metrô Barra Funda',
        ),
      ),
      111,
    );
    expect(
      await service.resolveLineCode(
        const BusRoute(
          id: '748R-10:1',
          shortName: '748R-10',
          longName: 'Jd. João Xxiii',
        ),
      ),
      222,
    );
  });

  test('resolves the line stop and requests its prediction', () async {
    final client = _SequenceClient([
      http.Response(
        'true',
        200,
        headers: const {'set-cookie': 'session=ok; Path=/'},
      ),
      http.Response(
        '[{"cp":40012306,"np":"RIO DAS PEDRAS B/C","py":-23.568189,"px":-46.509633}]',
        200,
      ),
      http.Response(
        '{"hr":"14:30","p":{"cp":40012306,"l":[{"cl":123,"vs":[{"p":"12345","t":"14:34","a":true}]}]}}',
        200,
      ),
    ]);
    final service = OlhoVivoService(token: 'token-de-teste', client: client);
    const stop = BusStop(
      id: '40012306',
      name: 'Av. Rio Das Pedras, 1649',
      lat: -23.568189,
      lon: -46.509633,
    );

    final arrivals = await service.arrivals(123, stop);

    expect(arrivals, hasLength(1));
    expect(arrivals.single.prefix, '12345');
    expect(arrivals.single.minutes, 4);
    expect(client.requests, hasLength(3));
    expect(client.requests.last.url.path, '/v2.1/Previsao');
    expect(client.requests.last.url.queryParameters, {
      'codigoParada': '40012306',
      'codigoLinha': '123',
    });
  });
}
