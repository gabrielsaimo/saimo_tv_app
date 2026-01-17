/// Script para converter arquivos M3U8 em JSONs divididos por categoria
/// Isso otimiza o carregamento para dispositivos com pouca memória (1GB RAM)
/// 
/// Como usar:
/// cd /Users/gabrielespindola/Documents/saimo_tv_app
/// dart run scripts/convert_m3u8_to_json.dart

import 'dart:convert';
import 'dart:io';

// Categorias que devem ser ignoradas (TV ao vivo, esportes, etc.)
const List<String> ignoredCategories = [
  '⏺️ ABERTO', '⏺️ BAND', '⏺️ SBT', '⏺️ GLOBO', '⏺️ RECORD', '⏺️ HBO',
  '⏺️ TELECINE', '⏺️ DISCOVERY', '⏺️ CINE SKY', '⏺️ FILMES E SERIES',
  '⏺️ NOTICIA', '⏺️ NBA', '⏺️ RUNTIME', '⏺️ 4K',
  'GLOBO (CENTRO-OESTE)', 'GLOBO (NORDESTE)', 'GLOBO (NORTE)',
  'GLOBO (SUDESTE)', 'GLOBO (SUL)',
  '⚽APPLETV', '⚽DAZN', '⚽DISNEY', '⚽ESPORTE', '⚽HBO',
  '⚽PARAMOUNT', '⚽PREMIERE', '⚽PRIME', '⚽ COPINHA',
  'A FAZENDA', 'BBB 20', 'BBB 2026', 'ESTRELA DA CASA',
  'Área do cliente', 'JOGOS DE HOJE', 'RÁDIOS FM', 'CANAIS:',
];

// Keywords adulto
const List<String> adultKeywords = [
  'ADULTOS', '[HOT]', 'XXX', '[Adulto]', 'ADULTO', '❌❤️',
];

// Keywords de série na categoria
const List<String> seriesCategoryKeywords = [
  'series', 'série', 'novelas', 'doramas', 'programas', 'stand up', '24h',
];

// Patterns de episódio
final List<RegExp> episodePatterns = [
  RegExp(r'S\d+\s*E\d+', caseSensitive: false),
  RegExp(r'T\d+\s*E\d+', caseSensitive: false),
  RegExp(r'\d+\s*x\s*\d+', caseSensitive: false),
  RegExp(r'Temporada\s*\d+', caseSensitive: false),
  RegExp(r'Temp\.?\s*\d+', caseSensitive: false),
  RegExp(r'Season\s*\d+', caseSensitive: false),
];

// Patterns de info de série
final List<RegExp> seriesInfoPatterns = [
  RegExp(r'^(.+?)\s*S(\d+)\s*E(\d+)', caseSensitive: false),
  RegExp(r'^(.+?)\s*T(\d+)\s*E(\d+)', caseSensitive: false),
  RegExp(r'^(.+?)\s*(\d+)\s*x\s*(\d+)', caseSensitive: false),
];

bool shouldIgnoreCategory(String category) {
  final upper = category.toUpperCase();
  return ignoredCategories.any((ignored) {
    final upperIgnored = ignored.toUpperCase();
    return upper.startsWith(upperIgnored) || upper == upperIgnored || category == ignored;
  });
}

bool isSeriesByCategory(String category) {
  final lower = category.toLowerCase();
  return seriesCategoryKeywords.any((keyword) => lower.contains(keyword));
}

bool isSeriesByName(String name) {
  return episodePatterns.any((pattern) => pattern.hasMatch(name));
}

bool isAdultContent(String name, String category) {
  final combined = '$name $category';
  return adultKeywords.any((keyword) => combined.contains(keyword));
}

({String baseName, int season, int episode})? parseSeriesInfo(String name) {
  for (final pattern in seriesInfoPatterns) {
    final match = pattern.firstMatch(name);
    if (match != null) {
      return (
        baseName: match.group(1)!.trim(),
        season: int.parse(match.group(2)!),
        episode: int.parse(match.group(3)!),
      );
    }
  }
  return null;
}

String cleanName(String name) {
  return name
      .replaceAll(RegExp(r'^\d+\s*[-–]\s*'), '')
      .replaceAll(RegExp(r'\s*\[L\]\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(DUB\)\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(LEG\)\s*', caseSensitive: false), '')
      .trim();
}

