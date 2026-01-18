import 'package:http/http.dart' as http;

void main() async {
  final testUrl = 'http://coneasy.lat:80/movie/kyeoj2w4/0drti608/3543151.mp4';
  
  print('=== TESTE DE URL DE VÍDEO ===\n');
  print('URL Original: $testUrl\n');
  
  // Resolver redirects
  final finalUrl = await resolveRedirects(testUrl);
  print('\n✅ URL Final Resolvida: $finalUrl');
  
  // Testar se a URL final funciona
  print('\n=== TESTANDO URL FINAL ===');
  try {
    final response = await http.get(
      Uri.parse(finalUrl),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Android TV) AppleWebKit/537.36 SaimoTV/1.0',
        'Range': 'bytes=0-1000',
      },
    ).timeout(const Duration(seconds: 15));
    
    print('Status: ${response.statusCode}');
    print('Content-Type: ${response.headers['content-type']}');
    print('Content-Length: ${response.headers['content-length']}');
    print('Primeiros bytes recebidos: ${response.bodyBytes.length}');
    
    if (response.statusCode == 200 || response.statusCode     if (response.statusCode == 200 || rNA!    if (response.s.'    if (response.statusCode == 200 || response.statusCode     if (response.st  }
                                           sar                                 tring>                       g                                            sar   r c                                           saonst ma                                  il                                            nt('[                                  ent                          r               equest('GET', Uri.parse(currentUrl))
        ..followRedirects = false
        ..headers['User-Agent']        ..headers['User-Android 1       oi        ..headers['User-Agent']               ..h        ..headers['User-Agent']             f        ..headers['User-Agent']        ..headers['User-Andrration(seconds: 15));
      
      print('    Status: ${response.statusCode}');
      
      if (response.statusCode == 301 || response.statusCode == 302 || 
          response.statusCode == 307 || response.statusCode == 308) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i          i      
                                 
  }
}
