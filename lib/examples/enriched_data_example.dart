import 'package:flutter/material.dart';
import '../models/enriched_movie.dart';
import '../services/enriched_data_service.dart';

/// Exemplo de como usar o EnrichedDataService
/// 
/// Este arquivo mostra os principais casos de uso do serviço de dados enriched.
class EnrichedDataExample {
  final _service = EnrichedDataService();

  /// 1. Inicializar o serviço (chamar no início do app)
  Future<void> initializeService() async {
    await _service.initialize();
    debugPrint('Serviço inicializado!');
  }

  /// 2. Carregar uma categoria específica
  Future<void> loadCategory() async {
    final movies = await _service.loadEnrichedCategory('📺 Netflix');
    debugPrint('Netflix tem ${movies.length} títulos');
    
    // Contar filmes e séries
    final moviesCount = movies.where((m) => m.isMovie).length;
    final seriesCount = movies.where((m) => m.isSeries).length;
    debugPrint('Filmes: $moviesCount, Séries: $seriesCount');
  }

  /// 3. Buscar conteúdo por texto
  Future<void> searchContent() async {
    // Busca simples
    final results = await _service.searchContent('Vingadores');
    debugPrint('Encontrados ${results.length} resultados para "Vingadores"');
    
    // Busca com filtros
    final filteredResults = await _service.searchContent(
      'ação',
      filters: const FilterOptions(
        type: 'movie',
        certifications: ['14', '16'],
      ),
    );
    debugPrint('Filmes de ação 14+ ou 16+: ${filteredResults.length}');
  }

  /// 4. Filtrar uma categoria
  Future<void> filterCategory() async {
    await _service.loadEnrichedCategory('📺 Netflix');
    
    final filtered = _service.filterContent(
      '📺 Netflix',
      const FilterOptions(
        type: 'series',
        genres: ['Drama', 'Crime'],
        sortBy: 'rating',
        sortOrder: 'desc',
      ),
    );
    
    debugPrint('Séries de Drama/Crime ordenadas por rating: ${filtered.length}');
    
    // Exibir top 5
    for (var i = 0; i < (filtered.length > 5 ? 5 : filtered.length); i++) {
      final movie = filtered[i];
      debugPrint('${i + 1}. ${movie.displayTitle} - ${movie.rating}⭐');
    }
  }

  /// 5. Filtrar todo o catálogo
  Future<void> filterAllContent() async {
    final allMovies = _service.filterAllContent(
      const FilterOptions(
        type: 'movie',
        years: ['2024', '2023'],
        sortBy: 'rating',
        sortOrder: 'desc',
      ),
    );
    
    debugPrint('Filmes de 2023-2024 ordenados por rating: ${allMovies.length}');
  }

  /// 6. Obter lançamentos recentes
  Future<void> getRecentReleases() async {
    final recent = _service.getRecentReleases(limit: 20);
    
    debugPrint('Lançamentos recentes:');
    for (final movie in recent.take(10)) {
      debugPrint('- ${movie.displayTitle} (${movie.yearString})');
    }
  }

  /// 7. Obter itens em destaque
  Future<void> getFeaturedItems() async {
    // Filmes em destaque
    final featuredMovies = _service.getFeaturedItems(type: 'movie', limit: 10);
    debugPrint('Filmes em destaque (rating >= 7.0): ${featuredMovies.length}');
    
    // Séries em destaque
    final featuredSeries = _service.getFeaturedItems(type: 'series', limit: 10);
    debugPrint('Séries em destaque (rating >= 7.0): ${featuredSeries.length}');
  }

