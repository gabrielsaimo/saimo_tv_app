# Sistema de Catálogo Enriched com Dados TMDB

Este documento explica como usar o novo sistema de catálogo que utiliza arquivos JSON enriched com dados pré-carregados do TMDB.

## 📋 Visão Geral

O sistema de catálogo enriched substitui as chamadas à API do TMDB em tempo real por dados pré-processados, oferecendo:

- ✅ **Performance**: Carregamento instantâneo sem esperar API
- ✅ **Offline**: Funciona sem conexão com internet
- ✅ **Completo**: Inclui sinopse, elenco, rating, gêneros, keywords, etc.
- ✅ **Busca Avançada**: Filtros por gênero, ano, classificação, rating
- ✅ **Atores**: Busca por ator e visualização de filmografia
- ✅ **Recomendações**: Sugestões baseadas em dados do TMDB

## 📁 Estrutura de Arquivos

```
json/enriched/
├── netflix.json          # Conteúdo Netflix com dados TMDB
├── disney.json           # Conteúdo Disney+ com dados TMDB
├── prime-video.json      # Conteúdo Prime Video com dados TMDB
├── lancamentos.json      # Lançamentos recentes com dados TMDB
└── ...                   # Outras categorias
```

### Formato dos Arquivos

#### Filme:
```json
{
  "id": "filme-id",
  "name": "Nome do Filme",
  "category": "📺 Netflix",
  "type": "movie",
  "url": "http://...",
  "isAdult": false,
  "tmdb": {
    "id": 12345,
    "title": "Título do Filme",
    "originalTitle": "Original Title",
    "overview": "Sinopse completa...",
    "year": "2024",
    "rating": 8.5,
    "genres": ["Ação", "Aventura"],
    "certification": "14",
    "poster": "https://image.tmdb.org/t/p/w500/...",
    "backdrop": "https://image.tmdb.org/t/p/w1280/...",
    "cast": [
      {
        "id": 123,
        "name": "Ator Principal",
        "character": "Personagem",
        "photo": "https://image.tmdb.org/t/p/w185/..."
      }
    ],
    "keywords": ["herói", "batalha"],
    "recommendations": [...]
  }
}
```

#### Série:
```json
{
  "id": "serie-id",
  "name": "Nome da Série",
  "category": "📺 Netflix",
  "type": "series",
  "isAdult": false,
  "episodes": {
    "1": [
      {
        "episode": 1,
        "name": "Episódio 1",
        "url": "http://...",
        "id": "ep-id"
      }
    ]
  },
  "totalSeasons": 3,
  "totalEpisodes": 30,
  "tmdb": { ... }
}
```

## 🚀 Uso Básico

### 1. Inicializar o Serviço

```dart
import 'package:saimo_tv/services/enriched_data_service.dart';

final service = EnrichedDataService();

// Inicializar (carrega categorias prioritárias)
await service.initialize();
```

### 2. Carregar uma Categoria

```dart
// Carregar Netflix
final movies = await service.loadEnrichedCategory('📺 Netflix');

// Contar filmes e séries
final moviesCount = movies.where((m) => m.isMovie).length;
final seriesCount = movies.where((m) => m.isSeries).length;
```

### 3. Buscar Conteúdo

```dart
// Busca simples
final results = await service.searchContent('Vingadores');

// Busca com filtros
final filtered = await service.searchContent(
  'ação',
  filters: FilterOptions(
    type: 'movie',
    certifications: ['14', '16'],
    sortBy: 'rating',
    sortOrder: 'desc',
  ),
);
```

## 🔍 Filtros Avançados

### FilterOptions

```dart
const FilterOptions({
  String type = 'all',              // 'all', 'movie', 'series'
  List<String> genres = const [],   // ['Ação', 'Drama']
  List<String> years = const [],    // ['2024', '2023']
  List<String> certifications = const [], // ['L', '10', '12']
  List<String> ratings = const [],  // ['7.0', '8.0']
  String sortBy = 'popularity',     // 'popularity', 'rating', 'year', 'name'
  String sortOrder = 'desc',        // 'asc', 'desc'
});
```

