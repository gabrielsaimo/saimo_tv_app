import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/channels_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/movie_favorites_provider.dart';
import 'providers/epg_provider.dart';
import 'providers/player_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/movies_provider.dart';
import 'providers/lazy_movies_provider.dart';  // Novo provider otimizado
import 'services/epg_service.dart';
import 'utils/memory_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configuração de tela cheia
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  // TRAVADO EM MODO PAISAGEM - App de TV não usa retrato
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // === OTIMIZAÇÃO DE MEMÓRIA PARA FIRE TV LITE ===
  // Limita o cache de imagens para evitar vazamento de memória
  PaintingBinding.instance.imageCache.maximumSize = 50; // Máximo 50 imagens em cache
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB máximo

  // Inicializa serviço EPG em background
  EpgService().initialize();

  // Inicia limpeza automática de cache (Fire TV)
  MemoryManager.startAutoCleanup();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..loadFavorites()),
        ChangeNotifierProvider(create: (_) => MovieFavoritesProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ChannelsProvider()),
        ChangeNotifierProvider(create: (_) => EpgProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => MoviesProvider()),
        // Provider otimizado para memória - usa JSONs paginados por categoria
        ChangeNotifierProvider(create: (_) => LazyMoviesProvider()),
      ],
      child: const SaimoTVApp(),
    ),
  );
}
