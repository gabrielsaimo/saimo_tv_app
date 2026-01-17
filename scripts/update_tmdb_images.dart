#!/usr/bin/env dart
/// Script TURBO para atualização de TODAS as imagens para TMDB
/// Processamento em batches de 10.000 itens
/// Pula conteúdo adulto e episódios de séries (só atualiza capa da série)
///
/// Execute com: dart run scripts/update_tmdb_images.dart

import 'dart:convert';
import 'dart:io';

// Configurações do TMDB
const String TMDB_API_KEY = '15d2ea6d0dc1d476efbca3eba2b9bbfb';
const String TMDB_IMAGE_BASE = 'https://image.tmdb.org/t/p/w780';

// Configuração de processamento ULTRA TURBO
const int BATCH_SIZE = 10000; // Itens por batch
const int CONCURRENT_REQUESTS = 100; // Requisições simultâneas (aumentado!)
const int DELAY_BETWEEN_BATCHES_MS = 100; // ms entre batches (reduzido!)

// Arquivo para começar (deixe vazio para processar todos)
const String START_FROM_FILE = 'outros.json';

// Palavras-chave para detectar conteúdo adulto
const List<String> ADULT_KEYWORDS = [
  'adulto',
  'adult',
  'xxx',
  'hot',
  '18+',
  'erotic',
  'erotico',
  'porn',
  'sex',
];

// Cache para séries (evitar buscas duplicadas)
final Map<String, String?> seriesCache = {};

// Estatísticas
int totalProcessed = 0;
int updated = 0;
int notFound = 0;
int skippedAdult = 0;
int skippedEpisode = 0;
int cached = 0;
int errors = 0;

void main() async {
  print('\x1B[2J\x1B[H'); // Limpa tela
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║  🚀 ULTRA TURBO UPDATE - TMDB Images                         ║');
  print('║  ⚡ $CONCURRENT_REQUESTS requisições simultâneas | Delay: ${DELAY_BETWEEN_BATCHES_MS}ms          ║');
  print('╚══════════════════════════════════════════════════════════════╝\n');

  final catalogDir = Directory('assets/catalog');
  if (!catalogDir.existsSync()) {
    print('❌ Diretório assets/catalog não encontrado!');
    exit(1);
  }

  var files = catalogDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .where((f) => !f.path.contains('index.json'))
      .toList();

  files.sort((a, b) => a.path.compareTo(b.path)); // Ordem alfabética

  // Começa do arquivo específico se definido
  if (START_FROM_FILE.isNotEmpty) {
    final startIndex = files.indexWhere((f) => f.path.endsWith(START_FROM_FILE));
    if (startIndex > 0) {
      files = files.sublist(startIndex);
      print('⏭️  Continuando a partir de: $START_FROM_FILE');
    }
  }

  print('📂 ${files.length} arquivos JSON para processar\n');

  final startTime = DateTime.now();
  int fileIndex = 0;

  for (final file in files) {
    fileIndex++;
    await processFile(file, fileIndex, files.length);
  }

  final duration = DateTime.now().difference(startTime);

  print('\n==========================================');
  print('📊 ESTATÍSTICAS FINAIS');
  print('==========================================');
  print('Total processado: $totalProcessed');
  print('✅ Atualizados: $updated');
  print('📦 Cache hits: $cached');
  print('❌ Não encontrados: $notFound');
  print('🔞 Pulados (adulto): $skippedAdult');
  print('📺 Pulados (episódios): $skippedEpisode');
  print('⚠️ Erros: $errors');
  print('⏱️ Tempo: ${duration.inMinutes}m ${duration.inSeconds % 60}s');
  print('==========================================\n');
}

