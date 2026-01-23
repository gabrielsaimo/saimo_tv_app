import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/lazy_movies_provider.dart';
import '../utils/tv_constants.dart';

/// Filtros avançados disponíveis
class AdvancedFilters {
  // Gêneros
  final Set<String> genres;
  
  // Ano
  final int? yearFrom;
  final int? yearTo;
  
  // Nota mínima (0-10)
  final double? minRating;
  
  // Classificação indicativa
  final String? certification;
  
  // Idioma original
  final String? language;
  
  // Duração (minutos)
  final int? minRuntime;
  final int? maxRuntime;
  
  // Ordenação
  final SortOption sortBy;
  final bool sortDescending;

  const AdvancedFilters({
    this.genres = const {},
    this.yearFrom,
    this.yearTo,
    this.minRating,
    this.certification,
    this.language,
    this.minRuntime,
    this.maxRuntime,
    this.sortBy = SortOption.name,
    this.sortDescending = false,
  });
  
  AdvancedFilters copyWith({
    Set<String>? genres,
    int? yearFrom,
    int? yearTo,
    double? minRating,
    String? certification,
    String? language,
    int? minRuntime,
    int? maxRuntime,
    SortOption? sortBy,
    bool? sortDescending,
    bool clearYearFrom = false,
    bool clearYearTo = false,
    bool clearMinRating = false,
    bool clearCertification = false,
    bool clearLanguage = false,
    bool clearMinRuntime = false,
    bool clearMaxRuntime = false,
  }) {
    return AdvancedFilters(
      genres: genres ?? this.genres,
      yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
      yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      certification: clearCertification ? null : (certification ?? this.certification),
      language: clearLanguage ? null : (language ?? this.language),
      minRuntime: clearMinRuntime ? null : (minRuntime ?? this.minRuntime),
      maxRuntime: clearMaxRuntime ? null : (maxRuntime ?? this.maxRuntime),
      sortBy: sortBy ?? this.sortBy,
      sortDescending: sortDescending ?? this.sortDescending,
    );
  }
  
  bool get hasFilters => 
      genres.isNotEmpty || 
      yearFrom != null || 
      yearTo != null || 
      minRating != null || 
      certification != null ||
      language != null ||
      minRuntime != null ||
      maxRuntime != null;
  
  int get filterCount {
    int count = 0;
    if (genres.isNotEmpty) count++;
    if (yearFrom != null || yearTo != null) count++;
    if (minRating != null) count++;
    if (certification != null) count++;
    if (language != null) count++;
    if (minRuntime != null || maxRuntime != null) count++;
    return count;
  }
  
  static const AdvancedFilters empty = AdvancedFilters();
}

enum SortOption {
  name,
  year,
  rating,
  popularity,
  runtime,
}

/// Modal de filtros avançados com design moderno
class AdvancedFiltersModal extends StatefulWidget {
  final AdvancedFilters currentFilters;
  final Function(AdvancedFilters) onApply;

  const AdvancedFiltersModal({
    super.key,
    required this.currentFilters,
    required this.onApply,
  });

  @override
  State<AdvancedFiltersModal> createState() => _AdvancedFiltersModalState();
}

