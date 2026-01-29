
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import '../models/channel.dart';
import '../models/category.dart';

class ChannelsService {
  static const String _remoteUrl =
      'https://raw.githubusercontent.com/gabrielsaimo/free-tv/main/src/data/channels.ts';

  /// Fetches and parses channels from the remote TypeScript file.
  Future<List<Channel>> fetchChannels() async {
    try {
      final response = await http.get(Uri.parse(_remoteUrl));

      if (response.statusCode == 200) {
        // Optimization: also run this in compute if it gets large, but for now focus on PRO list
        return compute(_parseTypescript, response.body);
      } else {
        throw Exception('Failed to load channels: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching channels: $e');
      rethrow;
    }
  }

  Future<List<Channel>> fetchProChannels() async {
    try {
      final content = await rootBundle.loadString('assets/pro_list.m3u');
      return compute(_parseM3u, content);
    } catch (e) {
      debugPrint('Error fetching pro channels: $e');
      rethrow;
    }
  }
}

/// Top-level function for compute
List<Channel> _parseTypescript(String content) {
  final List<Channel> channels = [];
  
  // Extract constants
  final logoBase = _extractConstant(content, 'LOGO_BASE');
  final logoIntl = _extractConstant(content, 'LOGO_INTL');
  final logoUs = _extractConstant(content, 'LOGO_US');
  final logoLam = _extractConstant(content, 'LOGO_LAM');

  // Regex to match channel objects in the array
  // Matches { id: '...', name: '...', ... }
  final channelRegex = RegExp(
    r"\{\s*id:\s*'([^']+)',\s*name:\s*'([^']+)',\s*url:\s*'([^']+)',\s*category:\s*'([^']+)',\s*logo:\s*(.+?)\s*\},",
    multiLine: true,
    dotAll: true,
  );

  final matches = channelRegex.allMatches(content);

  int index = 1;
  for (final match in matches) {
    try {
      final id = match.group(1)!.trim();
      final name = match.group(2)!;
      final url = match.group(3)!;
      final categoryRaw = match.group(4)!;
      final logoRaw = match.group(5)!;

      // Resolve logo URL
      String? logo = _resolveLogo(logoRaw, {
        'LOGO_BASE': logoBase,
        'LOGO_INTL': logoIntl,
        'LOGO_US': logoUs,
        'LOGO_LAM': logoLam,
      });

      // Map remote category to local category
      final category = _mapCategory(categoryRaw);

      channels.add(Channel(
        id: id,
        name: name,
        url: url,
        logo: logo,
        category: category,
        channelNumber: index++, // Assign temporary number, will be re-assigned later
        isAdult: category == ChannelCategory.adulto, // Fix: Explicitly set based on category
      ));
    } catch (e) {
      debugPrint('Error parsing channel match: $e');
    }
  }

  return channels;
}

String _extractConstant(String content, String constantName) {
  final regex = RegExp(r"const\s+" + constantName + r"\s*=\s*'([^']+)';");
  final match = regex.firstMatch(content);
  return match?.group(1) ?? '';
}

String? _resolveLogo(String logoRaw, Map<String, String> constants) {
  // Handle template literals: `${LOGO_BASE}/foo.png`
  if (logoRaw.contains('\${')) {
    String resolved = logoRaw;
    // Remove backticks
    resolved = resolved.replaceAll('`', '');
    
    constants.forEach((key, value) {
      resolved = resolved.replaceAll('\${$key}', value);
    });
    return resolved;
  }
  
  // Handle simple strings: 'http://...'
  if (logoRaw.startsWith("'") && logoRaw.endsWith("'")) {
    return logoRaw.substring(1, logoRaw.length - 1);
  }
  
  // Handle function calls: getFallbackLogo(...) - return null to let local fallback handle it
  if (logoRaw.contains('getFallbackLogo')) {
    return null;
  }

  return null;
}

/// Top-level function for compute
List<Channel> _parseM3u(String content) {
  final List<Channel> channels = [];
  final lines = content.split('\n');
  
  String? currentName;
  String? currentLogo;
  String? currentGroup;
  
  // Simplistic M3U parser
  for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      if (line.startsWith('#EXTINF:')) {
          // Parse metadata
          // Example: #EXTINF:-1 tvg-name="A&E 4K" tvg-logo="..." group-title="...",A&E 4K
          
          // Extract logo
          final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
          currentLogo = logoMatch?.group(1);
          
          // Extract group
          final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
          currentGroup = groupMatch?.group(1);
          
          // Extract name (after last comma)
          final nameParts = line.split(',');
          if (nameParts.isNotEmpty) {
              currentName = nameParts.last.trim();
          }
      } else if (!line.startsWith('#') && currentName != null) {
          // Is URL
           // Map group to category
          final category = _mapProCategory(currentGroup ?? '', currentName);
          
          channels.add(Channel(
              id: 'pro_${channels.length}', // Generate unique ID
              name: currentName,
              url: line,
              logo: currentLogo,
              category: category,
              channelNumber: channels.length + 1,
              isAdult: category == ChannelCategory.adulto, // or check group name
              isMpegTs: true, // PRO channels are MPEG-TS
          ));
          
          // Reset for next entry
          currentName = null;
          currentLogo = null;
          currentGroup = null;
      }
  }
  
