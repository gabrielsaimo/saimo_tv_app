import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class VersionManager {
  static const String _versionUrl = 'https://saimo-tv.vercel.app/version.json';

  /// Verifica se há uma atualização disponível.
  /// Retorna `true` se houver uma atualização obrigatória ou recomendada.
  /// Retorna `false` se estiver na última versão ou se falhar ao verificar.
  static Future<VersionCheckResult> checkUpdate() async {
    if (kDebugMode) {
     // print('Verificando atualização...');
    }

    try {
      // 1. Obter versão local
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      //ignoring build number for now as semver is usually enough, but we can add if needed
      
      // 2. Obter versão remota
      final response = await http.get(Uri.parse(_versionUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String remoteVersion = data['version'] ?? '0.0.0';
        final bool forceUpdate = data['forceUpdate'] ?? false;

        // 3. Comparar versões
        final hasUpdate = _isVersionGreaterThan(remoteVersion, currentVersion);

        if (kDebugMode) {
          debugPrint('Versão Local: $currentVersion');
          debugPrint('Versão Remota: $remoteVersion');
          debugPrint('Atualização Disponível: $hasUpdate');
        }

        if (hasUpdate) {
            return VersionCheckResult(
                hasUpdate: true,
                currentVersion: currentVersion,
                newVersion: remoteVersion,
                forceUpdate: forceUpdate
            );
        }
      } else {
        if (kDebugMode) {
          debugPrint('Erro ao buscar versão: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao verificar atualização: $e');
      }
    }

    return VersionCheckResult(hasUpdate: false);
  }

  /// Compara duas strings de versão no formato X.Y.Z
  static bool _isVersionGreaterThan(String newVersion, String currentVersion) {
    try {
      List<int> newParts = newVersion.split('.').map(int.parse).toList();
      List<int> currentParts = currentVersion.split('.').map(int.parse).toList();

      for (int i = 0; i < newParts.length && i < currentParts.length; i++) {
        if (newParts[i] > currentParts[i]) {
          return true;
        } else if (newParts[i] < currentParts[i]) {
          return false;
        }
      }
      // Se tamanhos diferentes e prefixo igual, mais longo ganha (ex: 1.0.1 > 1.0)
      return newParts.length > currentParts.length;
    } catch (e) {
      return false; // Falha na comparação, assume sem update
    }
  }
}

class VersionCheckResult {
  final bool hasUpdate;
  final String? currentVersion;
  final String? newVersion;
  final bool forceUpdate;

  VersionCheckResult({
    required this.hasUpdate,
    this.currentVersion,
    this.newVersion,
    this.forceUpdate = false,
  });
}
