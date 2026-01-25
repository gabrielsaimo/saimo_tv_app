
import 'package:http/http.dart' as http;
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
        return _parseTypescript(response.body);
      } else {
        throw Exception('Failed to load channels: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching channels: $e');
      rethrow;
    }
  }

  /// Parses the TypeScript content to extract channel data.
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
        final id = match.group(1)!;
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
        print('Error parsing channel match: $e');
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
}