Future<void> processFile(File file, int fileIndex, int totalFiles) async {
  final fileName = file.path.split('/').last;

  // Pula arquivos de adulto
  if (isAdultFile(fileName)) {
    print('🔞 [$fileIndex/$totalFiles] Pulando adulto: $fileName');
    return;
  }

  print('\\n╔════════════════════════════════════════════════════════════════╗');
  print('║ 📁 [$fileIndex/$totalFiles] $fileName');
  print('╚════════════════════════════════════════════════════════════════╝');

  try {
    final content = file.readAsStringSync();
    final dynamic jsonData = json.decode(content);

    List<dynamic> items;
    bool isNewFormat = false;

    List<dynamic> seriesItems = [];

    // Detecta formato do JSON
    if (jsonData is Map) {
      if (jsonData.containsKey('movies') || jsonData.containsKey('series')) {
        items = List<dynamic>.from(jsonData['movies'] ?? []);
        seriesItems = List<dynamic>.from(jsonData['series'] ?? []);
        isNewFormat = true;
      } else {
        print('  ⚠️ Formato não reconhecido, pulando...');
        return;
      }
    } else if (jsonData is List) {
      items = List<dynamic>.from(jsonData);
    } else {
      print('  ⚠️ Formato não reconhecido, pulando...');
      return;
    }

    final allItems = [...items, ...seriesItems];
    print('  📊 Total: ${allItems.length} itens (${items.length} filmes, ${seriesItems.length} séries)');

    bool fileUpdated = false;
    int fileUpdatedCount = 0;
    int fileSkippedCount = 0;
    
    // Processa em batches
    for (int i = 0; i < allItems.length; i += BATCH_SIZE) {
      final batchEnd = (i + BATCH_SIZE < allItems.length) ? i + BATCH_SIZE : allItems.length;
      final batch = allItems.sublist(i, batchEnd);

      print('  🔄 Processando batch ${i ~/ BATCH_SIZE + 1} (${batch.length} itens)...');

      // Processa batch com concorrência controlada
      final results = await processBatch(batch, fileName);

      for (int j = 0; j < results.length; j++) {
        final result = results[j];
        final itemIndex = i + j;

        if (result['skipped'] == true) {
          fileSkippedCount++;
          continue;
        }

        if (result['imageUrl'] != null) {
          // Sempre atualiza a imagem, mesmo que já tenha uma
          allItems[itemIndex]['logo'] = result['imageUrl'];
          fileUpdated = true;
          fileUpdatedCount++;
        }
      }

      // Progresso detalhado
      final progress = batchEnd;
      final percent = (progress / allItems.length * 100).round();
      final bar = '█' * (percent ~/ 5) + '░' * (20 - percent ~/ 5);
      stdout.write('\\r  [$bar] $percent% | ✅ $fileUpdatedCount | ⏭️ $fileSkippedCount | Total: $progress/${allItems.length}');

      // Delay entre batches
      if (batchEnd < allItems.length) {
        await Future.delayed(Duration(milliseconds: DELAY_BETWEEN_BATCHES_MS));
      }
    }

    print(''); // Nova linha

    if (fileUpdated) {
      // Reconstrói os arrays originais a partir de allItems
      final updatedMovies = allItems.sublist(0, items.length);
      final updatedSeries = allItems.sublist(items.length);
      
      // Salva o arquivo
      final outputData = isNewFormat 
          ? {
              'category': jsonData['category'], 
              'page': jsonData['page'],
              'totalPages': jsonData['totalPages'],
              'movies': updatedMovies, 
              'series': updatedSeries
            } 
          : allItems;
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(outputData));
      print('  💾 Salvo! ($fileUpdatedCount atualizações)');
    } else {
      print('  ℹ️ Nenhuma atualização necessária');
    }
  } catch (e) {
    print('  ❌ Erro: $e');
    errors++;
  }
}

Future<List<Map<String, dynamic>>> processBatch(List<dynamic> items, String fileName) async {
  final results = <Future<Map<String, dynamic>>>[];

  for (int i = 0; i < items.length; i += CONCURRENT_REQUESTS) {
    final subBatch = items.sublist(
      i,
      (i + CONCURRENT_REQUESTS < items.length) ? i + CONCURRENT_REQUESTS : items.length,
    );

    final subResults = await Future.wait(
      subBatch.map((item) => processItem(item, fileName)),
    );

    results.addAll(subResults.map((r) => Future.value(r)));
  }

  return Future.wait(results);
}

Future<Map<String, dynamic>> processItem(dynamic item, String fileName) async {
  totalProcessed++;

  final name = item['name'] as String? ?? '';
  final type = item['type'] as String? ?? 'movie';
  final shortName = name.length > 40 ? '${name.substring(0, 37)}...' : name;

  // Pula conteúdo adulto
  if (isAdultContent(name, fileName)) {
    skippedAdult++;
    stdout.write('\\r  🔞 Pulando adulto: $shortName                              ');
    return {'skipped': true, 'reason': 'adult'};
  }

  // Pula episódios de séries (só atualiza capa da série principal)
  if (isEpisode(name)) {
    skippedEpisode++;
    return {'skipped': true, 'reason': 'episode'};
  }

  stdout.write('\\r  🔍 Buscando: $shortName                                    ');

  try {
    final imageUrl = await searchTMDBImage(name, type);
    if (imageUrl != null) {
      stdout.write('\\r  ✅ Encontrado: $shortName                                  ');
    } else {
      stdout.write('\\r  ❌ Não encontrado: $shortName                              ');
    }
    return {'imageUrl': imageUrl};
  } catch (e) {
    errors++;
    stdout.write('\\r  ⚠️ Erro: $shortName                                        ');
    return {'error': e.toString()};
  }
}

bool isAdultFile(String fileName) {
  final lowerName = fileName.toLowerCase();
  return ADULT_KEYWORDS.any((keyword) => lowerName.contains(keyword));
}

