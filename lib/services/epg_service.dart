import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/program.dart';
import '../data/epg_mappings.dart';

/// Serviço de EPG (Electronic Program Guide)
/// 
/// Sistema resiliente com:
/// - Duas fontes de EPG: meuguia.tv (principal) e guiadetv.com (alternativa)
/// - Múltiplos proxies CORS com fallback automático
/// - Cache inteligente persistente com SharedPreferences
/// - Atualização sob demanda (mensal ou quando programação acabar)
/// - Retry com backoff exponencial
class EpgService {
  static final EpgService _instance = EpgService._internal();
  factory EpgService() => _instance;
  EpgService._internal();

  // ============== CACHE EM MEMÓRIA ==============
  final Map<String, List<Program>> _epgCache = {};
  final Map<String, int> _lastFetch = {};
  
  // ============== REQUISIÇÕES PENDENTES ==============
  final Map<String, Completer<List<Program>>> _pendingFetches = {};
  
  // ============== LISTENERS ==============
  final Set<Function(String, List<Program>)> _listeners = {};
  final Set<Function(int, int)> _progressListeners = {};

  // ============== CONSTANTES ==============
  static const int _cacheExpirationDays = 30;
  static const int _minFuturePrograms = 5;
  static const int _maxRetries = 4;
  static const int _initialRetryDelayMs = 1000;
  static const String _cacheKey = 'epg_cache_v2';
  static const String _metaKey = 'epg_cache_meta_v2';

  // ============== PROXIES CORS ==============
  static const List<String> _corsProxyPatterns = [
    'https://api.allorigins.win/raw?url=',          // 1. AllOrigins - Mais estável
    'https://corsproxy.io/?',                        // 2. CorsProxy.io - Rápido
    'https://api.codetabs.com/v1/proxy?quest=',     // 3. CodeTabs - Alternativa
    'https://proxy.cors.sh/',                        // 4. Cors.sh
    'https://thingproxy.freeboard.io/fetch/',       // 5. ThingProxy - Último recurso
  ];

  // Índice do proxy atual que funcionou
  int _currentProxyIndex = 0;
  
  // ============== MAPEAMENTO guiadetv.com ==============
  /// Canais que usam guiadetv.com como fonte
  /// Estes canais não funcionam bem no meuguia.tv e usam o guiadetv.com como fonte alternativa
  static const Map<String, String> _channelToGuiaDeTvSlug = {
    'hbo-pop': 'hbo-pop',
    'hbo-xtreme': 'hbo-xtreme',
    'hbo-mundi': 'hbo-mundi',
    'history2': 'history-2',
    'cnn-brasil': 'cnn-brasil',
    'cartoonito': 'cartoonito',
    'gloobinho': 'gloobinho',
    'food-network': 'food-network',
    'hgtv': 'hgtv',
    'curta': 'curta',
    'premiere2': 'premiere-2',
    'premiere3': 'premiere-3',
    'premiere4': 'premiere-4',
    'cultura': 'tv-cultura',  // TV Cultura
  };

  // ============== CONTROLE DE ESTADO ==============
  bool _initialized = false;
  bool _isLoading = false;
  int _loadedCount = 0;
  int _totalCount = 0;

  // ============== GETTERS ==============
  int get loadedCount => _loadedCount;
  int get totalCount => _totalCount;
  bool get isLoading => _isLoading;
  double get progress => _totalCount > 0 ? _loadedCount / _totalCount : 0.0;
  int get progressPercent => (_totalCount > 0 ? (_loadedCount / _totalCount * 100).round() : 0);

  // ============== LISTENERS ==============
  void addProgressListener(Function(int, int) listener) {
    _progressListeners.add(listener);
  }
  
  void removeProgressListener(Function(int, int) listener) {
    _progressListeners.remove(listener);
  }
  
  void _notifyProgressListeners() {
    for (final listener in _progressListeners) {
      try {
        listener(_loadedCount, _totalCount);
      } catch (e) {
        debugPrint('[EPG] Erro em progress listener: $e');
      }
    }
  }

  void addListener(Function(String, List<Program>) listener) {
    _listeners.add(listener);
  }
  
  void removeListener(Function(String, List<Program>) listener) {
    _listeners.remove(listener);
  }
  
