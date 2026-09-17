import 'package:flutter/material.dart';
import 'screens/home_map_screen.dart';
import 'services/gtfs_repository.dart';
import 'services/olho_vivo_service.dart';
import 'services/rail_repository.dart';

void main() {
  const token = String.fromEnvironment('SPTRANS_TOKEN');
  runApp(MeuOnibusApp(token: token));
}

class MeuOnibusApp extends StatelessWidget {
  final String token;
  const MeuOnibusApp({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF0B82D4);
    const darkSurface = Color(0xFF101419);
    final light = ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.light);
    final dark = ColorScheme.fromSeed(seedColor: brand, brightness: Brightness.dark).copyWith(
      surface: darkSurface,
      surfaceContainer: const Color(0xFF1A2027),
      surfaceContainerHighest: const Color(0xFF252C35),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Meu Ônibus',
      theme: ThemeData(
        colorScheme: light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Color(0xFFF4F7FB),
        ),
        cardTheme: CardThemeData(
          elevation: 5,
          shadowColor: const Color(0x1A17212B),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: dark,
        useMaterial3: true,
        scaffoldBackgroundColor: darkSurface,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: darkSurface,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A2027),
          elevation: 8,
          shadowColor: Colors.black45,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      home: HomeMapScreen(gtfs: GtfsRepository(), rail: RailRepository(), api: OlhoVivoService(token: token)),
    );
  }
}
