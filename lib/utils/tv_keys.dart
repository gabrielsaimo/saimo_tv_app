import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Constantes de teclas para navegação em TV/Fire TV/Android TV
class TVKeys {
  // Teclas de navegação D-Pad
  static const dPadUp = LogicalKeyboardKey.arrowUp;
  static const dPadDown = LogicalKeyboardKey.arrowDown;
  static const dPadLeft = LogicalKeyboardKey.arrowLeft;
  static const dPadRight = LogicalKeyboardKey.arrowRight;
  
  // Teclas de confirmação
  static const select = LogicalKeyboardKey.select;
  static const enter = LogicalKeyboardKey.enter;
  
  // Teclas de navegação
  static const back = LogicalKeyboardKey.goBack;
  static const escape = LogicalKeyboardKey.escape;
  static const home = LogicalKeyboardKey.goHome;
  
  // Teclas de mídia
  static const playPause = LogicalKeyboardKey.mediaPlayPause;
  static const play = LogicalKeyboardKey.mediaPlay;
  static const pause = LogicalKeyboardKey.mediaPause;
  static const stop = LogicalKeyboardKey.mediaStop;
  static const fastForward = LogicalKeyboardKey.mediaFastForward;
  static const rewind = LogicalKeyboardKey.mediaRewind;
  static const channelUp = LogicalKeyboardKey.channelUp;
  static const channelDown = LogicalKeyboardKey.channelDown;
  
  // Teclas de volume
  static const volumeUp = LogicalKeyboardKey.audioVolumeUp;
  static const volumeDown = LogicalKeyboardKey.audioVolumeDown;
  static const volumeMute = LogicalKeyboardKey.audioVolumeMute;
  
  // Teclas de info
  static const info = LogicalKeyboardKey.info;
  static const guide = LogicalKeyboardKey.guide;
  static const menu = LogicalKeyboardKey.contextMenu;
  
  // Teclas de controle de jogo (Fire TV)
  static const gameA = LogicalKeyboardKey.gameButtonA;
  static const gameB = LogicalKeyboardKey.gameButtonB;
  static const gameX = LogicalKeyboardKey.gameButtonX;
  static const gameY = LogicalKeyboardKey.gameButtonY;
  
  /// Verifica se a tecla é de confirmação
  static bool isSelect(LogicalKeyboardKey key) {
    return key == select || key == enter || key == gameA;
  }
  
  /// Verifica se a tecla é de voltar
  static bool isBack(LogicalKeyboardKey key) {
    return key == back || key == escape || key == gameB;
  }
  
  /// Verifica se a tecla é de navegação
  static bool isNavigation(LogicalKeyboardKey key) {
    return key == dPadUp || 
           key == dPadDown || 
           key == dPadLeft || 
           key == dPadRight;
  }
  
  /// Verifica se a tecla é de canal
  static bool isChannel(LogicalKeyboardKey key) {
    return key == channelUp || key == channelDown;
  }
  
  /// Verifica se a tecla é numérica
  static bool isNumeric(LogicalKeyboardKey key) {
    return _numericKeys.contains(key);
  }
  
  /// Retorna o dígito da tecla numérica (ou null)
  static String? getDigit(LogicalKeyboardKey key) {
    final index = _numericKeys.indexOf(key);
    if (index >= 0) {
      return '${index % 10}'; // 0-9
    }
    return null;
  }
  
  static const _numericKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];
}

/// Helper para lidar com eventos de teclado em TV
class TVKeyHandler {
  /// Processa evento de tecla e retorna ação
  static TVKeyAction? processKeyEvent(KeyEvent event) {
    // Responde tanto a KeyDownEvent quanto KeyRepeatEvent
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }
    
    final key = event.logicalKey;
    
    // Navegação
    if (key == TVKeys.dPadUp) return TVKeyAction.up;
    if (key == TVKeys.dPadDown) return TVKeyAction.down;
    if (key == TVKeys.dPadLeft) return TVKeyAction.left;
    if (key == TVKeys.dPadRight) return TVKeyAction.right;
    
    // Confirmação (apenas KeyDownEvent para evitar duplo trigger)
    if (event is KeyDownEvent) {
      if (TVKeys.isSelect(key)) return TVKeyAction.select;
      if (TVKeys.isBack(key)) return TVKeyAction.back;
    }
    