### Exemplo de Filtros

```dart
// Filmes de ação de 2023-2024 com rating >= 7.0
final filters = FilterOptions(
  type: 'movie',
  genres: ['Ação'],
  years: ['2024', '2023'],
  ratings: ['7.0'],
  sortBy: 'rating',
  sortOrder: 'desc',
);

final results = service.filterAllContent(filters);
```

## 🎬 Trabalhando com Filmes

```dart
EnrichedMovie movie = ...;

// Informações básicas
print(movie.displayTitle);    // Título TMDB ou nome original
print(movie.yearString);      // Ano de lançamento
print(movie.rating);          // Rating do TMDB
print(movie.genresList);      // Lista de gêneros
print(movie.posterUrl);       // URL do poster
print(movie.backdropUrl);     // URL do backdrop

// Verificar tipo
if (movie.isMovie) {
  // É um filme
  print(movie.url); // URL do stream
} else if (movie.isSeries) {
  // É uma série
  final series = movie as EnrichedSeries;
  print(series.totalSeasons);
  print(series.totalEpisodes);
}

// Dados TMDB completos
if (movie.tmdb != null) {
  final tmdb = movie.tmdb!;
  print(tmdb.overview);        // Sinopse
  print(tmdb.certification);   // Classificação indicativa
  print(tmdb.runtime);         // Duração em minutos
  print(tmdb.voteCount);       // Número de votos
  
  // Elenco
  for (final actor in tmdb.cast) {
    print('${actor.name} como ${actor.character}');
  }
  
  // Keywords
  print(tmdb.keywords.join(', '));
  
  // Companhias de produção
  print(tmdb.companies.join(', '));
}
```

## 📺 Trabalhando com Séries

```dart
EnrichedSeries series = ...;

// Informações da série
print(series.totalSeasons);   // Número de temporadas
print(series.totalEpisodes);  // Total de episódios

// Listar temporadas
final seasons = series.seasonsList; // ['1', '2', '3']

// Obter episódios de uma temporada
final season1 = series.getEpisodes('1');

for (final episode in season1) {
  print('Episódio ${episode.episode}: ${episode.name}');
  print('URL: ${episode.url}');
}
```

## 👥 Trabalhando com Atores

### Buscar Atores

```dart
// Buscar atores (autocomplete)
final actors = service.searchActors('Robert Downey');

for (final actor in actors) {
  print(actor.name);
  print(actor.photo); // URL da foto
}
```

### Filmografia de um Ator

```dart
final actor = actors.first;
final filmography = service.getActorFilmography(actor.id);

if (filmography != null) {
  print('Total de trabalhos: ${filmography.totalWorks}');
  
  // Filmes
  for (final movie in filmography.movies) {
    print('${movie.displayTitle} (${movie.yearString})');
  }
  
  // Séries
  for (final series in filmography.series) {
    print('${series.displayTitle} (${series.yearString})');
  }
}
```

## 🎯 Recursos Especiais

### Lançamentos Recentes

```dart
final recent = service.getRecentReleases(limit: 20);
// Retorna filmes/séries dos últimos 2 anos
```

### Itens em Destaque

```dart
// Filmes bem avaliados (rating >= 7.0)
final featuredMovies = service.getFeaturedItems(type: 'movie', limit: 20);

// Séries bem avaliadas
final featuredSeries = service.getFeaturedItems(type: 'series', limit: 20);

// Ambos
final featured = service.getFeaturedItems(limit: 20);
```

### Recomendações

```dart
final movie = ...;

// Recomendações do TMDB que existem no catálogo
final recommendations = service.getAvailableRecommendations(movie);

// Similares por gênero
final similar = service.getSimilarByGenre(movie, limit: 10);
```

### Encontrar por ID

```dart
// Por ID do catálogo
final movie = service.findById('filme-id');

// Por TMDB ID
final movie = service.findByTmdbId(12345);
```

## 📊 Informações do Catálogo

