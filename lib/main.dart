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
    const seed = Color(0xFF087CCB);
    final light = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final dark = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Meu Ônibus',
      theme: ThemeData(
        colorScheme: light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: dark,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0, surfaceTintColor: Colors.transparent),
        cardTheme: CardThemeData(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: HomeMapScreen(gtfs: GtfsRepository(), api: OlhoVivoService(token: token)),
    );
  }
}