String generateId(String name, String url) {
  final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim().replaceAll(RegExp(r'\s+'), '-');
  final urlHash = url.hashCode.abs().toString();
  final hashPart = urlHash.length > 6 ? urlHash.substring(0, 6) : urlHash;
  return '$normalized-$hashPart';
}

String normalizeCategory(String category) {
  if (category.startsWith('OND /')) {
    var normalized = category.replaceFirst('OND /', '').trim();
    if (normalized.endsWith(' -')) {
      normalized = normalized.substring(0, normalized.length - 2).trim();
    }
    if (normalized.isNotEmpty) {
      normalized = normalized[0].toUpperCase() + normalized.substring(1);
    }
    return normalized.isEmpty ? 'Filmes' : normalized;
  }
  
  if (category.startsWith('Series |')) {
    final normalized = category.replaceFirst('Series |', '').trim();
    return normalized.isEmpty ? 'Séries' : normalized;
  }
  
  if (category.startsWith('COLETÂNEA:')) {
    return category.replaceFirst('COLETÂNEA:', '').trim();
  }
  
  final lower = category.toLowerCase();
  if (lower.contains('netflix')) return 'Netflix';
  if (lower.contains('prime video') || lower.contains('amazon prime')) return 'Prime Video';
  if (lower.contains('disney')) return 'Disney+';
  if (lower.contains('max') && !lower.contains('mad max')) return 'Max';
  if (lower.contains('hbo')) return 'Max';
  if (lower.contains('globoplay')) return 'Globoplay';
  if (lower.contains('paramount')) return 'Paramount+';
  if (lower.contains('apple')) return 'Apple TV+';
  if (lower.contains('novela')) return 'Novelas';
  if (lower.contains('dorama')) return 'Doramas';
  if (lower.contains('anime') || lower.contains('crunchyroll')) return 'Animes';
  if (lower.contains('programas de tv')) return 'Programas de TV';
  
  return category;
}

