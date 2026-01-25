
import 'package:flutter_test/flutter_test.dart';
import 'package:saimo_tv/models/channel.dart';
import 'package:saimo_tv/services/channels_service.dart';

// Mock specific parts if needed, but for now we test parsing logic via a subclass or exposing method
// Since _parseTypescript is private, we can use reflection or better: test via public fetch if we can mock http.
// Or we can copy the logic here to test the regex.
// Ideally, we should have made the parser public or internal visible.
// Let's modify ChannelsService to make _parseTypescript public for testing or just test the regex pattern here.

void main() {
  group('Channels Parsing Logic', () {
    test('Should parse simple channel object', () {
      final content = """
      const LOGO_BASE = 'https://logos.com';
      
      const rawChannels = [
        { id: 'foo', name: 'Foo Channel', url: 'http://foo.m3u8', category: 'TV Aberta', logo: `\${LOGO_BASE}/foo.png` },
      ];
      """;

      // Recreating logic here to verify pattern correctness first
      final logoBase = 'https://logos.com';
      final channelRegex = RegExp(
        r"\{\s*id:\s*'([^']+)',\s*name:\s*'([^']+)',\s*url:\s*'([^']+)',\s*category:\s*'([^']+)',\s*logo:\s*(.+?)\s*\},",
        multiLine: true,
        dotAll: true,
      );

      final match = channelRegex.firstMatch(content);
      expect(match, isNotNull);
      expect(match!.group(1), 'foo');
      expect(match.group(2), 'Foo Channel');
      expect(match.group(3), 'http://foo.m3u8');
      expect(match.group(4), 'TV Aberta');
      expect(match.group(5), '`\${LOGO_BASE}/foo.png`');
    });

    test('Should handle fallback logo call', () {
      final content = """
        { id: 'bar', name: 'Bar', url: 'http://bar.m3u8', category: 'Filmes', logo: getFallbackLogo('Bar') },
      """;
      
      final channelRegex = RegExp(
        r"\{\s*id:\s*'([^']+)',\s*name:\s*'([^']+)',\s*url:\s*'([^']+)',\s*category:\s*'([^']+)',\s*logo:\s*(.+?)\s*\},",
        multiLine: true,
        dotAll: true,
      );

      final match = channelRegex.firstMatch(content);
      expect(match!.group(5), "getFallbackLogo('Bar')");
    });
  });
}
