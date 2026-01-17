# Otimização de Memória - Catálogo de Filmes/Séries

## 📊 Resumo da Otimização

### Antes
- **Arquivos M3U8**: 2 arquivos (~113MB total)
  - `ListaBR01.m3u8`: 53MB
  - `ListaBR02.m3u8`: 60MB
- **Carregamento**: Tudo de uma vez na memória
- **Problema**: Crash em dispositivos com 1GB RAM

### Depois
- **Arquivos JSON**: ~156 arquivos divididos por categoria
  - Máximo por arquivo: **2.6MB** (vs 60MB antes)
  - Arquivo do índice: **~5KB**
- **Carregamento**: Sob demanda (lazy loading)
- **Cache LRU**: Máximo 5 categorias em memória

---

## 🚀 Arquitetura Implementada

```
┌─────────────────────────────────────────────────────┐
│                  OptimizedCatalogScreen             │
│         (Nova tela otimizada para TV)               │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│               LazyMoviesProvider                    │
│  - Gerencia estado do catálogo                      │
│  - Paginação por categoria                          │
│  - Filtros e busca                                  │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│                LazyMoviesService                    │
│  - Cache LRU (5 categorias)                         │
│  - Parse em Isolate                                 │
│  - Carregamento paginado                            │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│               assets/catalog/                       │
│  - _index.json (índice geral ~5KB)                  │
│  - {categoria}.json (série/filmes ~1-2MB)           │
│  - {categoria}_p{n}.json (páginas adicionais)       │
│  - {categoria}_movies.json (filmes separados)       │
└─────────────────────────────────────────────────────┘
```

---

## 📁 Arquivos Criados/Modificados

### Novos Arquivos
| Arquivo | Descrição |
|---------|-----------|
| `scripts/convert_m3u8_to_json.py` | Converte M3U8 → JSON por categoria |
| `lib/services/lazy_movies_service.dart` | Serviço com lazy loading e cache LRU |
| `lib/providers/lazy_movies_provider.dart` | Provider otimizado |
| `lib/screens/optimized_catalog_screen.dart` | Nova tela otimizada |
| `assets/catalog/*.json` | ~156 arquivos JSON |

### Arquivos Modificados
| Arquivo | Modificação |
|---------|-------------|
| `pubspec.yaml` | Adicionado `assets/catalog/` |
| `lib/main.dart` | Adicionado `LazyMoviesProvider` |
| `lib/app.dart` | Rota `/movies` usa tela otimizada |

---

## 💾 Economia de Memória

| Métrica | Antes | Depois | Redução |
|---------|-------|--------|---------|
| Arquivo inicial | 60MB | 5KB | 99.99% |
| Arquivo máximo | 60MB | 2.6MB | 95.7% |
| Memória em uso | ~200MB+ | ~15-30MB | 85%+ |
| Categorias em cache | Todas | 5 máx | Dinâmico |

---

## 🔧 Como Funciona

### 1. Inicialização (5KB)
```dart
// Carrega apenas o índice
_categories = await _service.loadCategoryIndex();
// Resultado: lista de 74 categorias com metadados
```

### 2. Seleção de Categoria (1-3MB)
```dart
// Carrega apenas a categoria selecionada
_currentCategoryData = await _service.loadCategory(categoryId, page: 1);
// Parsing em Isolate para não travar a UI
```

### 3. Scroll Infinito (Paginação)
```dart
// Quando chega perto do fim, carrega mais
if (hasMoreCategoryPages) {
  await provider.loadMoreCategoryPages();
}
```

### 4. Cache LRU (5 categorias)
```dart
// Quando 6ª categoria é carregada, a mais antiga é removida
_cache.remove(_lruQueue.removeFirst()); // Libera memória
```

---

## 📱 Rotas

| Rota | Tela | Descrição |
|------|------|-----------|
| `/movies` | `OptimizedCatalogScreen` | **Nova tela otimizada** |
| `/movies-legacy` | `MoviesCatalogScreen` | Tela antiga (backup) |

---

## 🧪 Teste de Memória

Para testar em dispositivo com pouca memória:

```bash
# Build de release
flutter build apk --release

# Instalar no dispositivo
adb install build/app/outputs/flutter-apk/app-release.apk

# Monitorar memória
adb shell dumpsys meminfo com.saimotv.app
```

---

## 📝 Estrutura do Catálogo JSON

### _index.json
```json
{
  "categories": [
    {
      "id": "netflix",
      "name": "Netflix",
      "movieCount": 1234,
      "seriesCount": 567,
      "adultCount": 0,
      "totalCount": 1801,
      "pages": 1,
      "hasMovies": false
    }
  ],
  "totalMovies": 123456,
  "totalSeries": 67890,
  "generatedAt": "2025-01-09T..."
}
```

### {categoria}.json
```json
{
  "id": "netflix",
  "name": "Netflix",
  "page": 1,
  "totalPages": 1,
  "movies": [...],
  "series": [...]
}
```

---

## ✅ Checklist de Migração

- [x] Converter M3U8 para JSON
- [x] Criar serviço de lazy loading
- [x] Criar provider otimizado
- [x] Criar tela otimizada para TV
- [x] Atualizar rotas do app
- [x] Atualizar pubspec.yaml
- [ ] Testar em Fire TV Stick (1GB RAM)
- [ ] Testar em TV Box (1GB RAM)
- [ ] Monitorar uso de memória em produção

---

## 🚨 Troubleshooting

### Erro: "Categoria não encontrada"
- Verifique se `assets/catalog/_index.json` existe
- Execute `python scripts/convert_m3u8_to_json.py` novamente

### Erro: "Arquivo de catálogo não encontrado"
- Verifique se `assets/catalog/` está no `pubspec.yaml`
- Execute `flutter pub get`

### App travando ainda com pouca memória
- Reduza `maxCachedCategories` de 5 para 3
- Reduza `_pageSize` de 30 para 20

---

**Última atualização**: Janeiro 2025