  void _notifyListeners(String channelId, List<Program> programs) {
    for (final listener in _listeners) {
      try {
        listener(channelId, programs);
      } catch (e) {
        debugPrint('[EPG] Erro em listener: $e');
      }
    }
  }

  // ============== INICIALIZAÇÃO ==============
  
  /// Inicializa o serviço de EPG
  Future<bool> initialize() async {
    if (_initialized) {
      debugPrint('[EPG] Já inicializado');
      return true;
    }
    
    debugPrint('[EPG] Inicializando serviço com cache inteligente...');
    
    // Carrega cache do storage
    await _loadCacheFromStorage();
    
    // Identifica canais que precisam atualizar
    final channelsNeedingUpdate = _getChannelsNeedingUpdate();
    
    debugPrint('[EPG] Cache carregado: ${_epgCache.length} canais');
    debugPrint('[EPG] Canais precisando atualização: ${channelsNeedingUpdate.length}');
    
    _initialized = true;
    
    // Carrega apenas os que precisam em background
    if (channelsNeedingUpdate.isNotEmpty) {
      _loadChannelsInBackground(channelsNeedingUpdate);
    }
    
    return true;
  }

  /// Carrega cache do SharedPreferences
  Future<void> _loadCacheFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      final metaData = prefs.getString(_metaKey);
      
