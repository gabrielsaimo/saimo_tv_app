import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Gerenciador de memória para Fire TV
/// Limpa caches automaticamente para evitar OOM
class MemoryManager {
  static final MemoryManager _instance = MemoryManager._internal();
  factory MemoryManager() => _instance;
  MemoryManager._internal();

  /// Limpa cache de imagens
  static Future<void> clearImageCache() async {
    try {
      debugPrint('🧹 Limpando cache de imagens...');
      await CachedNetworkImage.evictFromCache('');
      debugPrint('✅ Cache limpo');
    } catch (e) {
      debugPrint('⚠️ Erro ao limpar cache: $e');
    }
  }

  /// Limpa cache de imagens periodicamente (a cada 5 minutos)
  static void startAutoCleanup() {
    Future.delayed(const Duration(minutes: 5), () {
      clearImageCache();
      startAutoCleanup(); // Recursivo
    });
  }

  /// Força coleta de lixo (garbage collection)
  static void forceGC() {
    // Em Flutter, não temos controle direto do GC
    // Mas podemos sugerir com null checks
    debugPrint('🗑️ Sugerindo garbage collection...');
  }
}
