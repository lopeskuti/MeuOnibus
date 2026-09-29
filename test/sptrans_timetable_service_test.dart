import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:meu_onibus/models/transit_models.dart';
import 'package:meu_onibus/services/sptrans_timetable_service.dart';

class _Client extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = request.url.path.endsWith('RetornarLinhasTeste')
        ? '[{"codigo":"748R-10","CdPjOID":234917}]'
        : '''{"codigo":"748R-10","letreiroIda":"METRÔ BARRA FUNDA","letreiroVolta":"JD. JOÃO XXIII",
            "partidasIda":[{"tipoDia":0,"horariosProgramados":[{"horario":"04:00"},{"horario":"04:12"}]},
                           {"tipoDia":1,"horariosProgramados":[{"horario":"04:00"},{"horario":"23:40"},{"horario":"00:30"}]}],
            "partidasVolta":[{"tipoDia":0,"horariosProgramados":[{"horario":"05:10"},{"horario":"05:32"}]}]}''';
    return http.StreamedResponse(Stream.value(body.codeUnits), 200);
  }
}

void main() {
  test(
    'uses the official timetable for each direction and preserves next-day last departure',
    () async {
      final client = _Client();
      final service = SptransTimetableService(client: client);
      const barraFunda = BusRoute(
        id: '748R-10:0',
        shortName: '748R-10',
        longName: 'Metrô Barra Funda',
      );
      const joao = BusRoute(
        id: '748R-10:1',
        shortName: '748R-10',
        longName: 'Jd. João Xxiii',
      );
      final timetable = await service.forRoute(barraFunda);
      final weekday = timetable!.scheduleFor(barraFunda, DateTime(2026, 9, 28));
      final saturday = timetable.scheduleFor(barraFunda, DateTime(2026, 10, 3));
      final reverse = timetable.scheduleFor(joao, DateTime(2026, 9, 28));
      expect(weekday!.firstDeparture, '04:00');
      expect(weekday.lastDeparture, '04:12');
      expect(saturday!.lastDeparture, '00:30');
      expect(timetable.forDirection(barraFunda)[1]!.last, 1470);
      expect(reverse!.firstDeparture, '05:10');
      expect(reverse.lastDeparture, '05:32');
      expect(client.requests, hasLength(2));
      expect(client.requests.last.method, 'POST');
    },
  );
}