      if (cachedData != null && metaData != null) {
        final data = jsonDecode(cachedData) as Map<String, dynamic>;
        final meta = jsonDecode(metaData) as Map<String, dynamic>;
        final channelLastUpdate = meta['channelLastUpdate'] as Map<String, dynamic>? ?? {};
        
        data.forEach((channelId, programsJson) {
          final programs = (programsJson as List).map((p) => Program(
            id: p['id'],
            channelId: p['channelId'],
            title: p['title'],
            description: p['description'] ?? '',
            startTime: DateTime.parse(p['startTime']),
            endTime: DateTime.parse(p['endTime']),
            category: p['category'] ?? '',
            rating: p['rating'],
          )).toList();
          
          _epgCache[channelId] = programs;
          _lastFetch[channelId] = channelLastUpdate[channelId] ?? 0;
        });
        
        debugPrint('[EPG] Cache restaurado: ${_epgCache.length} canais');
      }
    } catch (e) {
      debugPrint('[EPG] Erro ao carregar cache: $e');
    }
  }

  /// Salva cache no SharedPreferences
  Future<void> _saveCacheToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final data = <String, dynamic>{};
      final meta = <String, dynamic>{
        'lastFullLoad': DateTime.now().millisecondsSinceEpoch,
        'channelLastUpdate': <String, dynamic>{},
      };
      
      _epgCache.forEach((channelId, programs) {
        data[channelId] = programs.map((p) => {
          'id': p.id,
          'channelId': p.channelId,
          'title': p.title,
          'description': p.description,
          'startTime': p.startTime.toIso8601String(),
          'endTime': p.endTime.toIso8601String(),
          'category': p.category,
          'rating': p.rating,
        }).toList();
        
        meta['channelLastUpdate'][channelId] = _lastFetch[channelId] ?? DateTime.now().millisecondsSinceEpoch;
      });
      
      await prefs.setString(_cacheKey, jsonEncode(data));
      await prefs.setString(_metaKey, jsonEncode(meta));
      
      debugPrint('[EPG] Cache salvo: ${_epgCache.length} canais');
    } catch (e) {
      debugPrint('[EPG] Erro ao salvar cache: $e');
    }
  }

  /// Identifica canais que precisam de atualização
  List<String> _getChannelsNeedingUpdate() {
    final now = DateTime.now();
    final needsUpdate = <String>[];
    final allChannels = EpgMappings.allChannelsWithEpg;
    
    for (final channelId in allChannels) {
      if (_needsUpdate(channelId, now)) {
        needsUpdate.add(channelId);
      }
    }
    
    return needsUpdate;
  }

  /// Verifica se canal precisa atualização
  bool _needsUpdate(String channelId, DateTime now) {
    // Sem cache = precisa atualizar
    if (!_epgCache.containsKey(channelId) || _epgCache[channelId]!.isEmpty) {
      return true;
    }
    
    final lastTime = _lastFetch[channelId] ?? 0;
    final lastDate = DateTime.fromMillisecondsSinceEpoch(lastTime);
    
    // Cache > 30 dias = precisa atualizar
    if (now.difference(lastDate).inDays > _cacheExpirationDays) {
      return true;
    }
    
    // Poucos programas futuros = precisa atualizar
    final programs = _epgCache[channelId]!;
    final futurePrograms = programs.where((p) => p.endTime.isAfter(now)).length;
    if (futurePrograms < _minFuturePrograms) {
      return true;
    }
    
    return false;
  }

  /// Carrega canais em background
  Future<void> _loadChannelsInBackground(List<String> channelIds) async {
    if (_isLoading) return;
    
    _isLoading = true;
    _totalCount = channelIds.length;
    _loadedCount = 0;
    _notifyProgressListeners();
    
    debugPrint('[EPG] Iniciando carregamento de ${channelIds.length} canais...');
    
    const batchSize = 3;
    const delayBetweenBatches = Duration(milliseconds: 1500);
    
    for (int i = 0; i < channelIds.length; i += batchSize) {
      final batch = channelIds.skip(i).take(batchSize).toList();
      
      await Future.wait(
        batch.map((channelId) => _fetchChannelEPGAsync(channelId).catchError((_) => <Program>[])),
      );
      
      _loadedCount = (i + batch.length).clamp(0, channelIds.length);
      _notifyProgressListeners();
      
      if (i + batchSize < channelIds.length) {
        await Future.delayed(delayBetweenBatches);
      }
    }
    
    _isLoading = false;
    
    // Salva cache após carregar tudo
    await _saveCacheToStorage();
    
    debugPrint('[EPG] Carregamento completo! ${_epgCache.length} canais com EPG');
  }

  // ============== FETCH COM PROXY FALLBACK ==============

  /// Busca URL com fallback entre múltiplos proxies CORS
  Future<String?> _fetchWithProxyFallback(String url, String channelId) async {
    final startProxyIndex = _currentProxyIndex;
    
    for (int retry = 0; retry < _maxRetries; retry++) {
      final retryDelay = _initialRetryDelayMs * (1 << retry); // Backoff exponencial
      
      for (int i = 0; i < _corsProxyPatterns.length; i++) {
        final proxyIndex = (startProxyIndex + i) % _corsProxyPatterns.length;
        final proxyPattern = _corsProxyPatterns[proxyIndex];
        
        // Constrói URL do proxy
        String proxyUrl;
        if (proxyPattern.contains('?')) {
          proxyUrl = '$proxyPattern${Uri.encodeComponent(url)}';
        } else if (proxyPattern.endsWith('/')) {
          proxyUrl = '$proxyPattern$url';
        } else {
          proxyUrl = '$proxyPattern${Uri.encodeComponent(url)}';
        }
        
        try {
          final response = await http.get(
            Uri.parse(proxyUrl),
            headers: {
              'Accept': 'text/html,application/xhtml+xml',
              'User-Agent': 'Mozilla/5.0 (compatible; SaimoTV/1.0)',
            },
          ).timeout(const Duration(seconds: 15));
          
          if (response.statusCode == 200) {
            final html = response.body;
            
            // Verifica se é HTML válido
            if (html.length > 500) {
              _currentProxyIndex = proxyIndex;
              return html;
            }
          } else if (response.statusCode == 429) {
            // Rate limit - próximo proxy
            debugPrint('[EPG] $channelId: Rate limit no proxy $proxyIndex');
            continue;
          }
        } catch (e) {
          // Erro - próximo proxy
          continue;
        }
      }
      
      // Aguarda antes do próximo retry
      if (retry < _maxRetries - 1) {
        await Future.delayed(Duration(milliseconds: retryDelay));
      }
    }
    
    return null;
  }

  // ============== FETCH EPG ==============

  /// Busca EPG de um canal (escolhe fonte automaticamente)
  Future<List<Program>> _fetchChannelEPGAsync(String channelId) async {
    // Verifica se há requisição pendente
    if (_pendingFetches.containsKey(channelId)) {
      return _pendingFetches[channelId]!.future;
    }

    final completer = Completer<List<Program>>();
    _pendingFetches[channelId] = completer;

    try {
      List<Program> programs = [];
      
      // Verifica se canal usa guiadetv.com
      if (_channelToGuiaDeTvSlug.containsKey(channelId)) {
        final slug = _channelToGuiaDeTvSlug[channelId]!;
        programs = await _fetchFromGuiaDeTv(channelId, slug);
      }
      
      // Se não encontrou no guiadetv ou não usa, busca no meuguia.tv
      if (programs.isEmpty) {
        final meuguiaCode = EpgMappings.getCode(channelId);
        if (meuguiaCode != null) {
          programs = await _fetchFromMeuGuia(channelId, meuguiaCode);
        }
      }
      
      // Atualiza cache
      if (programs.isNotEmpty) {
        _epgCache[channelId] = programs;
        _lastFetch[channelId] = DateTime.now().millisecondsSinceEpoch;
        _notifyListeners(channelId, programs);
      }
      
      completer.complete(programs);
      return programs;
    } catch (e) {
      debugPrint('[EPG] $channelId: erro - $e');
      completer.complete([]);
      return [];
    } finally {
      _pendingFetches.remove(channelId);
    }
  }

  /// Busca EPG do meuguia.tv
  Future<List<Program>> _fetchFromMeuGuia(String channelId, String code) async {
    final url = 'https://meuguia.tv/programacao/canal/$code';
    debugPrint('[EPG] $channelId: buscando de meuguia.tv ($code)');
    
    final html = await _fetchWithProxyFallback(url, channelId);
    if (html == null) return [];
    
    return _parseMeuGuiaHTML(html, channelId);
  }

  /// Busca EPG do guiadetv.com
  Future<List<Program>> _fetchFromGuiaDeTv(String channelId, String slug) async {
    final url = 'https://www.guiadetv.com/canal/$slug';
    debugPrint('[EPG] $channelId: buscando de guiadetv.com ($slug)');
    
    final html = await _fetchWithProxyFallback(url, channelId);
    if (html == null) return [];
    
    return _parseGuiaDeTvHTML(html, channelId);
  }

  // ============== PARSERS ==============

  /// Parse HTML do meuguia.tv
  List<Program> _parseMeuGuiaHTML(String html, String channelId) {
    final programs = <Program>[];
    
    try {
      final today = DateTime.now();
      final currentYear = today.year;
      
      // Remove templates ERB não processados
      var cleanHtml = html
        .replaceAll(RegExp(r'<li class="subheader[^"]*">\s*<%[^%]*%>\s*</li>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<%=[^%]*%>', caseSensitive: false), '');
      
      // Extrai datas dos cabeçalhos
      final dateHeaders = <({int index, DateTime date})>[];
      final headerRegex = RegExp(
        r'<li class="subheader[^"]*">[^<]*?(\d{1,2})/(\d{1,2})[^<]*</li>',
        caseSensitive: false,
      );
      
      for (final match in headerRegex.allMatches(cleanHtml)) {
        final day = int.tryParse(match.group(1)!) ?? today.day;
        final month = int.tryParse(match.group(2)!) ?? today.month;
        
        var date = DateTime(currentYear, month, day);
        if (month < today.month - 6) {
          date = DateTime(currentYear + 1, month, day);
        }
        
        dateHeaders.add((index: match.start, date: date));
      }
      
      if (dateHeaders.isEmpty) {
        dateHeaders.add((index: 0, date: DateTime(today.year, today.month, today.day)));
      }
      
      // Regex para capturar programas
      final programRegex = RegExp(
        "<div class=[\"']lileft time[\"']>\\s*(\\d{1,2}:\\d{2})\\s*</div>[\\s\\S]*?<h2>([^<]+)</h2>[\\s\\S]*?<h3>([^<]*)</h3>",
        caseSensitive: false,
      );
      
      int lastHour = -1;
      int currentDateIndex = 0;
      
      for (final match in programRegex.allMatches(cleanHtml)) {
        final timeStr = match.group(1)!;
        final title = match.group(2)!.trim();
        final category = match.group(3)?.trim() ?? '';
        
        while (currentDateIndex < dateHeaders.length - 1 && 
               match.start > dateHeaders[currentDateIndex + 1].index) {
          currentDateIndex++;
          lastHour = -1;
        }
        
        var programDate = DateTime(
          dateHeaders[currentDateIndex].date.year,
          dateHeaders[currentDateIndex].date.month,
          dateHeaders[currentDateIndex].date.day,
        );
        
        final timeParts = timeStr.split(':');
        final hours = int.tryParse(timeParts[0]) ?? 0;
        final minutes = int.tryParse(timeParts[1]) ?? 0;
        
        if (lastHour != -1 && hours < lastHour - 6) {
          programDate = programDate.add(const Duration(days: 1));
        }
        lastHour = hours;
        
        final startTime = DateTime(
          programDate.year,
          programDate.month,
          programDate.day,
          hours,
          minutes,
        );
        
        final endTime = startTime.add(const Duration(hours: 1));
        
        programs.add(Program(
          id: '${channelId}_${startTime.millisecondsSinceEpoch}',
          channelId: channelId,
          title: _decodeHtmlEntities(title),
          description: '',
          startTime: startTime,
          endTime: endTime,
          category: _decodeHtmlEntities(category),
        ));
      }
      
      // Ordena e ajusta horários
      programs.sort((a, b) => a.startTime.compareTo(b.startTime));
      _adjustEndTimes(programs);
      
      debugPrint('[EPG] $channelId: ${programs.length} programas (meuguia.tv)');
    } catch (e) {
      debugPrint('[EPG] Erro parsing meuguia.tv: $e');
    }
    
    return programs;
  }

  /// Parse HTML do guiadetv.com
  /// 
  /// Estrutura real do guiadetv.com (descoberta em 2025):
  /// <div class="row fs-2 mt-1 p-1 border-gray-300">
  ///   <div class="col-md-1 col-2">
  ///     <b class="fs-2">
  ///       <span data-dt="2025-01-12 15:25:00-03:00">15:25</span>
  ///     </b>
  ///   </div>
  ///   <div class="col-md-11 col-9">
  ///     <h3 class="text-color-primary">
  ///       <a href="/programa/nome-do-programa/hash">Nome do Programa</a>
  ///     </h3>
  ///   </div>
  /// </div>
  List<Program> _parseGuiaDeTvHTML(String html, String channelId) {
    final programs = <Program>[];
    
    try {
      final now = DateTime.now();
      DateTime currentDate = DateTime(now.year, now.month, now.day);
      
      // Lista para armazenar programas encontrados
      final rawPrograms = <({String title, String time, DateTime? dateTime})>[];
      
      // ========== ESTRATÉGIA PRINCIPAL: data-dt + link do programa ==========
      // Esta é a estrutura real do guiadetv.com
      // O atributo data-dt contém a data/hora completa
      // O título está dentro de <a href="/programa/...">
      
      final dataDtRegex = RegExp(
        r'<span\s+data-dt="(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}):\d{2}[^"]*"[^>]*>\s*\d{1,2}:\d{2}\s*</span>[\s\S]*?<h3[^>]*>\s*<a[^>]*href="[^"]*programa[^"]*"[^>]*>\s*([\s\S]*?)\s*</a>\s*</h3>',
        caseSensitive: false,
      );
      
      for (final match in dataDtRegex.allMatches(html)) {
        final dateStr = match.group(1)!;
        final timeStr = match.group(2)!;
        var title = match.group(3)!.trim();
        
        // Remove quebras de linha e espaços extras do título
        title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
        
        if (title.isNotEmpty && title.length >= 2 && !_isMenuOrNavigationItem(title)) {
          // Parse da data do atributo data-dt
          final dateParts = dateStr.split('-');
          final timeParts = timeStr.split(':');
          
          if (dateParts.length == 3 && timeParts.length >= 2) {
            final year = int.tryParse(dateParts[0]) ?? now.year;
            final month = int.tryParse(dateParts[1]) ?? now.month;
            final day = int.tryParse(dateParts[2]) ?? now.day;
            final hours = int.tryParse(timeParts[0]) ?? 0;
            final minutes = int.tryParse(timeParts[1]) ?? 0;
            
            final dateTime = DateTime(year, month, day, hours, minutes);
            rawPrograms.add((title: title, time: timeStr, dateTime: dateTime));
          }
        }
      }
      
      // ========== ESTRATÉGIA ALTERNATIVA 1: span com hora + link do programa ==========
      // Caso o data-dt não seja encontrado, usa padrão mais simples
      if (rawPrograms.length < 5) {
        final spanTimeRegex = RegExp(
          r'<span[^>]*>\s*(\d{1,2}:\d{2})\s*</span>[\s\S]*?<h3[^>]*>\s*<a[^>]*href="[^"]*programa[^"]*"[^>]*>\s*([\s\S]*?)\s*</a>\s*</h3>',
          caseSensitive: false,
        );
        
        for (final match in spanTimeRegex.allMatches(html)) {
          final time = match.group(1)!;
          var title = match.group(2)!.trim();
          title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
          
          if (title.isNotEmpty && title.length >= 2 && !_isMenuOrNavigationItem(title)) {
            rawPrograms.add((title: title, time: time, dateTime: null));
          }
        }
      }
      
      // ========== ESTRATÉGIA ALTERNATIVA 2: Extrai do link /programa/ ==========
      // Usa URL do programa para extrair o nome
      if (rawPrograms.length < 5) {
        final programLinkRegex = RegExp(
          r'(\d{1,2}:\d{2})[\s\S]*?<a[^>]*href="[^"]*programa/([^/"]+)/[^"]*"[^>]*>',
          caseSensitive: false,
        );
        
        for (final match in programLinkRegex.allMatches(html)) {
          final time = match.group(1)!;
          var slug = match.group(2)!;
          
          // Converte slug para título legível
          var title = slug
            .replaceAll('-', ' ')
            .split(' ')
            .map((word) => word.isNotEmpty 
              ? word[0].toUpperCase() + word.substring(1).toLowerCase() 
              : word)
            .join(' ');
          
          if (title.isNotEmpty && title.length >= 2 && !_isMenuOrNavigationItem(title)) {
            rawPrograms.add((title: title, time: time, dateTime: null));
          }
        }
      }
      
      // ========== ESTRATÉGIA ALTERNATIVA 3: Qualquer horário + texto ==========
      if (rawPrograms.length < 5) {
        final simpleRegex = RegExp(
          r'<b[^>]*>\s*<span[^>]*>\s*(\d{1,2}:\d{2})\s*</span>[\s\S]*?</b>[\s\S]*?<a[^>]*>\s*([^<]+)\s*</a>',
          caseSensitive: false,
        );
        
        for (final match in simpleRegex.allMatches(html)) {
          final time = match.group(1)!;
          var title = match.group(2)!.trim();
          title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
          
          if (title.isNotEmpty && title.length >= 2 && !_isMenuOrNavigationItem(title)) {
            rawPrograms.add((title: title, time: time, dateTime: null));
          }
        }
      }
      
      // Processa os programas encontrados
      int lastHour = -1;
      var processDate = currentDate;
      final seen = <String>{};
      
      for (final raw in rawPrograms) {
        DateTime startTime;
        
        if (raw.dateTime != null) {
          // Usa a data/hora do atributo data-dt
          startTime = raw.dateTime!;
        } else {
          // Calcula a data/hora baseado no horário
          final timeParts = raw.time.split(':');
          final hours = int.tryParse(timeParts[0]) ?? 0;
          final minutes = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;
          
          // Detecta virada de dia
          if (lastHour != -1 && hours < lastHour - 6) {
            processDate = processDate.add(const Duration(days: 1));
          }
          lastHour = hours;
          
          startTime = DateTime(
            processDate.year,
            processDate.month,
            processDate.day,
            hours,
            minutes,
          );
        }
        
        // Evita duplicatas pelo timestamp + título
        final key = '${startTime.millisecondsSinceEpoch}_${raw.title}';
        if (seen.contains(key)) continue;
        seen.add(key);
        
        programs.add(Program(
          id: '${channelId}_${startTime.millisecondsSinceEpoch}',
          channelId: channelId,
          title: _decodeHtmlEntities(raw.title),
          description: '',
          startTime: startTime,
          endTime: startTime.add(const Duration(hours: 1)),
          category: '',
        ));
      }
      
      // Ordena por horário
      programs.sort((a, b) => a.startTime.compareTo(b.startTime));
      
      // Ajusta horários de término
      _adjustEndTimes(programs);
      
      debugPrint('[EPG] $channelId: ${programs.length} programas (guiadetv.com)');
      
    } catch (e) {
      debugPrint('[EPG] Erro parsing guiadetv.com: $e');
    }
    
    return programs;
  }
  
  /// Helper para criar programa a partir de horário
  ({Program program, DateTime newDate, int lastHour})? _parseTimeAndCreateProgram(
    String title, String timeStr, String channelId, DateTime currentDate, int lastHour) {
    
    final timeParts = timeStr.split(':');
    final hours = int.tryParse(timeParts[0]) ?? 0;
    final minutes = int.tryParse(timeParts[1]) ?? 0;
    
    var newDate = currentDate;
    
    // Detecta virada de dia (se hora caiu muito)
    if (lastHour != -1 && hours < lastHour - 6) {
      newDate = currentDate.add(const Duration(days: 1));
    }
    
    final startTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      hours,
      minutes,
    );
    
    return (
      program: Program(
        id: '${channelId}_${startTime.millisecondsSinceEpoch}',
        channelId: channelId,
        title: _decodeHtmlEntities(title),
        description: '',
        startTime: startTime,
        endTime: startTime.add(const Duration(hours: 1)),
        category: '',
      ),
      newDate: newDate,
      lastHour: hours,
    );
  }

  /// Verifica se o título é um item de menu/navegação (não é programa)
  bool _isMenuOrNavigationItem(String title) {
    final lowerTitle = title.toLowerCase();
    final menuItems = [
      'página inicial', 'agora na tv', 'guia de jogos', 'esportes na tv',
      'notícias da tv', 'filmes e séries', 'documentários na tv',
      'sobre', 'contato', 'política de privacidade', 'política de cookies',
      'termos de uso', 'publicidade', 'guia de tv', 'nosso aplicativo',
      'início', 'programação da tv', 'futebol hoje', 'links úteis',
      'google play store',
    ];
    return menuItems.any((item) => lowerTitle.contains(item));
  }

  /// Ajusta horários de término baseado no próximo programa
  void _adjustEndTimes(List<Program> programs) {
    for (int i = 0; i < programs.length - 1; i++) {
      programs[i] = Program(
        id: programs[i].id,
        channelId: programs[i].channelId,
        title: programs[i].title,
        description: programs[i].description,
        startTime: programs[i].startTime,
        endTime: programs[i + 1].startTime,
        category: programs[i].category,
        rating: programs[i].rating,
      );
    }
  }

  /// Decodifica entidades HTML
  String _decodeHtmlEntities(String text) {
    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&nbsp;': ' ',
      '&eacute;': 'é',
      '&aacute;': 'á',
      '&iacute;': 'í',
      '&oacute;': 'ó',
      '&uacute;': 'ú',
      '&atilde;': 'ã',
      '&otilde;': 'õ',
      '&ccedil;': 'ç',
      '&Eacute;': 'É',
      '&Aacute;': 'Á',
      '&Iacute;': 'Í',
      '&Oacute;': 'Ó',
      '&Uacute;': 'Ú',
      '&Atilde;': 'Ã',
      '&Otilde;': 'Õ',
      '&Ccedil;': 'Ç',
      '&ndash;': '–',
      '&mdash;': '—',
    };
    
    var result = text;
    entities.forEach((entity, char) {
      result = result.replaceAll(entity, char);
    });
    
    result = result.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!)),
    );
    
    return result;
  }

  // ============== API PÚBLICA ==============

  /// Obtém EPG de um canal (com cache)
  Future<ChannelEPG> getChannelEPG(String channelId) async {
    final now = DateTime.now();
    
    // Verifica se precisa atualizar
    if (_needsUpdate(channelId, now)) {
      // Dispara fetch em background
      _fetchChannelEPGAsync(channelId);
    }
    
    // Retorna cache atual (pode estar vazio)
    return ChannelEPG(
      channelId: channelId,
      programs: _epgCache[channelId] ?? [],
      lastUpdated: _lastFetch[channelId] != null 
          ? DateTime.fromMillisecondsSinceEpoch(_lastFetch[channelId]!)
          : DateTime.now(),
    );
  }

  /// Obtém programa atual de um canal
  Future<CurrentProgram> getCurrentProgram(String channelId) async {
    final epg = await getChannelEPG(channelId);
    return epg.currentProgram;
  }
  
  /// Obtém programa atual de forma síncrona (usa cache)
  CurrentProgram? getCurrentProgramSync(String channelId) {
    final programs = _epgCache[channelId];
    if (programs == null || programs.isEmpty) {
      // Inicia busca em background
      getChannelEPG(channelId);
      return null;
    }
    
    final epg = ChannelEPG(
      channelId: channelId,
      programs: programs,
      lastUpdated: DateTime.now(),
    );
    return epg.currentProgram;
  }

  /// Verifica se canal tem EPG em cache
  bool hasEPG(String channelId) {
    return (_epgCache[channelId]?.length ?? 0) > 0;
  }

  /// Lista todos os canais com suporte a EPG
  List<String> listEPGChannels() {
    return EpgMappings.allChannelsWithEpg;
  }

  /// Limpa todo o cache
  Future<void> clearEPGCache() async {
    _epgCache.clear();
    _lastFetch.clear();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_metaKey);
    
    print('[EPG] Cache limpo');
  }

  /// Limpa cache de um canal específico
  void clearChannelCache(String channelId) {
    _epgCache.remove(channelId);
    _lastFetch.remove(channelId);
  }

  /// Força atualização de um canal
  Future<void> refreshChannelEPG(String channelId) async {
    clearChannelCache(channelId);
    await _fetchChannelEPGAsync(channelId);
    await _saveCacheToStorage();
  }

  /// Força atualização de todos os canais
  Future<void> refreshAllEPG() async {
    _epgCache.clear();
    _lastFetch.clear();
    await _loadChannelsInBackground(EpgMappings.allChannelsWithEpg);
  }

  /// Verifica e atualiza canais com programação acabando
  Future<int> checkAndUpdateExpiring() async {
    final now = DateTime.now();
    final needsUpdate = <String>[];
    
    for (final entry in _epgCache.entries) {
      final futurePrograms = entry.value.where((p) => p.endTime.isAfter(now)).length;
      if (futurePrograms < _minFuturePrograms) {
        needsUpdate.add(entry.key);
      }
    }
    
    if (needsUpdate.isNotEmpty) {
      await _loadChannelsInBackground(needsUpdate);
    }
    
    return needsUpdate.length;
  }

  /// Estatísticas do EPG
  Map<String, dynamic> getStats() {
    int totalPrograms = 0;
    int latestUpdate = 0;
    
    _epgCache.forEach((_, programs) => totalPrograms += programs.length);
    _lastFetch.forEach((_, time) { if (time > latestUpdate) latestUpdate = time; });
    
    final now = DateTime.now();
    final channelsNeedingUpdate = _getChannelsNeedingUpdate().length;
    
    return {
      'channelsWithEPG': _epgCache.length,
      'totalChannels': EpgMappings.allChannelsWithEpg.length,
      'totalPrograms': totalPrograms,
      'lastUpdate': latestUpdate > 0 ? DateTime.fromMillisecondsSinceEpoch(latestUpdate) : null,
      'isLoading': _isLoading,
      'channelsNeedingUpdate': channelsNeedingUpdate,
      'cacheAgeMs': latestUpdate > 0 ? now.millisecondsSinceEpoch - latestUpdate : 0,
    };
  }

  /// Obtém EPG de múltiplos canais de uma vez
  Map<String, ChannelEPG> getBulkEPG(List<String> channelIds) {
    final result = <String, ChannelEPG>{};
    
    for (final id in channelIds) {
      result[id] = ChannelEPG(
        channelId: id,
        programs: _epgCache[id] ?? [],
        lastUpdated: _lastFetch[id] != null 
            ? DateTime.fromMillisecondsSinceEpoch(_lastFetch[id]!)
            : DateTime.now(),
      );
      
      // Inicia busca em background se necessário
      if (_needsUpdate(id, DateTime.now())) {
        getChannelEPG(id);
      }
    }
    
    return result;
  }

  /// Pré-carrega EPG de múltiplos canais
  Future<void> preloadEPG(List<String> channelIds) async {
    final toLoad = channelIds.where((id) => _needsUpdate(id, DateTime.now())).toList();
    if (toLoad.isNotEmpty) {
      await _loadChannelsInBackground(toLoad);
    }
  }
  
  /// Limpa cache (alias para compatibilidade)
  void clearCache() {
    _epgCache.clear();
    _lastFetch.clear();
  }
  
  /// Obtém todos os programas do cache em memória (para carregamento rápido)
  /// Retorna um mapa de channelId -> List<Program>
  Map<String, List<Program>> getAllCachedPrograms() {
    return Map.from(_epgCache);
  }
  
  /// Carrega cache do storage e retorna todos os dados
  /// Usado para inicialização rápida da UI
  Future<Map<String, List<Program>>> loadAndGetCache() async {
    // Sempre carrega do storage para garantir dados atualizados
    await _loadCacheFromStorage();
    return getAllCachedPrograms();
  }
}
