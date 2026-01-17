# Sistema de Catálogo Otimizado para Memória

Este documento descreve a nova arquitetura de carregamento de filmes/séries, otimizada para dispositivos com pouca memória (1GB RAM).

## Problema Original

Os arquivos M3U8 originais eram muito grandes:
- `ListaBR01.m3u8`: 53MB
- `ListaBR02.m3u8`: 60MB
- **Total**: 113MB carregados na memória de uma vez

Isso causava problemas em dispositivos com 1GB de RAM como:
- Fire TV Stick básico
- TV Boxes baratos
- Celulares antigos

## Solução: JSONs por Categoria com Lazy Loading

### Estrutura de Arquivos

```
assets/catalog/
├── index.json           # Índice de categorias (~5KB)
├── netflix_p1.json      # Netflix - página 1 (~1.5MB)
├── netflix_p2.json      # Netflix - página 2 (~1.5MB)
├── ...
├── drama.json           # Drama (categoria pequena, ~1MB)
├── drama_movies.json    # Drama - apenas filmes
└── adultos_adult.json   # Conteúdo adulto (separado)
```

### Otimizações

1. **Carregamento Lazy**: 
   - Apenas o índice (~5KB) é carregado inicialmente
   - Cada categoria é carregada sob demanda

2. **Paginação**:
   - Categorias grandes são divididas em páginas de 5000 itens
   - Cada página tem ~1.5MB (máximo ~2.5MB)

3. **Cache LRU**:
   - Apenas 5 categorias mantidas em memória
   - Categorias antigas são automaticamente liberadas

4. **Parse em Isolate**:
   - JSON é parseado em thread separada
   - UI nunca trava

## Uso

### Antigo (MoviesProvider)
```dart
// Carregava TUDO de uma vez
await provider.loadMovies();  // ~113MB na memória
```

### Novo (LazyMoviesProvider)
```dart
// Carrega apenas o índice (~5KB)
await provider.initialize();

// Carrega categoria sob demanda (~1-2MB)
await provider.selectCategory('Netflix');

// Carrega mais páginas (scroll infinito)
await provider.loadMoreCategoryPages();
```

## Regenerar Catálogo

Se os arquivos M3U8 forem atualizados, regenere os JSONs:

```bash
cd /Users/gabrielespindola/Documents/saimo_tv_app
python3 scripts/convert_m3u8_to_json.py
```

### Configurações do Script

- `MAX_ITEMS_PER_FILE = 5000`: Itens por arquivo
- Pode ser ajustado para dispositivos com menos memória

## Estatísticas

Após conversão:
- **74 categorias**
- **541.580 itens** total
- **Maior arquivo**: ~2.6MB (vs 60MB antes)
- **Tamanho total**: ~156MB em disco (mas carrega apenas o necessário)

## Arquivos

| Arquivo | Descrição |
|---------|-----------|
| `scripts/convert_m3u8_to_json.py` | Script de conversão |
| `lib/services/lazy_movies_service.dart` | Serviço de carregamento lazy |
| `lib/providers/lazy_movies_provider.dart` | Provider otimizado |
| `assets/catalog/` | JSONs gerados |

## Memória Estimada

| Situação | Memória |
|----------|---------|
| Apenas índice | ~5KB |
| 1 categoria pequena | ~1-2MB |
| 5 categorias no cache | ~8-10MB |
| Sistema antigo | ~100-150MB |

**Economia**: ~90% menos uso de memória!
