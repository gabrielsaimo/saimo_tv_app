import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/channels_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/lazy_movies_provider.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';

/// Tela de Configurações com navegação D-Pad
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  int _selectedIndex = 0;
  
  // Lista de itens navegáveis
  final List<_SettingItem> _items = [
    _SettingItem(type: _ItemType.toggle, id: 'autoPlay', title: 'Reprodução Automática', subtitle: 'Iniciar reprodução ao selecionar um canal'),
    _SettingItem(type: _ItemType.toggle, id: 'enableSubtitles', title: 'Legendas (Closed Caption)', subtitle: 'Exibir legendas quando disponíveis'),
    _SettingItem(type: _ItemType.dropdown, id: 'preferredQuality', title: 'Qualidade Preferida', subtitle: 'Selecione a qualidade do vídeo'),
    _SettingItem(type: _ItemType.slider, id: 'volume', title: 'Volume Padrão', subtitle: ''),
    _SettingItem(type: _ItemType.toggle, id: 'showEpg', title: 'Mostrar Programação (EPG)', subtitle: 'Exibir informações do programa atual'),
    _SettingItem(type: _ItemType.special, id: 'adultMode', title: 'Canais Adultos', subtitle: 'Conteúdo +18'),
    _SettingItem(type: _ItemType.action, id: 'clearFavorites', title: 'Limpar Favoritos', subtitle: 'Remover todos os canais favoritos'),
    _SettingItem(type: _ItemType.action, id: 'resetSettings', title: 'Resetar Configurações', subtitle: 'Restaurar configurações padrão'),
    _SettingItem(type: _ItemType.info, id: 'version', title: 'Versão', subtitle: '11.0.0'),
    _SettingItem(type: _ItemType.action, id: 'back', title: 'Voltar', subtitle: 'Retornar à tela anterior'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    setState(() {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          HapticFeedback.selectionClick();
          _selectedIndex = (_selectedIndex - 1).clamp(0, _items.length - 1);
          _scrollToSelected();
          break;
          
        case LogicalKeyboardKey.arrowDown:
          HapticFeedback.selectionClick();
          _selectedIndex = (_selectedIndex + 1).clamp(0, _items.length - 1);
          _scrollToSelected();
          break;
          
        case LogicalKeyboardKey.arrowLeft:
          HapticFeedback.selectionClick();
          _handleLeftRight(-1);
          break;
          
        case LogicalKeyboardKey.arrowRight:
          HapticFeedback.selectionClick();
          _handleLeftRight(1);
          break;
          
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.gameButtonA:
          HapticFeedback.mediumImpact();
          _handleSelect();
          break;
          
        case LogicalKeyboardKey.escape:
        case LogicalKeyboardKey.goBack:
        case LogicalKeyboardKey.gameButtonB:
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
          break;
      }
    });
  }

  void _scrollToSelected() {
    final itemHeight = 80.0;
    final offset = _selectedIndex * itemHeight;
    final screenHeight = MediaQuery.of(context).size.height;
    
    if (offset > _scrollController.offset + screenHeight - 200) {
      _scrollController.animateTo(
        offset - screenHeight + 300,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (offset < _scrollController.offset + 100) {
      _scrollController.animateTo(
        (offset - 100).clamp(0.0, double.infinity),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleLeftRight(int direction) {
    final item = _items[_selectedIndex];
    final settings = context.read<SettingsProvider>();
    
    switch (item.id) {
      case 'volume':
        final newVolume = (settings.volume + direction * 0.1).clamp(0.0, 1.0);
        settings.setVolume(newVolume);
        break;
        
      case 'preferredQuality':
        final options = ['auto', '1080p', '720p', '480p', '360p'];
        final currentIndex = options.indexOf(settings.preferredQuality);
        final newIndex = (currentIndex + direction).clamp(0, options.length - 1);
        settings.setPreferredQuality(options[newIndex]);
        break;
    }
  }

  void _handleSelect() {
    final item = _items[_selectedIndex];
    final settings = context.read<SettingsProvider>();
    
    switch (item.id) {
      case 'autoPlay':
        settings.setAutoPlay(!settings.autoPlay);
        break;
        
      case 'enableSubtitles':
        settings.setEnableSubtitles(!settings.enableSubtitles);
        break;
        
      case 'showEpg':
        settings.setShowEpg(!settings.showEpg);
        break;
        
      case 'adultMode':
        // Sempre mostra o diálogo de senha para ativar/desativar
        _showPasswordDialog(settings, isFirstTime: false);
        break;
        
      case 'clearFavorites':
        _confirmClearFavorites();
        break;
        
      case 'resetSettings':
        _confirmResetSettings();
        break;
        
      case 'back':
        Navigator.of(context).pop();
        break;
    }
  }

  void _handleAdultUnlock(SettingsProvider settings) async {
    // Mostra diretamente o diálogo de senha para ativar/desativar
    _showPasswordDialog(settings, isFirstTime: !settings.adultModeUnlocked);
  }

  void _showPasswordDialog(SettingsProvider settings, {bool isFirstTime = false}) {
    String enteredPassword = '';
    bool showError = false;
    int focusedKey = 4; // Começa no 5 (centro do teclado)
    final focusNode = FocusNode();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Layout do teclado: 3x4 grid
          // [1][2][3]
          // [4][5][6]
          // [7][8][9]
          // [⌫][0][✓]
          final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', '✓'];
          
          void handleKeyPress(String key) {
            if (key == '⌫') {
              if (enteredPassword.isNotEmpty) {
                setDialogState(() {
                  enteredPassword = enteredPassword.substring(0, enteredPassword.length - 1);
                  showError = false;
                });
              }
            } else if (key == '✓') {
              if (enteredPassword.length == 4) {
                _verifyPassword(ctx, settings, enteredPassword, setDialogState, (error) {
                  setDialogState(() {
                    showError = error;
                    if (error) enteredPassword = '';
                  });
                });
              }
            } else {
              if (enteredPassword.length < 4) {
                setDialogState(() {
                  enteredPassword += key;
                  showError = false;
                });
                // Auto-verifica quando completa 4 dígitos
                if (enteredPassword.length == 4) {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    _verifyPassword(ctx, settings, enteredPassword, setDialogState, (error) {
                      setDialogState(() {
                        showError = error;
                        if (error) enteredPassword = '';
                      });
                    });
                  });
                }
              }
            }
            HapticFeedback.selectionClick();
          }
          
          void handleNavigation(LogicalKeyboardKey key) {
            final col = focusedKey % 3;
            final row = focusedKey ~/ 3;
            
            if (key == LogicalKeyboardKey.arrowUp && row > 0) {
              setDialogState(() => focusedKey -= 3);
            } else if (key == LogicalKeyboardKey.arrowDown && row < 3) {
              setDialogState(() => focusedKey += 3);
            } else if (key == LogicalKeyboardKey.arrowLeft && col > 0) {
              setDialogState(() => focusedKey--);
            } else if (key == LogicalKeyboardKey.arrowRight && col < 2) {
              setDialogState(() => focusedKey++);
            } else if (key == LogicalKeyboardKey.select ||
                       key == LogicalKeyboardKey.enter ||
                       key == LogicalKeyboardKey.gameButtonA) {
              handleKeyPress(keys[focusedKey]);
            } else if (key == LogicalKeyboardKey.escape ||
                       key == LogicalKeyboardKey.goBack ||
                       key == LogicalKeyboardKey.gameButtonB) {
              Navigator.of(ctx).pop();
            }
            HapticFeedback.selectionClick();
          }
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            focusNode.requestFocus();
          });
          
          return KeyboardListener(
            focusNode: focusNode,
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
                handleNavigation(event.logicalKey);
              }
            },
            child: AlertDialog(
              backgroundColor: SaimoTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: settings.adultModeEnabled 
                          ? Colors.green.withOpacity(0.2) 
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      settings.adultModeEnabled ? Icons.lock_open : Icons.lock,
                      color: settings.adultModeEnabled ? Colors.green : Colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.adultModeEnabled ? 'Desativar +18' : 'Ativar +18',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Digite a senha: 1234',
                          style: TextStyle(color: SaimoTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  // Indicador de PIN
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final isFilled = i < enteredPassword.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: isFilled ? SaimoTheme.primary.withOpacity(0.2) : SaimoTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: showError 
                                ? Colors.red 
                                : (isFilled ? SaimoTheme.primary : Colors.transparent),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: isFilled 
                              ? const Icon(Icons.circle, color: SaimoTheme.primary, size: 16)
                              : null,
                        ),
                      );
                    }),
                  ),
                  if (showError)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Senha incorreta!', style: TextStyle(color: Colors.red, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  // Teclado numérico com navegação D-Pad
                  SizedBox(
                    width: 240,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.3,
                      ),
                      itemCount: 12,
                      itemBuilder: (ctx, index) {
                        final key = keys[index];
                        final isFocused = focusedKey == index;
                        final isSpecial = key == '⌫' || key == '✓';
                        
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isFocused 
                                ? (key == '✓' ? Colors.green : SaimoTheme.primary)
                                : (isSpecial ? SaimoTheme.surfaceLight : SaimoTheme.card),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFocused ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isFocused ? [
                              BoxShadow(
                                color: (key == '✓' ? Colors.green : SaimoTheme.primary).withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ] : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => handleKeyPress(key),
                              child: Center(
                                child: key == '⌫'
                                    ? Icon(Icons.backspace_outlined, 
                                        color: isFocused ? Colors.white : Colors.red, size: 24)
                                    : key == '✓'
                                        ? Icon(Icons.check, 
                                            color: Colors.white, size: 28)
                                        : Text(
                                            key,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Botão cancelar
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(color: SaimoTheme.textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  
  void _verifyPassword(
    BuildContext dialogContext,
    SettingsProvider settings,
    String password,
    StateSetter setDialogState,
    Function(bool) onError,
  ) {
    const correctPassword = '1234';
    
    if (password == correctPassword) {
      // Senha correta!
      Navigator.of(dialogContext).pop();
      
      // Alterna o modo adulto
      final newState = !settings.adultModeEnabled;
      settings.setAdultModeEnabled(newState);
      context.read<ChannelsProvider>().setAdultMode(newState);
      context.read<LazyMoviesProvider>().setAdultMode(newState);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newState ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(newState 
                  ? '🔓 Canais adultos visíveis!' 
                  : '🔒 Canais adultos ocultos!'),
            ],
          ),
          backgroundColor: newState ? Colors.red : SaimoTheme.success,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      // Senha incorreta
      onError(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _mainFocusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: SaimoTheme.background,
        body: SafeArea(
          child: Row(
            children: [
              // Sidebar
              _buildSidebar(),
              
              // Conteúdo principal
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: SaimoTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SaimoTheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.settings, color: SaimoTheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configurações',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Personalize o app',
                      style: TextStyle(
                        color: SaimoTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const Divider(color: SaimoTheme.surfaceLight, height: 1),
          
          // Instruções de navegação
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Navegação',
                    style: TextStyle(
                      color: SaimoTheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildNavHelp(Icons.keyboard_arrow_up, 'Cima/Baixo', 'Navegar'),
                  _buildNavHelp(Icons.keyboard_arrow_left, 'Esq/Dir', 'Ajustar valor'),
                  _buildNavHelp(Icons.circle, 'OK/Enter', 'Selecionar'),
                  _buildNavHelp(Icons.arrow_back, 'Voltar', 'Sair'),
                ],
              ),
            ),
          ),
          
          // Logo
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: SaimoTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.live_tv, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 12),
                const Text(
                  'SAIMO TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavHelp(IconData icon, String key, String action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: SaimoTheme.surfaceLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: Colors.white70, size: 16),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                action,
                style: const TextStyle(
                  color: SaimoTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(32),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            return _buildItemTile(index, settings);
          },
        );
      },
    );
  }

  Widget _buildItemTile(int itemIndex, SettingsProvider settings) {
    if (itemIndex >= _items.length) return const SizedBox.shrink();
    
    final item = _items[itemIndex];
    final isSelected = _selectedIndex == itemIndex;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = itemIndex;
        });
        _handleSelect();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? SaimoTheme.primary.withOpacity(0.15) : SaimoTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? SaimoTheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: SaimoTheme.primary.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: _buildItemContent(item, settings, isSelected),
      ),
    );
  }

  Widget _buildItemContent(_SettingItem item, SettingsProvider settings, bool isSelected) {
    switch (item.type) {
      case _ItemType.toggle:
        return _buildToggleTile(item, settings, isSelected);
      case _ItemType.dropdown:
        return _buildDropdownTile(item, settings, isSelected);
      case _ItemType.slider:
        return _buildSliderTile(item, settings, isSelected);
      case _ItemType.action:
        return _buildActionTile(item, isSelected);
      case _ItemType.info:
        return _buildInfoTile(item, isSelected);
      case _ItemType.special:
        return _buildAdultTile(settings, isSelected);
    }
  }

  Widget _buildToggleTile(_SettingItem item, SettingsProvider settings, bool isSelected) {
    bool value = false;
    switch (item.id) {
      case 'autoPlay':
        value = settings.autoPlay;
        break;
      case 'showEpg':
        value = settings.showEpg;
        break;
      case 'enableSubtitles':
        value = settings.enableSubtitles;
        break;
    }
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        value ? Icons.toggle_on : Icons.toggle_off,
        color: value ? SaimoTheme.primary : SaimoTheme.textSecondary,
        size: 32,
      ),
      title: Text(
        item.title,
        style: TextStyle(
          color: isSelected ? Colors.white : SaimoTheme.textPrimary,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        style: TextStyle(
          color: isSelected ? Colors.white70 : SaimoTheme.textTertiary,
          fontSize: 13,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: null,
        activeColor: SaimoTheme.primary,
      ),
    );
  }

  Widget _buildDropdownTile(_SettingItem item, SettingsProvider settings, bool isSelected) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        Icons.high_quality,
        color: isSelected ? SaimoTheme.primary : SaimoTheme.textSecondary,
        size: 28,
      ),
      title: Text(
        item.title,
        style: TextStyle(
          color: isSelected ? Colors.white : SaimoTheme.textPrimary,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        isSelected ? '← Use as setas para alterar →' : 'Qualidade: ${settings.preferredQuality.toUpperCase()}',
        style: TextStyle(
          color: isSelected ? SaimoTheme.primary : SaimoTheme.textTertiary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SaimoTheme.surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          settings.preferredQuality.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTile(_SettingItem item, SettingsProvider settings, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_up,
                color: isSelected ? SaimoTheme.primary : SaimoTheme.textSecondary,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : SaimoTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${(settings.volume * 100).round()}%',
                style: TextStyle(
                  color: isSelected ? SaimoTheme.primary : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.volume_mute, color: SaimoTheme.textTertiary, size: 18),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: settings.volume,
                    onChanged: null,
                    activeColor: isSelected ? SaimoTheme.primary : SaimoTheme.textSecondary,
                    inactiveColor: SaimoTheme.surfaceLight,
                  ),
                ),
              ),
              const Icon(Icons.volume_up, color: SaimoTheme.textTertiary, size: 18),
            ],
          ),
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '← Use as setas para ajustar →',
                style: TextStyle(
                  color: SaimoTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionTile(_SettingItem item, bool isSelected) {
    IconData icon;
    Color iconColor;
    
    switch (item.id) {
      case 'clearFavorites':
        icon = Icons.star_border;
        iconColor = Colors.amber;
        break;
      case 'resetSettings':
        icon = Icons.refresh;
        iconColor = Colors.orange;
        break;
      case 'back':
        icon = Icons.arrow_back;
        iconColor = SaimoTheme.primary;
        break;
      default:
        icon = Icons.settings;
        iconColor = SaimoTheme.textSecondary;
    }
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        icon,
        color: isSelected ? iconColor : SaimoTheme.textSecondary,
        size: 28,
      ),
      title: Text(
        item.title,
        style: TextStyle(
          color: isSelected ? Colors.white : SaimoTheme.textPrimary,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        style: TextStyle(
          color: isSelected ? Colors.white70 : SaimoTheme.textTertiary,
          fontSize: 13,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isSelected ? SaimoTheme.primary : SaimoTheme.textTertiary,
      ),
    );
  }

  Widget _buildInfoTile(_SettingItem item, bool isSelected) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        Icons.info_outline,
        color: isSelected ? SaimoTheme.primary : SaimoTheme.textSecondary,
        size: 28,
      ),
      title: Text(
        item.title,
        style: TextStyle(
          color: isSelected ? Colors.white : SaimoTheme.textPrimary,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: Text(
        item.subtitle,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAdultTile(SettingsProvider settings, bool isSelected) {
    final isUnlocked = settings.adultModeUnlocked;
    final isEnabled = settings.adultModeEnabled;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isUnlocked ? Colors.red : Colors.grey).withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isUnlocked ? Icons.eighteen_mp_rounded : Icons.lock_outline,
          color: isUnlocked ? Colors.red : Colors.grey,
          size: 24,
        ),
      ),
      title: Row(
        children: [
          const Text(
            'Canais Adultos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isUnlocked) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '✓',
                style: TextStyle(color: Colors.green, fontSize: 10),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        isUnlocked 
            ? (isEnabled ? 'Visíveis' : 'Ocultos')
            : 'Pressione OK para desbloquear (${settings.secretClickCount}/15)',
        style: TextStyle(
          color: isSelected ? Colors.white70 : SaimoTheme.textTertiary,
          fontSize: 13,
        ),
      ),
      trailing: isUnlocked
          ? Switch(
              value: isEnabled,
              onChanged: null,
              activeColor: Colors.red,
            )
          : Icon(
              Icons.chevron_right,
              color: isSelected ? Colors.red : SaimoTheme.textTertiary,
            ),
    );
  }

  void _confirmClearFavorites() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SaimoTheme.surface,
        title: const Text(
          'Limpar Favoritos',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Tem certeza que deseja remover todos os canais favoritos?',
          style: TextStyle(color: SaimoTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<FavoritesProvider>().clearFavorites();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Favoritos removidos'),
                  backgroundColor: SaimoTheme.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: SaimoTheme.error),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  void _confirmResetSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SaimoTheme.surface,
        title: const Text(
          'Resetar Configurações',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Tem certeza que deseja restaurar todas as configurações para o padrão?',
          style: TextStyle(color: SaimoTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<SettingsProvider>().resetSettings();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Configurações restauradas'),
                  backgroundColor: SaimoTheme.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: SaimoTheme.warning),
            child: const Text('Resetar'),
          ),
        ],
      ),
    );
  }
}

enum _ItemType { toggle, dropdown, slider, action, info, special }

class _SettingItem {
  final _ItemType type;
  final String id;
  final String title;
  final String subtitle;

  _SettingItem({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
  });
}
