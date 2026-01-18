import 'dart:async';
import 'package:flutter/services.dart';

/// Utilitário para prevenir processamento duplicado de teclas no Fire TV
/// O Fire TV às vezes envia eventos duplicados de teclas, especialmente para back
class KeyDebouncer {
  static final KeyDebouncer _instance = KeyDebouncer._internal();
  factory KeyDebouncer() => _instance;
  KeyDebouncer._internal();

  DateTime? _lastBackPress;
  static const _debounceTime = Duration(milliseconds: 300);

  /// Verifica se o evento de voltar deve ser processado (evita duplicatas)
  /// Retorna true se deve processar, false se deve ignorar
  bool shouldProcessBack() {
    final now = DateTime.now();
    if (_lastBackPress != null && 
        now.difference(_lastBackPress!) < _debounceTime) {
      // Evento duplicado, ignorar
      return false;
    }
    _lastBackPress = now;
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
  }
}