bool isAdultContent(String name, String fileName) {
  final lowerName = name.toLowerCase();
  final lowerFileName = fileName.toLowerCase();
  return ADULT_KEYWORDS.any((keyword) =>
      lowerName.contains(keyword) || lowerFileName.contains(keyword));
}

bool isEpisode(String name) {
  // Padrões que indicam episódio
  final patterns = [
    RegExp(r'S\d+\s*E\d+', caseSensitive: false), // S01E05
    RegExp(r'T\d+\s*E\d+', caseSensitive: false), // T01E05
    RegExp(r'\d+\s*x\s*\d+', caseSensitive: false), // 1x05
    RegExp(r'Episódio\s*\d+', caseSensitive: false), // Episódio 5
    RegExp(r'EP?\s*\d+', caseSensitive: false), // EP5, E5
    RegExp(r'Temporada\s*\d+\s*-?\s*\d+', caseSensitive: false), // Temporada 1 - 5
  ];

  return patterns.any((pattern) => pattern.hasMatch(name));
}

String cleanTitle(String title) {
  var clean = title
      .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '') // Remove ano no final
      .replaceAll(RegExp(r'\s*S\d+E\d+.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*EP?\d+.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*-\s*Episódio\s*\d+.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*Temporada\s*\d+.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[™®©]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean;
}

int? extractYear(String name) {
  final match = RegExp(r'\((\d{4})\)').firstMatch(name);
  return match != null ? int.tryParse(match.group(1)!) : null;
}

String normalizeForComparison(String str) {
  return str
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[ñ]'), 'n')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<String?> searchTMDBImage(String name, String type) async {
  final cleanedTitle = cleanTitle(name);
  final year = extractYear(name);
  final cacheKey = cleanedTitle.toLowerCase();

  // Verifica cache
  if (seriesCache.containsKey(cacheKey)) {
    if (seriesCache[cacheKey] != null) cached++;
    return seriesCache[cacheKey];
  }

  final searchType = type == 'series' ? 'tv' : 'movie';
  final yearParam = year != null && searchType == 'movie' ? '&year=$year' : '';

  try {
    // Primeira busca
    var url = Uri.parse(
        'https://api.themoviedb.org/3/search/$searchType?api_key=$TMDB_API_KEY&language=pt-BR&query=${Uri.encodeComponent(cleanedTitle)}$yearParam');

    var response = await HttpClient()
        .getUrl(url)
        .timeout(const Duration(seconds: 15))
        .then((req) => req.close())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body);

      if (data['results'] != null && data['results'].isNotEmpty) {
        final bestMatch = findBestMatch(data['results'], cleanedTitle, year);
        if (bestMatch != null && bestMatch['poster_path'] != null) {
          final imageUrl = '$TMDB_IMAGE_BASE${bestMatch['poster_path']}';
          seriesCache[cacheKey] = imageUrl;
          updated++;
          return imageUrl;
        }
      }
    }

    // Tenta tipo alternativo
    final altType = searchType == 'tv' ? 'movie' : 'tv';
    url = Uri.parse(
        'https://api.themoviedb.org/3/search/$altType?api_key=$TMDB_API_KEY&language=pt-BR&query=${Uri.encodeComponent(cleanedTitle)}');

    response = await HttpClient()
        .getUrl(url)
        .timeout(const Duration(seconds: 15))
        .then((req) => req.close())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body);

      if (data['results'] != null && data['results'].isNotEmpty) {
        final bestMatch = findBestMatch(data['results'], cleanedTitle, year);
        if (bestMatch != null && bestMatch['poster_path'] != null) {
          final imageUrl = '$TMDB_IMAGE_BASE${bestMatch['poster_path']}';
          seriesCache[cacheKey] = imageUrl;
          updated++;
          return imageUrl;
        }
      }
    }

    seriesCache[cacheKey] = null;
    notFound++;
    return null;
  } catch (e) {
    errors++;
    return null;
  }
}

Map<String, dynamic>? findBestMatch(
    List<dynamic> results, String originalTitle, int? year) {
  if (results.isEmpty) return null;

  final normalizedOriginal = normalizeForComparison(originalTitle);

  // Busca correspondência exata com ano
  for (final result in results) {
    final tmdbTitle = result['title'] ?? result['name'] ?? '';
    final normalizedTmdb = normalizeForComparison(tmdbTitle);
    final tmdbYear = result['release_date']?.split('-')[0] ??
        result['first_air_date']?.split('-')[0];

    if (normalizedTmdb == normalizedOriginal &&
        (year == null || tmdbYear == year.toString())) {
      return result;
    }
  }

  // Busca correspondência exata sem ano
  for (final result in results) {
    final tmdbTitle = result['title'] ?? result['name'] ?? '';
    if (normalizeForComparison(tmdbTitle) == normalizedOriginal) {
      return result;
    }
  }

  // Retorna primeiro com poster
  for (final result in results) {
    if (result['poster_path'] != null) {
      return result;
    }
  }

  return results.first;
}
