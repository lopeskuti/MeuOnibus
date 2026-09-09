import 'package:flutter/material.dart';
import 'screens/home_map_screen.dart';
import 'services/gtfs_repository.dart';
import 'services/olho_vivo_service.dart';

void main() {
  const token = String.fromEnvironment('SPTRANS_TOKEN');
  runApp(MeuOnibusApp(token: token));
}

class MeuOnibusApp extends StatelessWidget {
  final String token;
  const MeuOnibusApp({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Meu Ônibus',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true, brightness: Brightness.dark),
      home: HomeMapScreen(gtfs: GtfsRepository(), api: OlhoVivoService(token: token)),
    );
  }
}