    // Canais
    if (key == TVKeys.channelUp) return TVKeyAction.channelUp;
    if (key == TVKeys.channelDown) return TVKeyAction.channelDown;
    
    // Volume
    if (key == TVKeys.volumeUp) return TVKeyAction.volumeUp;
    if (key == TVKeys.volumeDown) return TVKeyAction.volumeDown;
    if (key == TVKeys.volumeMute) return TVKeyAction.mute;
    
    // Mídia
    if (key == TVKeys.playPause || 
        key == LogicalKeyboardKey.space) return TVKeyAction.playPause;
    
    // Info
    if (key == TVKeys.info || 
        key == LogicalKeyboardKey.keyI) return TVKeyAction.info;
    
    // Guide
    if (key == TVKeys.guide ||
        key == LogicalKeyboardKey.keyG) return TVKeyAction.guide;
    
    // Numérico
    if (TVKeys.isNumeric(key)) {
      return TVKeyAction.numeric;
    }
    
    return null;
  }
}

/// Ações possíveis de tecla em TV
enum TVKeyAction {
  up,
  down,
  left,
  right,
  select,
  back,
  channelUp,
  channelDown,
  volumeUp,
  volumeDown,
  mute,
  playPause,
  info,
  guide,
  numeric,
}

/// Mixin para adicionar suporte a navegação de TV em widgets
mixin TVNavigationMixin<T extends StatefulWidget> on State<T> {
  // Index do item focado atual
  int _focusedIndex = 0;
  int get focusedIndex => _focusedIndex;
  
  // Total de itens navegáveis
  int get itemCount;
  
  // Número de colunas (para grid)
  int get columnCount => 1;
  
  /// Atualiza o index focado
  void setFocusedIndex(int index) {
    if (index >= 0 && index < itemCount) {
      setState(() => _focusedIndex = index);
      onFocusChanged(index);
    }
  }
  
  /// Callback quando o foco muda
  void onFocusChanged(int index) {}
  
  /// Callback quando um item é selecionado
  void onItemSelected(int index);
  
  /// Callback quando o botão voltar é pressionado
  void onBackPressed() {
    Navigator.of(context).maybePop();
  }
  
  /// Processa eventos de navegação
  KeyEventResult handleTVNavigation(KeyEvent event) {
    final action = TVKeyHandler.processKeyEvent(event);
    if (action == null) return KeyEventResult.ignored;
    
    switch (action) {
      case TVKeyAction.up:
        if (columnCount > 1) {
          setFocusedIndex(_focusedIndex - columnCount);
        } else {
          setFocusedIndex(_focusedIndex - 1);
        }
        return KeyEventResult.handled;
        
      case TVKeyAction.down:
        if (columnCount > 1) {
          setFocusedIndex(_focusedIndex + columnCount);
        } else {
          setFocusedIndex(_focusedIndex + 1);
        }
        return KeyEventResult.handled;
        
      case TVKeyAction.left:
        if (columnCount > 1) {
          if (_focusedIndex % columnCount > 0) {
            setFocusedIndex(_focusedIndex - 1);
          }
        }
        return KeyEventResult.handled;
        
      case TVKeyAction.right:
        if (columnCount > 1) {
          if (_focusedIndex % columnCount < columnCount - 1) {
            setFocusedIndex(_focusedIndex + 1);
          }
        }
        return KeyEventResult.handled;
        
      case TVKeyAction.select:
        onItemSelected(_focusedIndex);
        return KeyEventResult.handled;
        
      case TVKeyAction.back:
        onBackPressed();
        return KeyEventResult.handled;
        
      default:
        return KeyEventResult.ignored;
    }
  }
}

/// Extension para facilitar verificação de plataforma
extension PlatformExtension on BuildContext {
  /// Verifica se estamos rodando em TV (baseado no tamanho da tela)
  bool get isTV {
    final size = MediaQuery.of(this).size;
    // TV geralmente tem aspect ratio > 1.7 e largura > 1200
    return size.width > 1200 && (size.width / size.height) > 1.5;
  }
  
  /// Verifica se é uma tela grande (tablet ou TV)
  bool get isLargeScreen {
    final size = MediaQuery.of(this).size;
    return size.shortestSide > 600;
  }
}