  /// 8. Trabalhar com séries e episódios
  Future<void> workWithSeries() async {
    final netflix = await _service.loadEnrichedCategory('📺 Netflix');
    final series = netflix.whereType<EnrichedSeries>().toList();
    
    if (series.isNotEmpty) {
      final firstSeries = series.first;
      debugPrint('Série: ${firstSeries.displayTitle}');
      debugPrint('Temporadas: ${firstSeries.totalSeasons}');
      debugPrint('Episódios totais: ${firstSeries.totalEpisodes}');
      
      // Listar temporadas
      for (final season in firstSeries.seasonsList) {
        final episodes = firstSeries.getEpisodes(season);
        debugPrint('Temporada $season: ${episodes.length} episódios');
        
        // Listar alguns episódios
        for (final episode in episodes.take(3)) {
          debugPrint('  - Episódio ${episode.episode}: ${episode.name}');
        }
      }
    }
  }

  /// 9. Buscar e trabalhar com atores
  Future<void> workWithActors() async {
    // Buscar atores
    final actors = _service.searchActors('Robert Downey');
    debugPrint('Atores encontrados: ${actors.length}');
    
    if (actors.isNotEmpty) {
      final actor = actors.first;
      debugPrint('Ator: ${actor.name}');
      
      // Obter filmografia
      final filmography = _service.getActorFilmography(actor.id);
      if (filmography != null) {
        debugPrint('Filmes: ${filmography.movies.length}');
        debugPrint('Séries: ${filmography.series.length}');
        debugPrint('Total: ${filmography.totalWorks}');
        
        // Listar alguns trabalhos
        debugPrint('Alguns filmes:');
        for (final movie in filmography.movies.take(5)) {
          debugPrint('  - ${movie.displayTitle} (${movie.yearString})');
        }
      }
    }
  }

  /// 10. Obter recomendações
  Future<void> getRecommendations() async {
    final lancamentos = await _service.loadEnrichedCategory('🎬 Lançamentos');
    
    if (lancamentos.isNotEmpty) {
      final movie = lancamentos.first;
      debugPrint('Filme: ${movie.displayTitle}');
      
      // Recomendações do TMDB que existem no catálogo
      final recommendations = _service.getAvailableRecommendations(movie);
      debugPrint('Recomendações: ${recommendations.length}');
      
      // Similares por gênero
      final similar = _service.getSimilarByGenre(movie, limit: 10);
      debugPrint('Similares por gênero: ${similar.length}');
    }
  }

  /// 11. Obter informações de categorias e gêneros
  Future<void> getCategoryInfo() async {
    // Todas as categorias disponíveis
    final categories = _service.getAllCategories();
    debugPrint('Categorias disponíveis: ${categories.length}');
    
    // Categorias incluindo adultas
    final allCategories = _service.getAllCategories(includeAdult: true);
    debugPrint('Total com adultas: ${allCategories.length}');
    
    // Gêneros disponíveis
    final genres = _service.getAvailableGenres();
    debugPrint('Gêneros: ${genres.join(', ')}');
    
    // Anos disponíveis
    final years = _service.getAvailableYears();
    debugPrint('Anos: ${years.take(10).join(', ')}...');
    
    // Classificações disponíveis
    final certifications = _service.getAvailableCertifications();
    debugPrint('Classificações: ${certifications.join(', ')}');
  }

  /// 12. Acessar dados TMDB de um filme
  void accessTMDBData(EnrichedMovie movie) {
    if (movie.tmdb == null) {
      debugPrint('Filme sem dados TMDB');
      return;
    }
    
    final tmdb = movie.tmdb!;
    
    debugPrint('=== Dados TMDB ===');
    debugPrint('Título: ${tmdb.title}');
    debugPrint('Título Original: ${tmdb.originalTitle}');
    debugPrint('Tagline: ${tmdb.tagline}');
    debugPrint('Sinopse: ${tmdb.overview}');
    debugPrint('Ano: ${tmdb.year}');
    debugPrint('Duração: ${tmdb.runtime} min');
    debugPrint('Rating: ${tmdb.rating} ⭐ (${tmdb.voteCount} votos)');
    debugPrint('Classificação: ${tmdb.certification}');
    debugPrint('Gêneros: ${tmdb.genres.join(', ')}');
    debugPrint('Poster: ${tmdb.poster}');
    debugPrint('Backdrop: ${tmdb.backdrop}');
    
    // Elenco
    debugPrint('\nElenco principal:');
    for (final actor in tmdb.cast.take(5)) {
      debugPrint('  - ${actor.name} como ${actor.character}');
    }
    
    // Keywords
    if (tmdb.keywords.isNotEmpty) {
      debugPrint('\nKeywords: ${tmdb.keywords.take(10).join(', ')}');
    }
    
    // Recomendações
    if (tmdb.recommendations.isNotEmpty) {
      debugPrint('\nRecomendações do TMDB: ${tmdb.recommendations.length}');
    }
  }

