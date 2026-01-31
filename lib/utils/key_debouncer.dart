import 'dart:async';
import 'package:flutter/services.dart';

/// Utilitário para prevenir processamento duplicado de teclas no Fire TV
/// O Fire TV às vezes envia eventos duplicados de teclas, especialmente para back
class KeyDebouncer {
  static final KeyDebouncer _instance = KeyDebouncer._internal();
  factory KeyDebouncer() => _instance;
  KeyDebouncer._internal();

  DateTime? _lastBackPress;
  // Aumentado para 600ms para Fire TV
  static const _debounceTime = Duration(milliseconds: 600);
  
  // Track if we're currently processing a back press
  bool _processingBack = false;
  Timer? _processingTimer;

  /// Verifica se o evento de voltar deve ser processado (evita duplicatas)
  /// Retorna true se deve processar, false se deve ignorar
  bool shouldProcessBack() {
    // Se já estamos processando um back, ignora
    if (_processingBack) {
      return false;
    }
    
    final now = DateTime.now();
    if (_lastBackPress != null && 
        now.difference(_lastBackPress!) < _debounceTime) {
      // Evento duplicado, ignorar
      return false;
    }
    
    _lastBackPress = now;
    
    // Mark as processing and clear after debounce time
    _processingBack = true;
    _processingTimer?.cancel();
    _processingTimer = Timer(_debounceTime, () {
      _processingBack = false;
    });
    
    return true;
  }

  /// Verifica se a tecla é de voltar
  static bool isBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.goBack || 
           key == LogicalKeyboardKey.escape ||
           key == LogicalKeyboardKey.browserBack;
  }

  /// Reseta o debouncer (útil ao mudar de tela)
  void reset() {
    _lastBackPress = null;
    _processingBack = false;
    _processingTimer?.cancel();
  }
  
  /// Disposes the timer
  void dispose() {
    _processingTimer?.cancel();
  }
}