class _AdvancedFiltersModalState extends State<AdvancedFiltersModal> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AdvancedFilters _filters;
  
  // Navegação: 0=gêneros, 1=ano, 2=nota, 3=classificação, 4=duração, 5=ordenação, 6=botões
  int _currentSection = 0;
  int _selectedItemIndex = 0;
  
  // Keys para scroll (7 seções)
  final List<GlobalKey> _sectionKeys = List.generate(7, (_) => GlobalKey());
  
  // Dados disponíveis (extraídos do catálogo)
  Set<String> _availableGenres = {};
  int _minYear = 1950;
  int _maxYear = DateTime.now().year;
  
  // Opções de ano
  final List<int?> _yearOptions = [null, 2026, 2025, 2024, 2023, 2022, 2021, 2020, 2015, 2010, 2000, 1990];
  
  // Opções de nota
  final List<double?> _ratingOptions = [null, 9.0, 8.0, 7.0, 6.0, 5.0];
  
  // Opções de classificação indicativa (fixas)
  final List<String> _certificationOptions = ['Todas', 'L', '10', '12', '14', '16', '18'];
  
  // Opções de duração (minutos)
  final List<int?> _runtimeOptions = [null, 60, 90, 120, 150, 180];

  @override
  void initState() {
    super.initState();
    _filters = widget.currentFilters;
    _loadAvailableOptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _loadAvailableOptions() {
    final provider = Provider.of<LazyMoviesProvider>(context, listen: false);
    
    // Coleta gêneros de todos os filmes carregados
    final genres = <String>{};
    
    for (final item in provider.displayItems) {
      final tmdb = item.movie?.tmdb ?? item.series?.tmdb;
      if (tmdb != null) {
        if (tmdb.genres != null) genres.addAll(tmdb.genres!);
      }
    }
    
    setState(() {
      _availableGenres = genres;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  void _scrollToSection(int section) {
    if (section < 0 || section >= _sectionKeys.length) return;
    final key = _sectionKeys[section];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      HapticFeedback.selectionClick();
      _navigateUp();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      HapticFeedback.selectionClick();
      _navigateDown();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      HapticFeedback.selectionClick();
      _navigateLeft();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      HapticFeedback.selectionClick();
      _navigateRight();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      HapticFeedback.mediumImpact();
      _handleSelect();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _navigateUp() {
    setState(() {
      if (_currentSection > 0) {
        _currentSection--;
        _selectedItemIndex = 0;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSection(_currentSection);
    });
  }

  void _navigateDown() {
    setState(() {
      if (_currentSection < 6) { // 0-5 são seções + 6 é botões
        _currentSection++;
        _selectedItemIndex = 0;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSection(_currentSection);
    });
  }

  void _navigateLeft() {
    setState(() {
      if (_selectedItemIndex > 0) {
        _selectedItemIndex--;
      }
    });
  }

  void _navigateRight() {
    setState(() {
      final maxIndex = _getMaxIndexForSection(_currentSection);
      if (_selectedItemIndex < maxIndex) {
        _selectedItemIndex++;
      }
    });
  }

  // Listas compactas para o novo layout
  List<int?> get _compactYearOptions => [null, 2025, 2024, 2023, 2020, 2015, 2010];
  List<double?> get _compactRatingOptions => [null, 8.0, 7.0, 6.0, 5.0];
  List<String> get _compactCertOptions => ['Todas', 'L', '10', '12', '14', '16', '18'];
  List<int?> get _compactRuntimeOptions => [null, 90, 120, 180];
  List<String> get _displayGenres => _availableGenres.toList()..sort();

  int _getMaxIndexForSection(int section) {
    switch (section) {
      case 0: return (_displayGenres.take(14).length - 1).clamp(0, 999); // Gêneros (max 14)
      case 1: return _compactYearOptions.length - 1; // Ano
      case 2: return _compactRatingOptions.length - 1; // Nota
      case 3: return _compactCertOptions.length - 1; // Classificação
      case 4: return _compactRuntimeOptions.length - 1; // Duração
      case 5: return SortOption.values.length - 1; // Ordenação
      case 6: return 2; // Botões (Limpar, Cancelar, Aplicar)
      default: return 0;
    }
  }

  void _handleSelect() {
    switch (_currentSection) {
      case 0: // Gêneros
        final genreList = _displayGenres.take(14).toList();
        if (genreList.isNotEmpty) {
          final genre = genreList[_selectedItemIndex.clamp(0, genreList.length - 1)];
          setState(() {
            final newGenres = Set<String>.from(_filters.genres);
            if (newGenres.contains(genre)) {
              newGenres.remove(genre);
            } else {
              newGenres.add(genre);
            }
            _filters = _filters.copyWith(genres: newGenres);
          });
        }
        break;
      case 1: // Ano
        final year = _compactYearOptions[_selectedItemIndex.clamp(0, _compactYearOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(yearFrom: year, clearYearFrom: year == null);
        });
        break;
      case 2: // Nota
        final rating = _compactRatingOptions[_selectedItemIndex.clamp(0, _compactRatingOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(minRating: rating, clearMinRating: rating == null);
        });
        break;
      case 3: // Classificação
        final cert = _compactCertOptions[_selectedItemIndex.clamp(0, _compactCertOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(
            certification: cert == 'Todas' ? null : cert,
            clearCertification: cert == 'Todas',
          );
        });
        break;
      case 4: // Duração
        final runtime = _compactRuntimeOptions[_selectedItemIndex.clamp(0, _compactRuntimeOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(maxRuntime: runtime, clearMaxRuntime: runtime == null);
        });
        break;
      case 5: // Ordenação
        final sort = SortOption.values[_selectedItemIndex.clamp(0, SortOption.values.length - 1)];
        setState(() {
          if (_filters.sortBy == sort) {
            // Toggle direção
            _filters = _filters.copyWith(sortDescending: !_filters.sortDescending);
          } else {
            _filters = _filters.copyWith(sortBy: sort);
          }
        });
        break;
      case 6: // Botões
        if (_selectedItemIndex == 0) {
          // Limpar
          setState(() => _filters = AdvancedFilters.empty);
        } else if (_selectedItemIndex == 1) {
          // Cancelar
          Navigator.of(context).pop();
        } else {
          // Aplicar
          widget.onApply(_filters);
          Navigator.of(context).pop();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Container(
          width: size.width * 0.92,
          constraints: BoxConstraints(maxHeight: size.height * 0.95),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF0F0F1A),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Linha 1: Gêneros (compacto)
                      Container(key: _sectionKeys[0], child: _buildCompactGenresSection()),
                      const SizedBox(height: 10),
                      // Linha 2: Ano, Nota, Classificação (3 colunas)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Container(key: _sectionKeys[1], child: _buildCompactYearSection())),
                          const SizedBox(width: 12),
                          Expanded(child: Container(key: _sectionKeys[2], child: _buildCompactRatingSection())),
                          const SizedBox(width: 12),
                          Expanded(child: Container(key: _sectionKeys[3], child: _buildCompactCertificationSection())),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Linha 3: Duração e Ordenação (2 colunas)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Container(key: _sectionKeys[4], child: _buildCompactRuntimeSection())),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: Container(key: _sectionKeys[5], child: _buildCompactSortSection())),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Botões
                      Container(key: _sectionKeys[6], child: _buildActionButtons()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE50914).withOpacity(0.2),
            Colors.transparent,
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE50914), Color(0xFFB20710)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'Filtros Avançados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_filters.hasFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_filters.filterCount} ativo${_filters.filterCount > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '↑↓ seção  ←→ item  OK seleciona',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE50914).withOpacity(0.2),
            Colors.transparent,
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE50914), Color(0xFFB20710)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filtros Avançados',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Refine sua busca com precisão',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_filters.hasFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_filters.filterCount} filtro${_filters.filterCount > 1 ? 's' : ''} ativo${_filters.filterCount > 1 ? 's' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, bool isFocused) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: isFocused ? const Color(0xFFE50914) : Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: isFocused ? Colors.white : Colors.white70,
              fontSize: 16,
              fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          if (isFocused) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '← → selecionar  •  OK confirmar',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactChip({
    required String label,
    required bool isSelected,
    required bool isFocused,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.symmetric(
          horizontal: isFocused ? 10 : 8,
          vertical: isFocused ? 5 : 4,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB20710)])
              : null,
          color: isSelected ? null : Colors.white.withOpacity(isFocused ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused
                ? const Color(0xFFFFD700)
                : isSelected
                    ? Colors.transparent
                    : Colors.white.withOpacity(0.2),
            width: isFocused ? 2 : 1,
          ),
          boxShadow: isFocused
              ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.3), blurRadius: 6)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: isSelected || isFocused ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactSectionTitle(String title, IconData icon, bool isFocused) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            icon,
            color: isFocused ? const Color(0xFFE50914) : Colors.white54,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: isFocused ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: isFocused ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactGenresSection() {
    final isFocused = _currentSection == 0;
    final genreList = _availableGenres.toList()..sort();
    // Mostrar apenas os 12 gêneros mais comuns para caber
    final displayGenres = genreList.take(14).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSectionTitle('Gêneros', Icons.category_rounded, isFocused),
        if (displayGenres.isEmpty)
          Text('Carregando...', style: TextStyle(color: Colors.white38, fontSize: 10))
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: displayGenres.asMap().entries.map((entry) {
              final index = entry.key;
              final genre = entry.value;
              final isSelected = _filters.genres.contains(genre);
              final isItemFocused = isFocused && _selectedItemIndex == index;
              return _buildCompactChip(
                label: genre,
                isSelected: isSelected,
                isFocused: isItemFocused,
                onTap: () {
                  setState(() {
                    _currentSection = 0;
                    _selectedItemIndex = index;
                    final newGenres = Set<String>.from(_filters.genres);
                    if (newGenres.contains(genre)) {
                      newGenres.remove(genre);
                    } else {
                      newGenres.add(genre);
                    }
                    _filters = _filters.copyWith(genres: newGenres);
                  });
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildCompactYearSection() {
    final isFocused = _currentSection == 1;
    final compactYearOptions = [null, 2025, 2024, 2023, 2020, 2015, 2010];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSectionTitle('Ano', Icons.calendar_today_rounded, isFocused),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: compactYearOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final year = entry.value;
            final label = year == null ? 'Todos' : '$year+';
            final isSelected = _filters.yearFrom == year;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildCompactChip(
              label: label,
              isSelected: isSelected,
              isFocused: isItemFocused,
              onTap: () {
                setState(() {
                  _currentSection = 1;
                  _selectedItemIndex = index;
                  _filters = _filters.copyWith(yearFrom: year, clearYearFrom: year == null);
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCompactRatingSection() {
    final isFocused = _currentSection == 2;
    final compactRatingOptions = [null, 8.0, 7.0, 6.0, 5.0];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSectionTitle('Nota', Icons.star_rounded, isFocused),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: compactRatingOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final rating = entry.value;
            final label = rating == null ? 'Todas' : '${rating.toInt()}+⭐';
            final isSelected = _filters.minRating == rating;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildCompactChip(
              label: label,
              isSelected: isSelected,
              isFocused: isItemFocused,
              onTap: () {
                setState(() {
                  _currentSection = 2;
                  _selectedItemIndex = index;
                  _filters = _filters.copyWith(minRating: rating, clearMinRating: rating == null);
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCompactCertificationSection() {
    final isFocused = _currentSection == 3;
    final compactCertOptions = ['Todas', 'L', '10', '12', '14', '16', '18'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSectionTitle('Classif.', Icons.child_care_rounded, isFocused),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: compactCertOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final cert = entry.value;
            final isSelected = cert == 'Todas'
                ? _filters.certification == null
                : _filters.certification == cert;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildCompactChip(
              label: cert,
              isSelected: isSelected,
              isFocused: isItemFocused,
              onTap: () {
                setState(() {
                  _currentSection = 3;
                  _selectedItemIndex = index;
                  _filters = _filters.copyWith(
                    certification: cert == 'Todas' ? null : cert,
                    clearCertification: cert == 'Todas',
                  );
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCompactRuntimeSection() {
    final isFocused = _currentSection == 4;
    final compactRuntimeOptions = [null, 90, 120, 180];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSectionTitle('Duração', Icons.timer_rounded, isFocused),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: compactRuntimeOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final runtime = entry.value;
            final label = runtime == null
                ? 'Qualquer'
                : runtime < 60
                    ? '${runtime}m'
                    : '${runtime ~/ 60}h${runtime % 60 > 0 ? '${runtime % 60}m' : ''}';
            final isSelected = _filters.maxRuntime == runtime;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildCompactChip(
              label: label,
              isSelected: isSelected,
              isFocused: isItemFocused,
              onTap: () {
                setState(() {
                  _currentSection = 4;
                  _selectedItemIndex = index;
                  _filters = _filters.copyWith(maxRuntime: runtime, clearMaxRuntime: runtime == null);
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCompactSortSection() {
    final isFocused = _currentSection == 5;
    final sortLabels = {
      SortOption.name: 'Nome',
      SortOption.year: 'Ano',
      SortOption.rating: 'Nota',
      SortOption.popularity: 'Popular',
      SortOption.runtime: 'Duração',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactSectionTitle('Ordenar', Icons.sort_rounded, isFocused),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: SortOption.values.asMap().entries.map((entry) {
            final index = entry.key;
            final sort = entry.value;
            final isSelected = _filters.sortBy == sort;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            final arrow = isSelected
                ? (_filters.sortDescending ? '↓' : '↑')
                : '';
            return _buildCompactChip(
              label: '${sortLabels[sort]}$arrow',
              isSelected: isSelected,
              isFocused: isItemFocused,
              onTap: () {
                setState(() {
                  _currentSection = 5;
                  _selectedItemIndex = index;
                  if (_filters.sortBy == sort) {
                    _filters = _filters.copyWith(sortDescending: !_filters.sortDescending);
                  } else {
                    _filters = _filters.copyWith(sortBy: sort);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required bool isFocused,
    IconData? icon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(
        horizontal: isFocused ? 14 : 12,
        vertical: isFocused ? 10 : 8,
      ),
      decoration: BoxDecoration(
        gradient: isSelected
            ? const LinearGradient(colors: [Color(0xFFE50914), Color(0xFFB20710)])
            : null,
        color: isSelected ? null : Colors.white.withOpacity(isFocused ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFocused
              ? const Color(0xFFFFD700)
              : isSelected
                  ? Colors.transparent
                  : Colors.white.withOpacity(0.2),
          width: isFocused ? 2 : 1,
        ),
        boxShadow: isFocused
            ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.3), blurRadius: 8)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: isFocused ? 13 : 12,
              fontWeight: isSelected || isFocused ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check, color: Colors.white, size: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildGenresSection() {
    final isFocused = _currentSection == 0;
    final genreList = _availableGenres.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Gêneros', Icons.category_rounded, isFocused),
        if (genreList.isEmpty)
          Text(
            'Carregando gêneros...',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: genreList.asMap().entries.map((entry) {
              final index = entry.key;
              final genre = entry.value;
              final isSelected = _filters.genres.contains(genre);
              final isItemFocused = isFocused && _selectedItemIndex == index;
              return _buildChip(
                label: genre,
                isSelected: isSelected,
                isFocused: isItemFocused,
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildYearSection() {
    final isFocused = _currentSection == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Ano de Lançamento', Icons.calendar_today_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _yearOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final year = entry.value;
            final label = year == null ? 'Todos' : '$year+';
            final isSelected = _filters.yearFrom == year;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildChip(
              label: label,
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRatingSection() {
    final isFocused = _currentSection == 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Nota Mínima', Icons.star_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _ratingOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final rating = entry.value;
            final label = rating == null ? 'Todas' : '${rating.toStringAsFixed(0)}+ ⭐';
            final isSelected = _filters.minRating == rating;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildChip(
              label: label,
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCertificationSection() {
    final isFocused = _currentSection == 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Classificação Indicativa', Icons.child_care_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _certificationOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final cert = entry.value;
            final isSelected = cert == 'Todas' 
                ? _filters.certification == null 
                : _filters.certification == cert;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildChip(
              label: cert == 'Todas' ? cert : '$cert anos',
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRuntimeSection() {
    final isFocused = _currentSection == 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Duração Máxima', Icons.timer_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _runtimeOptions.asMap().entries.map((entry) {
            final index = entry.key;
            final runtime = entry.value;
            final label = runtime == null 
                ? 'Qualquer' 
                : runtime < 60 
                    ? '$runtime min'
                    : '${runtime ~/ 60}h${runtime % 60 > 0 ? ' ${runtime % 60}min' : ''}';
            final isSelected = _filters.maxRuntime == runtime;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildChip(
              label: label,
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSortSection() {
    final isFocused = _currentSection == 5;
    final sortLabels = {
      SortOption.name: 'Nome',
      SortOption.year: 'Ano',
      SortOption.rating: 'Nota',
      SortOption.popularity: 'Popularidade',
      SortOption.runtime: 'Duração',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Ordenar Por', Icons.sort_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SortOption.values.asMap().entries.map((entry) {
            final index = entry.key;
            final sort = entry.value;
            final isSelected = _filters.sortBy == sort;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            final arrow = isSelected 
                ? (_filters.sortDescending ? ' ↓' : ' ↑')
                : '';
            return _buildChip(
              label: '${sortLabels[sort]}$arrow',
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final isFocused = _currentSection == 6;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildActionButton(
          label: 'Limpar Filtros',
          icon: Icons.clear_all_rounded,
          isFocused: isFocused && _selectedItemIndex == 0,
          isDestructive: true,
          onTap: () => setState(() => _filters = AdvancedFilters.empty),
        ),
        const SizedBox(width: 16),
        _buildActionButton(
          label: 'Cancelar',
          icon: Icons.close_rounded,
          isFocused: isFocused && _selectedItemIndex == 1,
          isSecondary: true,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 16),
        _buildActionButton(
          label: 'Aplicar Filtros',
          icon: Icons.check_rounded,
          isFocused: isFocused && _selectedItemIndex == 2,
          isPrimary: true,
          onTap: () {
            widget.onApply(_filters);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required bool isFocused,
    bool isPrimary = false,
    bool isSecondary = false,
    bool isDestructive = false,
    VoidCallback? onTap,
  }) {
    Color bgColor;
    Color textColor = Colors.white;
    
    if (isPrimary) {
      bgColor = const Color(0xFFE50914);
    } else if (isDestructive) {
      bgColor = Colors.orange.withOpacity(0.2);
      textColor = Colors.orange;
    } else {
      bgColor = Colors.white.withOpacity(0.1);
      textColor = Colors.white70;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: isFocused ? 24 : 20,
          vertical: isFocused ? 14 : 12,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused ? const Color(0xFFFFD700) : Colors.transparent,
            width: 2,
          ),
          boxShadow: isFocused
              ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 12)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isPrimary ? Colors.white : textColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : textColor,
                fontSize: 14,
                fontWeight: isFocused || isPrimary ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
