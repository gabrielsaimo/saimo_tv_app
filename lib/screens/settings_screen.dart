import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/channels_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/lazy_movies_provider.dart';
import '../services/json_catalog_service.dart';
import '../utils/theme.dart';
import '../utils/tv_constants.dart';

/// Tela de Configurações Redesenhada - Design moderno e compacto
/// Otimizada para TV com navegação D-Pad fluida
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  final FocusNode _mainFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  int _selectedSection = 0;
  int _selectedItem = 0;
  
  // Seções organizadas por categoria
  final List<_SettingsSection> _sections = [
    _SettingsSection(
      title: 'Reprodução',
      icon: Icons.play_circle_outline_rounded,
      items: [
        _SettingItem(id: 'autoPlay', title: 'Reprodução Automática', type: _ItemType.toggle),
        _SettingItem(id: 'preferredQuality', title: 'Qualidade', type: _ItemType.selector),
        _SettingItem(id: 'volume', title: 'Volume Padrão', type: _ItemType.slider),
      ],
    ),
    _SettingsSection(
      title: 'Interface',
      icon: Icons.palette_outlined,
      items: [
        _SettingItem(id: 'showEpg', title: 'Mostrar Programação (EPG)', type: _ItemType.toggle),
        _SettingItem(id: 'enableSubtitles', title: 'Legendas Automáticas', type: _ItemType.toggle),
      ],
    ),
    _SettingsSection(
      title: 'Controle Parental',
      icon: Icons.security_rounded,
      items: [
        _SettingItem(id: 'adultMode', title: 'Canais Adultos (+18)', type: _ItemType.locked),
      ],
    ),
    _SettingsSection(
      title: 'Dados',
      icon: Icons.storage_rounded,
      items: [
        _SettingItem(id: 'refreshCatalog', title: 'Atualizar Catálogo', type: _ItemType.action),
        _SettingItem(id: 'clearFavorites', title: 'Limpar Favoritos', type: _ItemType.action),
        _SettingItem(id: 'resetSettings', title: 'Restaurar Padrões', type: _ItemType.action),
      ],
    ),
    _SettingsSection(
      title: 'Sobre',
      icon: Icons.info_outline_rounded,
      items: [
        _SettingItem(id: 'version', title: 'Versão 11.0.0', type: _ItemType.info),
      ],
    ),
  ];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  int get _totalItems => _sections.fold(0, (sum, s) => sum + s.items.length);
  
  _SettingItem? get _currentItem {
    int count = 0;
    for (final section in _sections) {
      if (_selectedSection < _sections.indexOf(section) + 1) {
        final idx = _selectedItem;
        if (idx < section.items.length) {
          return section.items[idx];
        }
      }
    }
    return null;
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    
    if (key == LogicalKeyboardKey.escape || 
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      final section = _sections[_selectedSection];
      
      if (key == LogicalKeyboardKey.arrowUp) {
        HapticFeedback.selectionClick();
        if (_selectedItem > 0) {
          _selectedItem--;
        } else if (_selectedSection > 0) {
          _selectedSection--;
          _selectedItem = _sections[_selectedSection].items.length - 1;
        }
        _scrollToSelected();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        HapticFeedback.selectionClick();
        if (_selectedItem < section.items.length - 1) {
          _selectedItem++;
        } else if (_selectedSection < _sections.length - 1) {
          _selectedSection++;
          _selectedItem = 0;
        }
        _scrollToSelected();
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        HapticFeedback.selectionClick();
        _handleLeftRight(-1);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        HapticFeedback.selectionClick();
        _handleLeftRight(1);
      } else if (key == LogicalKeyboardKey.select ||
                 key == LogicalKeyboardKey.enter ||
                 key == LogicalKeyboardKey.gameButtonA) {
        HapticFeedback.mediumImpact();
        _handleSelect();
      }
    });
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    
    // Calcula offset aproximado
    double offset = 0;
    for (int i = 0; i < _selectedSection; i++) {
      offset += 60 + (_sections[i].items.length * 64); // header + items
    }
    offset += 60 + (_selectedItem * 64);
    
    final screenHeight = MediaQuery.of(context).size.height;
    final targetOffset = (offset - screenHeight / 2 + 32).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _handleLeftRight(int direction) {
    final section = _sections[_selectedSection];
    final item = section.items[_selectedItem];
    final settings = context.read<SettingsProvider>();
    
    if (item.id == 'volume') {
      final newVolume = (settings.volume + direction * 0.1).clamp(0.0, 1.0);
      settings.setVolume(newVolume);
    } else if (item.id == 'preferredQuality') {
      final options = ['auto', '1080p', '720p', '480p', '360p'];
      final currentIndex = options.indexOf(settings.preferredQuality);
      final newIndex = (currentIndex + direction).clamp(0, options.length - 1);
      settings.setPreferredQuality(options[newIndex]);
    }
  }

  void _handleSelect() {
    final section = _sections[_selectedSection];
    final item = section.items[_selectedItem];
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
        _showPasswordDialog(settings);
        break;
      case 'refreshCatalog':
        _refreshCatalog();
        break;
      case 'clearFavorites':
        _confirmClearFavorites();
        break;
      case 'resetSettings':
        _confirmResetSettings();
        break;
    }
  }

  void _refreshCatalog() async {
    _showSnackBar('Atualizando catálogo...', Icons.refresh);
    
    try {
      // Clear local catalog cache
      final catalogService = JsonCatalogService();
      await catalogService.clearLocalCache();
      
      // Reload movies provider
      if (mounted) {
        final moviesProvider = context.read<LazyMoviesProvider>();
        await moviesProvider.initialize(); // Force reload
        
        _showSnackBar('Catálogo atualizado!', Icons.check_circle);
      }
    } catch (e) {
      debugPrint('Erro ao atualizar catálogo: $e');
      if (mounted) {
        _showSnackBar('Erro ao atualizar', Icons.error);
      }
    }
  }

  void _confirmClearFavorites() {
    showDialog(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Limpar Favoritos',
        message: 'Remover todos os favoritos salvos?',
        icon: Icons.favorite_outline,
        iconColor: Colors.pink,
        onConfirm: () {
          context.read<FavoritesProvider>().clearFavorites();
          Navigator.pop(ctx);
          _showSnackBar('Favoritos removidos', Icons.check);
        },
      ),
    );
  }

  void _confirmResetSettings() {
    showDialog(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Restaurar Padrões',
        message: 'Todas as configurações serão resetadas.',
        icon: Icons.restart_alt_rounded,
        iconColor: Colors.orange,
        onConfirm: () {
          context.read<SettingsProvider>().resetSettings();
          Navigator.pop(ctx);
          _showSnackBar('Configurações restauradas', Icons.check);
        },
      ),
    );
  }

  void _showSnackBar(String message, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: SaimoTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showPasswordDialog(SettingsProvider settings) {
    String enteredPassword = '';
    bool showError = false;
    int focusedKey = 4;
    final focusNode = FocusNode();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
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
            child: Dialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: settings.adultModeEnabled 
                              ? [Colors.green.withOpacity(0.2), Colors.green.withOpacity(0.1)]
                              : [Colors.red.withOpacity(0.2), Colors.red.withOpacity(0.1)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        settings.adultModeEnabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                        color: settings.adultModeEnabled ? Colors.green : Colors.red,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      settings.adultModeEnabled ? 'Desativar +18' : 'Ativar +18',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Digite a senha: 1234',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    
                    // PIN Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final isFilled = i < enteredPassword.length;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 48,
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: isFilled 
                                ? SaimoTheme.primary.withOpacity(0.2) 
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: showError 
                                  ? Colors.red 
                                  : (isFilled ? SaimoTheme.primary : Colors.white.withOpacity(0.1)),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: isFilled 
                                ? Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: SaimoTheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ),
                    
                    if (showError) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red, size: 16),
                            SizedBox(width: 8),
                            Text('Senha incorreta', style: TextStyle(color: Colors.red, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Numeric Keypad
                    SizedBox(
                      width: 220,
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: 12,
                        itemBuilder: (ctx, index) {
                          final key = keys[index];
                          final isFocused = focusedKey == index;
                          final isSpecial = key == '⌫' || key == '✓';
                          
                          Color bgColor;
                          if (isFocused) {
                            bgColor = key == '✓' ? Colors.green : SaimoTheme.primary;
                          } else if (isSpecial) {
                            bgColor = Colors.white.withOpacity(0.05);
                          } else {
                            bgColor = Colors.white.withOpacity(0.08);
                          }
                          
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isFocused ? Colors.white : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => handleKeyPress(key),
                                child: Center(
                                  child: key == '⌫'
                                      ? Icon(Icons.backspace_outlined, 
                                          color: isFocused ? Colors.white : Colors.red[400], size: 22)
                                      : key == '✓'
                                          ? Icon(Icons.check_rounded, 
                                              color: Colors.white, size: 26)
                                          : Text(
                                              key,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w600,
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
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ),
                  ],
                ),
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
      Navigator.of(dialogContext).pop();
      
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
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      onError(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 600;
    
    return KeyboardListener(
      focusNode: _mainFocusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: SafeArea(
          child: isCompact ? _buildCompactLayout() : _buildWideLayout(),
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            border: Border(
              right: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: SaimoTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.settings_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configurações',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Personalize seu app',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Divider(color: Colors.white.withOpacity(0.05), height: 1),
              
              // Navigation hints
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NAVEGAÇÃO',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildNavHint('↑↓', 'Navegar'),
                      _buildNavHint('←→', 'Ajustar valor'),
                      _buildNavHint('OK', 'Selecionar'),
                      _buildNavHint('⏎', 'Voltar'),
                    ],
                  ),
                ),
              ),
              
              // Logo
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: SaimoTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SAIMO TV',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'v11.0.0',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Content
        Expanded(
          child: _buildSettingsList(),
        ),
      ],
    );
  }

  Widget _buildCompactLayout() {
    return Column(
      children: [
        // Header compacto
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Configurações',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // Content
        Expanded(
          child: _buildSettingsList(),
        ),
      ],
    );
  }

  Widget _buildSettingsList() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          itemCount: _sections.length,
          itemBuilder: (context, sectionIndex) {
            final section = _sections[sectionIndex];
            final isSectionSelected = _selectedSection == sectionIndex;
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section header
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 8),
                  child: Row(
                    children: [
                      Icon(
                        section.icon,
                        color: isSectionSelected ? SaimoTheme.primary : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        section.title.toUpperCase(),
                        style: TextStyle(
                          color: isSectionSelected ? SaimoTheme.primary : Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Section items
                ...section.items.asMap().entries.map((entry) {
                  final itemIndex = entry.key;
                  final item = entry.value;
                  final isSelected = isSectionSelected && _selectedItem == itemIndex;
                  
                  return _buildSettingTile(item, settings, isSelected);
                }),
                
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingTile(_SettingItem item, SettingsProvider settings, bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected 
            ? SaimoTheme.primary.withOpacity(0.12) 
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? SaimoTheme.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: SaimoTheme.primary.withOpacity(0.2),
            blurRadius: 12,
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedSection = _sections.indexWhere((s) => s.items.contains(item));
              _selectedItem = _sections[_selectedSection].items.indexOf(item);
            });
            _handleSelect();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                _buildItemControl(item, settings, isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemControl(_SettingItem item, SettingsProvider settings, bool isSelected) {
    switch (item.type) {
      case _ItemType.toggle:
        bool value = false;
        if (item.id == 'autoPlay') value = settings.autoPlay;
        if (item.id == 'showEpg') value = settings.showEpg;
        if (item.id == 'enableSubtitles') value = settings.enableSubtitles;
        
        return Container(
          width: 48,
          height: 28,
          decoration: BoxDecoration(
            color: value ? SaimoTheme.primary : Colors.grey[800],
            borderRadius: BorderRadius.circular(14),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
        
      case _ItemType.selector:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) 
                const Icon(Icons.chevron_left_rounded, color: Colors.grey, size: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  settings.preferredQuality.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? SaimoTheme.primary : Colors.grey[400],
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isSelected) 
                const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 16),
            ],
          ),
        );
        
      case _ItemType.slider:
        return SizedBox(
          width: 120,
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: settings.volume,
                    backgroundColor: Colors.grey[800],
                    valueColor: AlwaysStoppedAnimation(
                      isSelected ? SaimoTheme.primary : Colors.grey[600],
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(settings.volume * 100).toInt()}%',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
        
      case _ItemType.locked:
        final isEnabled = settings.adultModeEnabled;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isEnabled 
                ? Colors.green.withOpacity(0.15) 
                : Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isEnabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: isEnabled ? Colors.green : Colors.red,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                isEnabled ? 'Ativo' : 'Bloqueado',
                style: TextStyle(
                  color: isEnabled ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
        
      case _ItemType.action:
        return Icon(
          Icons.chevron_right_rounded,
          color: isSelected ? SaimoTheme.primary : Colors.grey[600],
          size: 20,
        );
        
      case _ItemType.info:
        return const SizedBox.shrink();
    }
  }

  Widget _buildNavHint(String key, String action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                key,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            action,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// === Models ===

class _SettingsSection {
  final String title;
  final IconData icon;
  final List<_SettingItem> items;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _SettingItem {
  final String id;
  final String title;
  final _ItemType type;

  const _SettingItem({
    required this.id,
    required this.title,
    required this.type,
  });
}

enum _ItemType {
  toggle,
  selector,
  slider,
  locked,
  action,
  info,
}

// === Confirm Dialog ===

class _ConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onConfirm,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  int _focusedButton = 0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() => _focusedButton = _focusedButton == 0 ? 1 : 0);
          HapticFeedback.selectionClick();
        } else if (event.logicalKey == LogicalKeyboardKey.select ||
                   event.logicalKey == LogicalKeyboardKey.enter) {
          HapticFeedback.mediumImpact();
          if (_focusedButton == 0) {
            Navigator.pop(context);
          } else {
            widget.onConfirm();
          }
        } else if (event.logicalKey == LogicalKeyboardKey.escape ||
                   event.logicalKey == LogicalKeyboardKey.goBack) {
          Navigator.pop(context);
        }
      },
      child: Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.iconColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.message,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildButton(
                      label: 'Cancelar',
                      isFocused: _focusedButton == 0,
                      isPrimary: false,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildButton(
                      label: 'Confirmar',
                      isFocused: _focusedButton == 1,
                      isPrimary: true,
                      onTap: widget.onConfirm,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required bool isFocused,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary 
              ? (isFocused ? SaimoTheme.primary : SaimoTheme.primary.withOpacity(0.7))
              : (isFocused ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
