import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/channels_screen.dart';
import 'screens/player_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/search_screen.dart';
import 'screens/home_selector_screen.dart';
import 'screens/movies_catalog_screen.dart';
import 'screens/optimized_catalog_screen.dart';
import 'screens/catalog_screen_lite.dart';
import 'screens/movie_player_screen.dart';
import 'providers/settings_provider.dart';
import 'utils/theme.dart';

class SaimoTVApp extends StatelessWidget {
  const SaimoTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Saimo TV',
          debugShowCheckedModeBanner: false,
          theme: SaimoTheme.darkTheme,
          darkTheme: SaimoTheme.darkTheme,
          themeMode: ThemeMode.dark,
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(),
            '/selector': (context) => const HomeSelectorScreen(),
            '/channels': (context) => const ChannelsScreen(), // Tela de canais premium
            '/player': (context) => const PlayerScreen(),
            '/guide': (context) => const GuideScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/search': (context) => const SearchScreen(),
            '/movies': (context) => const CatalogScreenLite(), // Versão ultra otimizada para Fire TV Lite
            '/movies-old': (context) => const OptimizedCatalogScreen(), // Versão anterior
            '/movies-legacy': (context) => const MoviesCatalogScreen(), // Versão antiga (backup)
            '/movie-player': (context) => const MoviePlayerScreen(),
          },
          builder: (context, child) {
            // Mantém o texto com tamanho fixo para evitar escala automática
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: child!,
            );
          },
        );
      },
    );
  }
}
