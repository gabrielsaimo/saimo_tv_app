import 'package:flutter/material.dart';

/// Sistema de escala responsiva para garantir que o conteúdo apareça
/// no mesmo tamanho visual em todas as telas, independente da resolução.
/// 
/// Usa uma resolução base de referência (1920x1080 - Full HD) para calcular
/// a escala proporcional em qualquer tamanho de tela.
class ResponsiveScale {
  // Resolução de referência (Full HD - padrão de TV)
  static const double _baseWidth = 1920.0;
  static const double _baseHeight = 1080.0;
  
  /// Calcula o fator de escala baseado no tamanho da tela atual
  /// Retorna um valor que quando multiplicado pelos tamanhos de design,
  /// resulta em proporções visuais consistentes
  static double getScale(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    // Usa a menor proporção para garantir que tudo caiba na tela
    final widthScale = size.width / _baseWidth;
    final heightScale = size.height / _baseHeight;
    
    // Usa a menor escala para garantir que o conteúdo caiba
    return (widthScale < heightScale ? widthScale : heightScale);
  }
  
  /// Escala um valor baseado na largura da tela
  static double scaleWidth(BuildContext context, double value) {
    final size = MediaQuery.of(context).size;
    return value * (size.width / _baseWidth);
  }
  
  /// Escala um valor baseado na altura da tela
  static double scaleHeight(BuildContext context, double value) {
    final size = MediaQuery.of(context).size;
    return value * (size.height / _baseHeight);
  }
  
  /// Retorna um widget que envolve o conteúdo com escala proporcional
  /// Isso garante que todo o conteúdo seja redimensionado uniformemente
  static Widget scaledContainer({
    required BuildContext context,
    required Widget child,
  }) {
    final scale = getScale(context);
    final size = MediaQuery.of(context).size;
    
    return SizedBox(
      width: size.width,
      height: size.height,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: SizedBox(
          width: _baseWidth,
          height: _baseHeight,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: const Size(_baseWidth, _baseHeight),
              textScaler: const TextScaler.linear(1.0),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Extension para facilitar o uso da escala responsiva
extension ResponsiveExtension on num {
  /// Escala o valor para a tela atual mantendo proporção
  double scaled(BuildContext context) {
    return toDouble() * ResponsiveScale.getScale(context);
  }
  
  /// Escala baseada na largura
  double scaledW(BuildContext context) {
    return ResponsiveScale.scaleWidth(context, toDouble());
  }
  
  /// Escala baseada na altura
  double scaledH(BuildContext context) {
    return ResponsiveScale.scaleHeight(context, toDouble());
  }
}
