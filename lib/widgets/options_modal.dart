import 'dart:ui';
import 'dart:async'; // Add this import for Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/casting_service.dart';
import 'package:provider/provider.dart';

class OptionsModal extends StatefulWidget {
  final String title;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final Function(CastDevice) onCastSelected;
  final VoidCallback? onPlay;
  final VoidCallback? onOpenGuide;

  const OptionsModal({
    super.key,
    required this.title,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onCastSelected,
    this.onPlay,
    this.onOpenGuide,
  });

  @override
  State<OptionsModal> createState() => _OptionsModalState();
}

class _OptionsModalState extends State<OptionsModal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  
  // 0: Play (if available), 1: Favorite, 2: Cast
  int _focusedIndex = 0;
  List<CastDevice> _devices = [];
  bool _searchingDevices = false;
  final FocusNode _focusNode = FocusNode();
  
  // Cast device list focus
  int _focusedDeviceIndex = 0;
  bool _deviceListFocused = false;

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.onPlay != null ? 0 : 1;
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    // Start searching devices
    _startDeviceDiscovery();
  }

  void _startDeviceDiscovery() {
    setState(() => _searchingDevices = true);
    final castingService = CastingService();
    castingService.startDiscovery();
    castingService.addListener(_onDevicesChanged);
  }

  void _onDevicesChanged() {
    if (mounted) {
      setState(() {
        _devices = CastingService().devices;
        _searchingDevices = CastingService().isScanning;
      });
    }
  }

  @override
  void dispose() {
    CastingService().removeListener(_onDevicesChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _closeModal() {
    _controller.reverse().then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _closeModal();
      return;
    }

    if (_deviceListFocused) {
      _handleDeviceListKey(key);
    } else {
      _handleMenuKey(key);
    }
  }

  void _handleMenuKey(LogicalKeyboardKey key) {
    final hasPlay = widget.onPlay != null;
    final hasGuide = widget.onOpenGuide != null;
    final maxIndex = 4; // 0:Play, 1:Fav, 2:Guide, 3:Cast, 4:Cancel

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
         if (_focusedIndex < maxIndex) _focusedIndex++;
         // Pula play se não tiver
         if (!hasPlay && _focusedIndex == 0) _focusedIndex = 1;
         // Pula guide se não tiver (mas sempre terá no player)
         if (!hasGuide && _focusedIndex == 2) _focusedIndex = 3;
      });
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
         if (_focusedIndex > 0) _focusedIndex--;
         if (!hasGuide && _focusedIndex == 2) _focusedIndex = 1;
         if (!hasPlay && _focusedIndex == 0) _focusedIndex = 1; // Fav é o primeiro se não tem play
      });
      HapticFeedback.selectionClick();
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.numpadEnter) {
      _selectOption();
    } else if (key == LogicalKeyboardKey.arrowRight && _focusedIndex == 3 && _devices.isNotEmpty) {
      // Allow entering cast list with Right arrow too
      setState(() {
          _deviceListFocused = true;
          _focusedDeviceIndex = 0;
      });
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _closeModal();
    }
  }

  void _handleDeviceListKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_focusedDeviceIndex < _devices.length - 1) {
        setState(() => _focusedDeviceIndex++);
        HapticFeedback.selectionClick();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_focusedDeviceIndex > 0) {
        setState(() => _focusedDeviceIndex--);
        HapticFeedback.selectionClick();
      } else {
        setState(() => _deviceListFocused = false); // Back to menu
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
       setState(() => _deviceListFocused = false);
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.numpadEnter) {
      if (_devices.isNotEmpty) {
        final device = _devices[_focusedDeviceIndex];
        _controller.reverse().then((_) {
           Navigator.pop(context);
           widget.onCastSelected(device);
        });
      }
    }
  }

  void _selectOption() {
    if (_focusedIndex == 0 && widget.onPlay != null) {
      _closeModal();
      // Use a small delay to ensure modal is closed before playing? 
      // Actually _closeModal calls pop then finishes. We should call onPlay AFTER pop?
      // But _closeModal is async animation. 
      // Let's pass closure to _closeModal or just run parallel.
      // Better:
       Future.delayed(const Duration(milliseconds: 300), () {
         widget.onPlay!();
       });
    } else if (_focusedIndex == 1) {
      widget.onToggleFavorite();
      setState(() {}); 
    } else if (_focusedIndex == 2 && widget.onOpenGuide != null) {
      // Guia de TV
      _closeModal();
      Future.delayed(const Duration(milliseconds: 300), () {
        widget.onOpenGuide!();
      });
    } else if (_focusedIndex == 3) {
      // Cast
      if (_devices.isEmpty && !_searchingDevices) {
         CastingService().startDiscovery();
      }
      if (_devices.isNotEmpty) {
        setState(() {
          _deviceListFocused = true;
          _focusedDeviceIndex = 0;
        });
      }
    } else if (_focusedIndex == 4) {
      // Cancelar
      _closeModal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          // Blurred Background
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeModal,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withOpacity(0.4),
                ),
              ),
            ),
          ),
          
          // Right Side Panel
          Align(
            alignment: Alignment.centerRight,
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                width: 400,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: SaimoTheme.surface.withOpacity(0.95), // Slightly transparent
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30,
                      offset: const Offset(-5, 0),
                    ),
                  ],
                  border: const Border(left: BorderSide(color: Colors.white12, width: 1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(30, 60, 30, 30),
                      color: Colors.black12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OPÇÕES',
                            style: TextStyle(
                              color: SaimoTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Menu Items
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                        children: [
                          if (widget.onPlay != null)
                            _buildMenuItem(
                              index: 0,
                              icon: Icons.play_arrow_rounded,
                              label: 'Assistir Agora',
                              subtitle: 'Reproduzir no dispositivo atual',
                            ),
                          
                          _buildMenuItem(
                            index: 1,
                            icon: widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                            label: widget.isFavorite ? 'Remover dos Favoritos' : 'Adicionar aos Favoritos',

                            isActive: widget.isFavorite,
                          ),

                          if (widget.onOpenGuide != null)
                             _buildMenuItem(
                               index: 2,
                               icon: Icons.list_alt_rounded,
                               label: 'Abrir Guia de TV',
                             ),

                          const Divider(color: Colors.white10, height: 40),

                          _buildMenuItem(
                            index: 3,
                            icon: Icons.cast_connected_rounded,
                            label: 'Transmitir',
                            subtitle: _devices.isEmpty 
                                ? (_searchingDevices ? 'Procurando dispositivos...' : 'Nenhum dispositivo encontrado') 
                                : '${_devices.length} dispositivos encontrados',
                            showChevron: true,
                          ),
                          
                          // Expanded Cast List
                          if ((_focusedIndex == 3 || _deviceListFocused) && _devices.isNotEmpty)
                             _buildCastList(),

                          const Divider(color: Colors.white10, height: 40),

                          _buildMenuItem(
                            index: 4,
                            icon: Icons.close_rounded,
                            label: 'Cancelar',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
    String? subtitle,
    bool isActive = false,
    bool showChevron = false,
  }) {
    final isFocused = !_deviceListFocused && _focusedIndex == index;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isFocused ? SaimoTheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFocused ? SaimoTheme.primary : Colors.white10,
          width: 1,
        ),
        boxShadow: isFocused ? [
          BoxShadow(
             color: SaimoTheme.primary.withOpacity(0.4),
             blurRadius: 12,
             offset: const Offset(0, 4),
          )
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _focusedIndex = index);
            _selectOption();
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isFocused ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isFocused ? Colors.white : (isActive ? SaimoTheme.primary : Colors.white70),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isFocused ? Colors.white : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: isFocused ? Colors.white70 : Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showChevron)
                   Icon(
                     _deviceListFocused ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_right_rounded,
                     color: isFocused ? Colors.white : Colors.white24,
                   ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCastList() {
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: _devices.asMap().entries.map((entry) {
          final index = entry.key;
          final device = entry.value;
          final isFocused = _deviceListFocused && _focusedDeviceIndex == index;
          
          return Container(
            color: isFocused ? Colors.white.withOpacity(0.1) : Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(
                device.type == CastDeviceType.chromecast 
                    ? Icons.cast_connected_rounded 
                    : (device.type == CastDeviceType.fireTv ? Icons.local_fire_department : Icons.tv_rounded),
                color: isFocused ? SaimoTheme.primary : Colors.white54,
                size: 20,
              ),
              title: Text(
                device.name,
                style: TextStyle(
                  color: isFocused ? Colors.white : Colors.white70,
                  fontSize: 14,
                  fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: isFocused ? const Icon(Icons.check_circle_outline, color: SaimoTheme.primary, size: 16) : null,
              onTap: () => widget.onCastSelected(device),
            ),
          );
        }).toList(),
      ),
    );
  }
}
