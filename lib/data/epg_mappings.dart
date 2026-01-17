/// Mapeamento de canais para códigos do meuguia.tv
/// 
/// Fonte dos dados: https://meuguia.tv
/// O código é usado para construir a URL: https://meuguia.tv/programacao/canal/{codigo}
/// 
/// Total: 74+ canais mapeados
class EpgMappings {
  static const Map<String, String> channelToMeuGuiaCode = {
    // === TELECINE (6 canais) ===
    'telecine-action': 'TC2',
    'telecine-premium': 'TC1',
    'telecine-pipoca': 'TC4',
    'telecine-cult': 'TC5',
    'telecine-fun': 'TC6',
    'telecine-touch': 'TC3',
    
    // === HBO (7 canais) ===
    'hbo': 'HBO',
    'hbo2': 'HB2',
    'hbo-family': 'HFA',
    'hbo-plus': 'HPL',
    'hbo-mundi': 'HMU',
    'hbo-pop': 'HPO',
    'hbo-xtreme': 'HXT',
    
    // === GLOBO (5 canais) ===
    'globo-sp': 'GRD',
    'globo-rj': 'GRD',
    'globo-mg': 'GRD',
    'globo-rs': 'GRD',
    'globo-es': 'GRD',
    'globo-am': 'GRD',
    'globo-news': 'GLN',
    
    // === SPORTV (3 canais) ===
    'sportv': 'SPO',
    'sportv2': 'SP2',
    'sportv3': 'SP3',
    
    // === ESPN (5 canais) ===
    'espn': 'ESP',
    'espn2': 'ES2',
    'espn3': 'ES3',
    'espn4': 'ES4',
    'espn5': 'ES5',  // ESPN Extra
    
    // === TV ABERTA (8 canais) ===
    'sbt': 'SBT',
    'band': 'BAN',
    'record': 'REC',
    'rede-tv': 'RTV',
    'tv-brasil': 'TED',
    'aparecida': 'TAP',
    'cultura': 'CUL',
    'tv-gazeta': 'GAZ',
    
    // === NOTÍCIAS (3 canais) ===
    'cnn-brasil': 'CNB',
    'band-news': 'NEW',
    'record-news': 'RCN',
    
    // === INFANTIL (6 canais) ===
    'cartoon-network': 'CAR',
    'cartoonito': 'CTO',
    'discovery-kids': 'DIK',
    'gloob': 'GOB',
    'gloobinho': 'GBI',
    'adult-swim': 'ASW',
    'nickelodeon': 'NIC',
    'nick-jr': 'NJR',
    'disney-channel': 'DCH',
    'disney-junior': 'DJR',
    'disney-xd': 'DXD',
    
    // === DOCUMENTÁRIOS (9 canais) ===
    'discovery': 'DIS',
    'discovery-turbo': 'DTU',
    'discovery-world': 'DIW',
    'discovery-science': 'DSC',
    'discovery-hh': 'HEA',  // Discovery Home & Health
    'animal-planet': 'APL',
    'history': 'HIS',
    'history2': 'H2H',
    'tlc': 'TRV',
    'discovery-id': 'IDD',  // Investigation Discovery
    'food-network': 'FOO',
    'hgtv': 'HGT',
    'nat-geo': 'NGC',
    'nat-geo-wild': 'NGW',
    
    // === SÉRIES (7 canais) ===
    'warner': 'WBT',
    'tnt': 'TNT',
    'tnt-series': 'TNS',
    'axn': 'AXN',
    'sony': 'SET',
    'universal-tv': 'USA',
    'ae': 'MDO',  // A&E
    'fx': 'FXX',
    'paramount': 'PAR',
    
    // === FILMES (6 canais) ===
    'amc': 'MGM',
    'tcm': 'TCM',
    'space': 'SPA',
    'cinemax': 'MNX',
    'megapix': 'MPX',
    'studio-universal': 'HAL',
    
    // === ENTRETENIMENTO (6 canais) ===
    'multishow': 'MSW',
    'bis': 'MSH',
    'viva': 'VIV',
    'off': 'OFF',
    'gnt': 'GNT',
    'arte1': 'BQ5',
    'comedy-central': 'CCE',
    'mtv': 'MTV',
    'vh1': 'VH1',
    'e-entertainment': 'EEN',
    
    // === ESPORTES PREMIUM (3 canais) ===
    'premiere': '121',
    'combate': '135',
    'band-sports': 'BSP',
    'woohoo': 'WOO',
    
    // === MAX (antigo HBO Max) ===
    'max': 'HBO',
  };

  /// Obtém o código do meuguia.tv para um canal
  static String? getCode(String channelId) {
    return channelToMeuGuiaCode[channelId];
  }

  /// Verifica se o canal tem EPG disponível
  static bool hasEpg(String channelId) {
    return channelToMeuGuiaCode.containsKey(channelId);
  }
  
  /// Lista todos os canais com EPG disponível
  static List<String> get allChannelsWithEpg {
    return channelToMeuGuiaCode.keys.toList();
  }
  
  /// Retorna a URL do meuguia.tv para um canal
  static String? getMeuGuiaUrl(String channelId) {
    final code = getCode(channelId);
    if (code == null) return null;
    return 'https://meuguia.tv/programacao/canal/$code';
  }
}