/// Gera um slug seguro para nome de arquivo
String categoryToFilename(String category) {
  return category
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

void main() async {
  final stopwatch = Stopwatch()..start();
  
  print('🎬 Iniciando conversão de M3U8 para JSONs por categoria...\n');
  
  // Diretórios
  final assetsDir = Directory('assets');
  final outputDir = Directory('assets/catalog');
  
  // Cria diretório de saída
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }
  
  // Lista de arquivos M3U8
  final m3u8Files = [
    File('${assetsDir.path}/ListaBR01.m3u8'),
    File('${assetsDir.path}/ListaBR02.m3u8'),
  ];
  
  // Mapa de filmes/séries por categoria
  final Map<String, List<Map<String, dynamic>>> byCategory = {};
  final Set<String> seenUrls = {};
  
  int totalParsed = 0;
  int totalSkipped = 0;
  int totalDuplicates = 0;
  
  for (final file in m3u8Files) {
    if (!await file.exists()) {
      print('⚠️ Arquivo não encontrado: ${file.path}');
      continue;
    }
    
    print('📖 Lendo: ${file.path}');
    final content = await file.readAsString();
    final lines = content.split('\n');
    
    String? currentName;
    String? currentCategory;
    String? currentLogo;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (line.startsWith('#EXTINF:')) {
        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        currentCategory = groupMatch?.group(1) ?? 'Outros';
        
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        currentLogo = logoMatch?.group(1);
        
        final nameMatch = RegExp(r',(.+)$').firstMatch(line);
        currentName = nameMatch?.group(1)?.trim();
      } else if (line.startsWith('http') && currentName != null) {
        final url = line;
        
        // Ignora .ts (streams ao vivo)
        if (url.toLowerCase().endsWith('.ts')) {
          currentName = null;
          currentCategory = null;
          currentLogo = null;
          totalSkipped++;
          continue;
        }
        
        final category = currentCategory ?? 'Outros';
        
        // Ignora categorias bloqueadas
        if (shouldIgnoreCategory(category)) {
          currentName = null;
          currentCategory = null;
          currentLogo = null;
          totalSkipped++;
          continue;
        }
        
        // Verifica duplicatas
        if (seenUrls.contains(url)) {
          currentName = null;
          currentCategory = null;
          currentLogo = null;
          totalDuplicates++;
          continue;
        }
        seenUrls.add(url);
        
        final cleanedName = cleanName(currentName);
        final isAdult = isAdultContent(currentName, category);
        final isSeries = isSeriesByCategory(category) || isSeriesByName(currentName);
        final seriesInfo = parseSeriesInfo(currentName);
        final type = (isSeries || seriesInfo != null) ? 'series' : 'movie';
        final normalizedCategory = normalizeCategory(category);
        
        // Cria objeto do filme/episódio
        final movie = <String, dynamic>{
          'id': generateId(cleanedName, url),
          'name': cleanedName,
          'url': url,
          if (currentLogo != null && currentLogo.isNotEmpty) 'logo': currentLogo,
          'type': type,
          if (isAdult) 'isAdult': true,
          if (seriesInfo != null) ...{
            'seriesName': seriesInfo.baseName,
            'season': seriesInfo.season,
            'episode': seriesInfo.episode,
          },
        };
        
        // Adiciona à categoria
        byCategory.putIfAbsent(normalizedCategory, () => []).add(movie);
        totalParsed++;
        
        currentName = null;
        currentCategory = null;
        currentLogo = null;
      }
    }
  }
  
  print('\n📊 Estatísticas de parsing:');
  print('   ✅ Itens válidos: $totalParsed');
  print('   ⏭️ Itens ignorados: $totalSkipped');
  print('   🔄 Duplicatas removidas: $totalDuplicates');
  print('   📁 Categorias: ${byCategory.length}\n');
  
  // Gera índice e arquivos por categoria
  final categoryIndex = <Map<String, dynamic>>[];
  int totalSavedItems = 0;
  
  for (final entry in byCategory.entries) {
    final category = entry.key;
    final items = entry.value;
    final filename = categoryToFilename(category);
    
    // Separa filmes, séries e adulto
    final movies = items.where((m) => m['type'] == 'movie' && m['isAdult'] != true).toList();
    final series = items.where((m) => m['type'] == 'series' && m['isAdult'] != true).toList();
    final adult = items.where((m) => m['isAdult'] == true).toList();
    
    // Conta totais
    final totalItems = movies.length + series.length + adult.length;
    totalSavedItems += totalItems;
    
    // Adiciona ao índice
    categoryIndex.add({
      'id': filename,
      'name': category,
      'movieCount': movies.length,
      'seriesCount': series.length,
      'adultCount': adult.length,
      'totalCount': totalItems,
    });
    
    // Salva arquivo da categoria (compacto, sem adulto)
    final categoryData = {
      'category': category,
      'movies': movies,
      'series': series,
    };
    
    final categoryFile = File('${outputDir.path}/$filename.json');
    await categoryFile.writeAsString(jsonEncode(categoryData));
    
    print('   📄 $filename.json: ${movies.length} filmes, ${series.length} séries');
    
    // Salva conteúdo adulto separadamente (se houver)
    if (adult.isNotEmpty) {
      final adultData = {
        'category': category,
        'items': adult,
      };
      final adultFile = File('${outputDir.path}/${filename}_adult.json');
      await adultFile.writeAsString(jsonEncode(adultData));
      print('   🔞 ${filename}_adult.json: ${adult.length} itens');
    }
  }
  
  // Ordena índice por quantidade
  categoryIndex.sort((a, b) => (b['totalCount'] as int).compareTo(a['totalCount'] as int));
  
  // Gera arquivo de índice principal
  final indexData = {
    'version': 1,
    'generatedAt': DateTime.now().toIso8601String(),
    'totalMovies': categoryIndex.fold<int>(0, (sum, c) => sum + (c['movieCount'] as int)),
    'totalSeries': categoryIndex.fold<int>(0, (sum, c) => sum + (c['seriesCount'] as int)),
    'totalAdult': categoryIndex.fold<int>(0, (sum, c) => sum + (c['adultCount'] as int)),
    'categories': categoryIndex,
  };
  
  final indexFile = File('${outputDir.path}/index.json');
  await indexFile.writeAsString(const JsonEncoder.withIndent('  ').convert(indexData));
  
  stopwatch.stop();
  
  print('\n✅ Conversão concluída!');
  print('   📁 Arquivos salvos em: ${outputDir.path}/');
  print('   📊 Total de categorias: ${categoryIndex.length}');
  print('   🎬 Total de itens: $totalSavedItems');
  print('   ⏱️ Tempo: ${stopwatch.elapsedMilliseconds}ms');
  
  // Calcula tamanho total
  final files = await outputDir.list().where((f) => f.path.endsWith('.json')).toList();
  int totalSize = 0;
  for (final f in files) {
    if (f is File) {
      totalSize += await f.length();
    }
  }
  print('   💾 Tamanho total: ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB');
}
