import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/lazy_movies_provider.dart';

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
  late AdvancedFilters _filters;
  
  // Navegação
  int _currentSection = 0; // 0=gêneros, 1=ano, 2=nota, 3=classificação, 4=idioma, 5=duração, 6=ordenação
  int _selectedItemIndex = 0;
  
  // Dados disponíveis (extraídos do catálogo)
  Set<String> _availableGenres = {};
  Set<String> _availableCertifications = {};
  Set<String> _availableLanguages = {};
  int _minYear = 1950;
  int _maxYear = DateTime.now().year;
  
  // Opções de ano
  final List<int?> _yearOptions = [null, 2026, 2025, 2024, 2023, 2022, 2021, 2020, 2015, 2010, 2000, 1990];
  
  // Opções de nota
  final List<double?> _ratingOptions = [null, 9.0, 8.0, 7.0, 6.0, 5.0];
  
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
    
    // Coleta gêneros, certificações e idiomas de todos os filmes carregados
    final genres = <String>{};
    final certifications = <String>{};
    final languages = <String>{};
    
    for (final item in provider.displayItems) {
      final tmdb = item.movie?.tmdb ?? item.series?.tmdb;
      if (tmdb != null) {
        if (tmdb.genres != null) genres.addAll(tmdb.genres!);
        if (tmdb.certification != null) certifications.add(tmdb.certification!);
        if (tmdb.language != null) languages.add(tmdb.language!);
      }
    }
    
    setState(() {
      _availableGenres = genres;
      _availableCertifications = certifications;
      _availableLanguages = languages;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      _navigateUp();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _navigateDown();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _navigateLeft();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _navigateRight();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      _handleSelect();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  void _navigateUp() {
    setState(() {
      if (_currentSection > 0) {
        _currentSection--;
        _selectedItemIndex = 0;
      }
    });
  }

  void _navigateDown() {
    setState(() {
      if (_currentSection < 7) { // 0-6 são seções + 7 é botões
        _currentSection++;
        _selectedItemIndex = 0;
      }
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

  int _getMaxIndexForSection(int section) {
    switch (section) {
      case 0: return _availableGenres.length - 1; // Gêneros
      case 1: return _yearOptions.length - 1; // Ano de
      case 2: return _ratingOptions.length - 1; // Nota
      case 3: return _availableCertifications.length; // Classificação (+ "Todas")
      case 4: return _availableLanguages.length; // Idioma (+ "Todos")
      case 5: return _runtimeOptions.length - 1; // Duração
      case 6: return SortOption.values.length - 1; // Ordenação
      case 7: return 2; // Botões (Limpar, Cancelar, Aplicar)
      default: return 0;
    }
  }

  void _handleSelect() {
    switch (_currentSection) {
      case 0: // Gêneros
        if (_availableGenres.isNotEmpty) {
          final genre = _availableGenres.elementAt(_selectedItemIndex.clamp(0, _availableGenres.length - 1));
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
        final year = _yearOptions[_selectedItemIndex.clamp(0, _yearOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(yearFrom: year, clearYearFrom: year == null);
        });
        break;
      case 2: // Nota
        final rating = _ratingOptions[_selectedItemIndex.clamp(0, _ratingOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(minRating: rating, clearMinRating: rating == null);
        });
        break;
      case 3: // Classificação
        final certList = ['Todas', ..._availableCertifications];
        final cert = certList[_selectedItemIndex.clamp(0, certList.length - 1)];
        setState(() {
          _filters = _filters.copyWith(
            certification: cert == 'Todas' ? null : cert,
            clearCertification: cert == 'Todas',
          );
        });
        break;
      case 4: // Idioma
        final langList = ['Todos', ..._availableLanguages];
        final lang = langList[_selectedItemIndex.clamp(0, langList.length - 1)];
        setState(() {
          _filters = _filters.copyWith(
            language: lang == 'Todos' ? null : lang,
            clearLanguage: lang == 'Todos',
          );
        });
        break;
      case 5: // Duração
        final runtime = _runtimeOptions[_selectedItemIndex.clamp(0, _runtimeOptions.length - 1)];
        setState(() {
          _filters = _filters.copyWith(maxRuntime: runtime, clearMaxRuntime: runtime == null);
        });
        break;
      case 6: // Ordenação
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
      case 7: // Botões
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
        insetPadding: const EdgeInsets.all(40),
        child: Container(
          width: size.width * 0.8,
          height: size.height * 0.85,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF0F0F1A),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
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
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGenresSection(),
                        const SizedBox(height: 24),
                        _buildYearSection(),
                        const SizedBox(height: 24),
                        _buildRatingSection(),
                        const SizedBox(height: 24),
                        _buildCertificationSection(),
                        const SizedBox(height: 24),
                        _buildLanguageSection(),
                        const SizedBox(height: 24),
                        _buildRuntimeSection(),
                        const SizedBox(height: 24),
                        _buildSortSection(),
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final certList = ['Todas', ..._availableCertifications.toList()..sort()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Classificação Indicativa', Icons.child_care_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: certList.asMap().entries.map((entry) {
            final index = entry.key;
            final cert = entry.value;
            final isSelected = cert == 'Todas' 
                ? _filters.certification == null 
                : _filters.certification == cert;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildChip(
              label: cert,
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLanguageSection() {
    final isFocused = _currentSection == 4;
    final langList = ['Todos', ..._availableLanguages.toList()..sort()];
    
    // Mapeia códigos para nomes
    final langNames = {
      'en': 'Inglês',
      'pt': 'Português',
      'es': 'Espanhol',
      'fr': 'Francês',
      'de': 'Alemão',
      'it': 'Italiano',
      'ja': 'Japonês',
      'ko': 'Coreano',
      'zh': 'Chinês',
      'hi': 'Hindi',
      'ru': 'Russo',
      'tr': 'Turco',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Idioma Original', Icons.language_rounded, isFocused),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: langList.asMap().entries.map((entry) {
            final index = entry.key;
            final lang = entry.value;
            final displayName = lang == 'Todos' ? lang : (langNames[lang] ?? lang.toUpperCase());
            final isSelected = lang == 'Todos' 
                ? _filters.language == null 
                : _filters.language == lang;
            final isItemFocused = isFocused && _selectedItemIndex == index;
            return _buildChip(
              label: displayName,
              isSelected: isSelected,
              isFocused: isItemFocused,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRuntimeSection() {
    final isFocused = _currentSection == 5;

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
    final isFocused = _currentSection == 6;
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
    final isFocused = _currentSection == 7;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildActionButton(
          label: 'Limpar Filtros',
          icon: Icons.clear_all_rounded,
          isFocused: isFocused && _selectedItemIndex == 0,
          isDestructive: true,
        ),
        const SizedBox(width: 16),
        _buildActionButton(
          label: 'Cancelar',
          icon: Icons.close_rounded,
          isFocused: isFocused && _selectedItemIndex == 1,
          isSecondary: true,
        ),
        const SizedBox(width: 16),
        _buildActionButton(
          label: 'Aplicar Filtros',
          icon: Icons.check_rounded,
          isFocused: isFocused && _selectedItemIndex == 2,
          isPrimary: true,
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

    return AnimatedContainer(
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
    );
  }
}