  /// Widget exemplo de lista de filmes
  Widget buildMoviesList(List<EnrichedMovie> movies) {
    return ListView.builder(
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        final tmdb = movie.tmdb;
        
        return ListTile(
          leading: tmdb?.poster != null
              ? Image.network(
                  tmdb!.poster!,
                  width: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.movie),
                )
              : const Icon(Icons.movie),
          title: Text(movie.displayTitle),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tmdb?.year != null) Text(tmdb!.year),
              if (tmdb?.genres.isNotEmpty ?? false)
                Text(tmdb!.genres.take(2).join(', ')),
            ],
          ),
          trailing: tmdb?.rating != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(tmdb!.rating.toStringAsFixed(1)),
                  ],
                )
              : null,
          onTap: () {
            // Abrir detalhes do filme
            debugPrint('Filme selecionado: ${movie.displayTitle}');
          },
        );
      },
    );
  }

  /// Widget exemplo de filtros
  Widget buildFiltersExample() {
    return const SizedBox.shrink(); // Placeholder - implementar filtros conforme necessário
  }
}

/// Exemplo de tela completa usando EnrichedDataService
class EnrichedCatalogScreen extends StatefulWidget {
  const EnrichedCatalogScreen({super.key});

  @override
  State<EnrichedCatalogScreen> createState() => _EnrichedCatalogScreenState();
}

class _EnrichedCatalogScreenState extends State<EnrichedCatalogScreen> {
  final _service = EnrichedDataService();
  List<EnrichedMovie> _movies = [];
  bool _isLoading = true;
  String _searchQuery = '';
  FilterOptions _filters = const FilterOptions();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    await _service.initialize();
    final movies = await _service.loadEnrichedCategory('📺 Netflix');
    
    setState(() {
      _movies = movies;
      _isLoading = false;
    });
  }

  Future<void> _search() async {
    if (_searchQuery.isEmpty && !_filters.hasActiveFilters) {
      await _loadData();
      return;
    }

    setState(() => _isLoading = true);

    final results = _searchQuery.isNotEmpty
        ? await _service.searchContent(_searchQuery, filters: _filters)
        : _service.filterAllContent(_filters);

    setState(() {
      _movies = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo Enriched'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // Mostrar filtros
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de busca
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar filmes, séries, atores...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              onSubmitted: (_) => _search(),
            ),
          ),
          
          // Lista de resultados
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _movies.isEmpty
                    ? const Center(child: Text('Nenhum resultado encontrado'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2 / 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _movies.length,
                        itemBuilder: (context, index) {
                          final movie = _movies[index];
                          return _buildMovieCard(movie);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieCard(EnrichedMovie movie) {
    final tmdb = movie.tmdb;
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          Expanded(
            child: tmdb?.poster != null
                ? Image.network(
                    tmdb!.poster!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[800],
                      child: const Center(child: Icon(Icons.movie, size: 48)),
                    ),
                  )
                : Container(
                    color: Colors.grey[800],
                    child: const Center(child: Icon(Icons.movie, size: 48)),
                  ),
          ),
          
          // Info
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (tmdb?.year != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    tmdb!.year,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
                if (tmdb?.rating != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        tmdb!.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
