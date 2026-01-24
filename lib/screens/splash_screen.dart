import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/channels_provider.dart';
import '../providers/settings_provider.dart';
import '../services/storage_service.dart';
import '../services/version_manager.dart'; // Import VersionManager
import '../utils/theme.dart';
import '../utils/tv_constants.dart';
import '../widgets/update_dialog.dart'; // Import UpdateDialog

/// Tela de Splash com animação
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _rotateAnimation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Carrega dados necessários
    final channelsProvider = context.read<ChannelsProvider>();
    await channelsProvider.loadChannels();

    // === VERIFICAÇÃO DE ATUALIZAÇÃO ===
    try {
      final updateResult = await VersionManager.checkUpdate();
      
      if (updateResult.hasUpdate && mounted) {
        // Mostra diálogo de atualização e PAUSA O FLUXO
        await showDialog(
          context: context,
          barrierDismissible: !updateResult.forceUpdate,
          builder: (context) => UpdateDialog(
            currentVersion: updateResult.currentVersion ?? 'Unknown',
            newVersion: updateResult.newVersion ?? 'Unknown',
            forceUpdate: updateResult.forceUpdate,
          ),
        );
        
        // Se for forceUpdate, o diálogo não fecha (WillPopScope), 
        // mas se o usuário fechar (se possível), checamos se devemos prosseguir
        if (updateResult.forceUpdate) return; // Não navega para proxima tela
      }
    } catch (e) {
      // Falha silenciosa na verificação de update, prossegue normal
      debugPrint('Erro no check de update: $e');
    }
    // ==================================

    // Aguarda animação completar
    await Future.delayed(const Duration(milliseconds: 2500));

    // Navega para o seletor de modo (TV ou Filmes)
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/selector');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaimoTheme.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: SaimoTheme.backgroundGradient,
        ),
        child: Center(
          child: TVAnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Transform.rotate(
                    angle: _rotateAnimation.value,
                    child: _buildContent(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo
        GestureDetector(
          onTap: () async {
            // Clique secreto para modo adulto
            final settings = context.read<SettingsProvider>();
            final unlocked = await settings.processSecretClick();
            
            if (unlocked && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔓 Modo adulto desbloqueado!'),
                  backgroundColor: SaimoTheme.success,
                ),
              );
            }
          },
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SaimoTheme.primary, SaimoTheme.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: SaimoTheme.primary.withOpacity(0.4),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.live_tv,
              size: 100,
              color: Colors.white,
            ),
          ),
        ),
        
        const SizedBox(height: 32),
        
        // Nome
        ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [SaimoTheme.primary, SaimoTheme.accent],
            ).createShader(bounds);
          },
          child: const Text(
            'SAIMO TV',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Slogan
        const Text(
          'TV ao vivo, sem limites',
          style: TextStyle(
            color: SaimoTheme.textSecondary,
            fontSize: TVConstants.fontM,
            letterSpacing: 1,
          ),
        ),
        
        const SizedBox(height: 48),
        
        // Loading
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            backgroundColor: SaimoTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(
              TVConstants.focusColor.withOpacity(0.7),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        const Text(
          'Carregando canais...',
          style: TextStyle(
            color: SaimoTheme.textTertiary,
            fontSize: TVConstants.fontS,
          ),
        ),
      ],
    );
  }
}

// AnimatedBuilder agora é TVAnimatedBuilder de tv_constants.dart