### Categorias Disponíveis

```dart
// Categorias normais
final categories = service.getAllCategories();

// Incluindo categorias adultas
final allCategories = service.getAllCategories(includeAdult: true);

// Categorias de streaming
EnrichedDataService.streamingCategories; // ['📺 Netflix', '📺 Prime Video', ...]

// Categorias de gênero
EnrichedDataService.genreCategories; // ['🎬 Ação', '🎬 Comédia', ...]
```

### Filtros Disponíveis

```dart
// Todos os gêneros
final genres = service.getAvailableGenres();

// Todos os anos
final years = service.getAvailableYears();

// Todas as classificações
final certs = service.getAvailableCertifications(); // ['L', '10', '12', '14', '16', '18']
```

## 🎨 Exemplo Completo de Tela

```dart
class MovieCatalogScreen extends StatefulWidget {
  @override
  State<MovieCatalogScreen> createState() => _MovieCatalogScreenState();
}

class _MovieCatalogScreenState extends State<MovieCatalogScreen> {
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
    // Ver lib/examples/enriched_data_example.dart para implementação completa
    return Scaffold(
      appBar: AppBar(title: Text('Catálogo')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2 / 3,
              ),
              itemCount: _movies.length,
              itemBuilder: (context, index) {
                return MovieCard(movie: _movies[index]);
              },
            ),
    );
  }
}
```

## 🔧 Performance e Cache

### Cache Automático

O serviço implementa cache LRU (Least Recently Used) que mantém até 10 categorias em memória. Quando uma nova categoria é carregada e o limite é atingido, a categoria menos recentemente usada é removida.

### Limpar Cache Manualmente

```dart
service.clearCache();
```

### Estatísticas

```dart
print('Categorias em cache: ${service.cachedCategoriesCount}');
print('Serviço inicializado: ${service.isInitialized}');
```

## 📝 Notas Importantes

1. **Inicialização**: Sempre chame `initialize()` antes de usar o serviço
2. **Performance**: As categorias prioritárias são carregadas primeiro, as demais em background
3. **Memória**: O cache LRU mantém o uso de memória controlado
4. **Offline**: Todo o catálogo funciona offline após o primeiro carregamento
5. **Atualização**: Para atualizar os dados, substitua os arquivos JSON em `json/enriched/`

## 🎯 Migração do Sistema Antigo

Se você está migrando do sistema antigo (chamadas diretas ao TMDB), siga estas etapas:

1. Substitua `TmdbService` por `EnrichedDataService`
2. Use `EnrichedMovie` em vez de `Movie` + dados TMDB separados
3. Os dados já vêm completos, não precisa fazer fetch adicional
4. Adapte os widgets para usar `movie.tmdb.*` diretamente

### Exemplo de Migração

**Antes:**
```dart
final tmdbService = TmdbService();
final movie = Movie(...);
final tmdbData = await tmdbService.fetchMovieDetails(movie.name);
```

**Depois:**
```dart
final service = EnrichedDataService();
final movie = await service.findById(movieId);
// movie.tmdb já tem todos os dados!
```

## 📚 Exemplos Adicionais

Veja o arquivo `lib/examples/enriched_data_example.dart` para mais exemplos detalhados de uso.

## 🐛 Troubleshooting

### Categoria não encontrada
- Verifique se o nome da categoria está correto
- Use uma das constantes: `EnrichedDataService.streamingCategories` ou `enrichedCategories`

### Dados TMDB ausentes
- Alguns filmes/séries podem não ter dados TMDB
- Sempre verifique `if (movie.tmdb != null)` antes de usar

### Performance lenta
- Certifique-se de que está usando cache corretamente
- Não carregue todas as categorias de uma vez
- Use filtros para reduzir o número de resultados

## 📞 Suporte

Para dúvidas ou problemas, consulte:
- `lib/examples/enriched_data_example.dart` - Exemplos práticos
- `lib/services/enriched_data_service.dart` - Código do serviço
- `lib/models/enriched_movie.dart` - Modelos de dados