  return channels;
}

String _mapProCategory(String group, String name) {
    final lowerGroup = group.toLowerCase();
    final lowerName = name.toLowerCase();

    // 1. Adulto
    if (lowerGroup.contains('adulto') || lowerGroup.contains('xxx') || 
        lowerName.contains('adulto') || lowerName.contains('xxx') || lowerName.contains('sexo') || lowerName.contains('18+')) {
        return ChannelCategory.adulto;
    }

    // 2. 24 Horas (Moved up to prioritize over others)
    if (lowerGroup.contains('24h') || lowerName.contains('24h')) {
        return ChannelCategory.channels24h;
    }

    // 3. Legendados (Novo: Solicitado explicitamente)
    if (lowerGroup.contains('legendado') || lowerName.contains('[leg]') || lowerName.contains('(leg)')) {
        return ChannelCategory.legendados;
    }

    // 3. TV Aberta (Priorizar locais: Globo, SBT, Record, Band)
    if (lowerGroup.contains('abertos') || lowerGroup.contains('locais') || 
        lowerGroup.contains('globo') || lowerGroup.contains('sbt') || 
        lowerGroup.contains('record') || lowerGroup.contains('band') ||
        lowerGroup.contains('redetv') || lowerGroup.contains('gazeta')) {
        return ChannelCategory.tvAberta;
    }

    // 4. Esportes (Priorizar esportes ao vivo)
    if (lowerGroup.contains('esportes') || lowerGroup.contains('futebol') || 
        lowerGroup.contains('soccer') || lowerGroup.contains('espn') || 
        lowerGroup.contains('premiere') || lowerGroup.contains('combate') ||
        lowerGroup.contains('dazn') || lowerGroup.contains('ppv') || 
        lowerGroup.contains('nba') || lowerGroup.contains('ufc') ||
        lowerGroup.contains('sportv')) {
        return ChannelCategory.esportes;
    }

    // 5. Infantil (Priorizar conteúdo para crianças)
    if (lowerGroup.contains('infantil') || lowerGroup.contains('kids') || 
        lowerGroup.contains('desenho') || lowerGroup.contains('animacao') || 
        lowerGroup.contains('baby') || lowerGroup.contains('nickelodeon') || 
        lowerGroup.contains('cartoon') || lowerGroup.contains('disney')) {
        return ChannelCategory.infantil;
    }
    


    // 7. Qualidade High Priorities (Filmes, Séries, Documentários caem aqui se tiverem tag de qualidade)
    if (lowerGroup.contains('4k') || lowerName.contains('[4k]') || lowerName.contains('uhd')) return ChannelCategory.uhd;
    if (lowerGroup.contains('fhd') || lowerName.contains('[fhd]') || (lowerGroup.contains('h265') && !lowerGroup.contains('series'))) return ChannelCategory.fhd;
    if ((lowerGroup.contains('hd') && !lowerGroup.contains('fhd')) || lowerName.contains('[hd]')) return ChannelCategory.hd;
    if (lowerGroup.contains('sd') || lowerName.contains('[sd]')) return ChannelCategory.sd;

    // 8. Fallbacks (se não tiver tag de qualidade explícita)
    if (lowerGroup.contains('filmes') || lowerGroup.contains('cinema') || lowerGroup.contains('cine') || lowerGroup.contains('telecine') || lowerGroup.contains('hbo') || lowerGroup.contains('megapix')) return ChannelCategory.filmes;
    if (lowerGroup.contains('series') || lowerGroup.contains('séries')) return ChannelCategory.series;
    if (lowerGroup.contains('noticias') || lowerGroup.contains('news') || lowerGroup.contains('jornalismo') || lowerGroup.contains('cnn') || lowerGroup.contains('bandnews')) return ChannelCategory.noticias;
    if (lowerGroup.contains('documentarios') || lowerGroup.contains('doc') || lowerGroup.contains('discovery') || lowerGroup.contains('history') || lowerGroup.contains('animal planet')) return ChannelCategory.documentarios;
    if (lowerGroup.contains('variedades') || lowerGroup.contains('variety') || lowerGroup.contains('gnt') || lowerGroup.contains('viva')) return ChannelCategory.variedades;
    
    return 'Outros';
}

String _mapCategory(String remoteCategory) {
  // Determine mapping based on string similarity or exact match
  switch (remoteCategory) {
    case 'TV Aberta':
      return ChannelCategory.tvAberta;
    case 'Filmes':
      return ChannelCategory.filmes;
    case 'Series':
      return ChannelCategory.series;
    case 'Esportes':
      return ChannelCategory.esportes;
    case 'Noticias':
      return ChannelCategory.noticias;
    case 'Infantil':
      return ChannelCategory.infantil;
    case 'Documentarios':
      return ChannelCategory.documentarios;
    case 'Entretenimento':
      return ChannelCategory.entretenimento;
    case 'Internacionais':
      return ChannelCategory.internacionais;
    case 'Adulto':
      return ChannelCategory.adulto;
    default:
      return 'Outros';
  }
}
