import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Serviço para controle avançado de volume com suporte a boost de áudio
/// 
/// Usa o LoudnessEnhancer do Android para amplificar o volume além de 100%
class VolumeBoostService {
  static const _channel = MethodChannel('com.saimo.tv/volume');
  
  static final VolumeBoostService _instance = VolumeBoostService._internal();
  factory VolumeBoostService() => _instance;
  VolumeBoostService._internal();
  
  int? _currentSessionId;
  double _currentBoostLevel = 1.0;
  
  /// Define o nível de boost do volume
  /// 
  /// [boostLevel] - Nível de 0.0 a 2.0 (0% a 200%)
  /// [sessionId] - ID da sessão de áudio do video_player
  Future<bool> setVolumeBoost(double boostLevel, {int sessionId = 0}) async {
    try {
      _currentBoostLevel = boostLevel;
      
      // Se o volume está acima de 100%, aplica o LoudnessEnhancer
      if (boostLevel > 1.0 && sessionId > 0) {
        _currentSessionId = sessionId;
        
        final result = await _channel.invokeMethod<bool>('setVolumeBoost', {
          'boostLevel': boostLevel,
          'sessionId': sessionId,
        });
        
        debugPrint('VolumeBoost: Aplicado boost de ${(boostLevel * 100).round()}% - resultado: $result');
        return result ?? false;
      } else if (boostLevel <= 1.0) {
        // Desativa o boost se estiver em 100% ou menos
        await disableBoost();
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('VolumeBoost: Erro ao definir volume boost: $e');
      return false;
    }
  }
  
  /// Habilita o LoudnessEnhancer com ganho específico
  /// 
  /// [sessionId] - ID da sessão de áudio
  /// [gainMb] - Ganho em millibels (1000 mB = 10 dB)
  Future<bool> enableLoudnessEnhancer(int sessionId, int gainMb) async {
    try {
      _currentSessionId = sessionId;
      
      final result = await _channel.invokeMethod<bool>('enableLoudnessEnhancer', {
        'sessionId': sessionId,
        'gainMb': gainMb,
      });
      
      debugPrint('VolumeBoost: LoudnessEnhancer habilitado - ganho: ${gainMb}mB');
      return result ?? false;
    } catch (e) {
      debugPrint('VolumeBoost: Erro ao habilitar LoudnessEnhancer: $e');
      return false;
    }
  }
  
  /// Desativa o boost de volume
  Future<bool> disableBoost() async {
    try {
      final result = await _channel.invokeMethod<bool>('disableLoudnessEnhancer');
      _currentSessionId = null;
      debugPrint('VolumeBoost: Boost desativado');
      return result ?? false;
    } catch (e) {
      debugPrint('VolumeBoost: Erro ao desativar boost: $e');
      return false;
    }
  }
  
  /// Obtém o volume máximo do sistema
  Future<int> getMaxVolume() async {
    try {
      final result = await _channel.invokeMethod<int>('getMaxVolume');
      return result ?? 15;
    } catch (e) {
      debugPrint('VolumeBoost: Erro ao obter volume máximo: $e');
      return 15; // Valor padrão típico do Android
    }
  }
  
  /// Obtém o volume atual do sistema
  Future<int> getCurrentVolume() async {
    try {
      final result = await _channel.invokeMethod<int>('getCurrentVolume');
      return result ?? 0;
    } catch (e) {
      debugPrint('VolumeBoost: Erro ao obter volume atual: $e');
      return 0;
    }
  }
  
  /// Define o volume do sistema
  Future<bool> setSystemVolume(int volumeLevel) async {
    try {
      final result = await _channel.invokeMethod<bool>('setSystemVolume', {
        'volumeLevel': volumeLevel,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('VolumeBoost: Erro ao definir volume do sistema: $e');
      return false;
    }
  }
  
  /// Retorna o nível de boost atual
  double get currentBoostLevel => _currentBoostLevel;
  
  /// Verifica se o boost está ativo
  bool get isBoostActive => _currentBoostLevel > 1.0 && _currentSessionId != null;
}
