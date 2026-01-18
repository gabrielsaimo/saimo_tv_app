import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final testUrls = [
    'http://coneasy.lat:80/movie/kyeoj2w4/0drti608/3543151.mp4',
    'http://coneasy.lat:80/movie/kyeoj2w4/0drti608/3562530.mp4',
  ];

  for (final url in testUrls) {
    print('\n========================================');
    print('Testando: $url');
    print('========================================\n');
    
    try {
      final resolvedUrl = await resolveRedirects(url);
      print('\n✅ URL Final: $resolvedUrl');
    } catch (e) {
      print('\n❌ Erro: $e');
    }
  }
}

Future<String> resolveRedirects(String url) async {
  final client = http.Client();
  var currentUrl = url;
  var redirectCount = 0;
  const maxRedirects = 10;
  
  try {
    while (redirectCount < maxRedirects) {
      print('[$redirectCount] Verificando: $currentUrl');
      
      // Usa GET com range para não baixar arquivo inteiro
      final request = http.Request('GET', Uri.parse(currentUrl))
        ..followRedirects = false
        ..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Android TV) AppleWebKit/537.36 SaimoTV/1.0'
        ..headers['Range'] = 'bytes=0-0';  // Só pega 1 byte
      
      final response = await client.send(request).timeout(const Duration(seconds: 15));
      
      print('    Status: ${response.statusCode}');
      print('    isRedirect: ${response.isRedirect}');
      
      // Verifica redirect manualmente pelo status code
      if (response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 307 || response.statusCode == 308) {
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          // Se a location é relativa, constrói URL absoluta
          if (location.startsWith('/')) {
            final uri = Uri.parse(currentUrl);
            currentUrl = '${uri.scheme}://${uri.host}:${uri.port}$location';
          } else {
            currentUrl = location;
          }
          redirectCount++;
          print('    → Redirect para: $currentUrl');
        } else {
          print('    ⚠️ Location header vazio ou ausente');
          break;
        }
      } else {
        // Não é redirect, URL final encontrada
        print('    ✓ URL final (status ${response.statusCode})');
        break;
      }
    }
    
    return currentUrl;
  } finally {
    client.close();
  }
}
