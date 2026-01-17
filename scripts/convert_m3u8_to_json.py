#!/usr/bin/env python3
"""
Script para converter arquivos M3U8 em JSONs divididos por categoria.
Isso otimiza o carregamento para dispositivos com pouca memória (1GB RAM).

Como usar:
    cd /Users/gabrielespindola/Documents/saimo_tv_app
    python3 scripts/convert_m3u8_to_json.py
"""

import json
import re
import os
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, List, Any, Tuple

# Categorias que devem ser ignoradas (TV ao vivo, esportes, etc.)
IGNORED_CATEGORIES = [
    '⏺️ ABERTO', '⏺️ BAND', '⏺️ SBT', '⏺️ GLOBO', '⏺️ RECORD', '⏺️ HBO',
    '⏺️ TELECINE', '⏺️ DISCOVERY', '⏺️ CINE SKY', '⏺️ FILMES E SERIES',
    '⏺️ NOTICIA', '⏺️ NBA', '⏺️ RUNTIME', '⏺️ 4K',
    'GLOBO (CENTRO-OESTE)', 'GLOBO (NORDESTE)', 'GLOBO (NORTE)',
    'GLOBO (SUDESTE)', 'GLOBO (SUL)',
    '⚽APPLETV', '⚽DAZN', '⚽DISNEY', '⚽ESPORTE', '⚽HBO',
    '⚽PARAMOUNT', '⚽PREMIERE', '⚽PRIME', '⚽ COPINHA',
    'A FAZENDA', 'BBB 20', 'BBB 2026', 'ESTRELA DA CASA',
    'Área do cliente', 'JOGOS DE HOJE', 'RÁDIOS FM', 'CANAIS:',
]

# Keywords adulto
ADULT_KEYWORDS = ['ADULTOS', '[HOT]', 'XXX', '[Adulto]', 'ADULTO', '❌❤️']

# Keywords de série na categoria
SERIES_CATEGORY_KEYWORDS = ['series', 'série', 'novelas', 'doramas', 'programas', 'stand up', '24h']

# Patterns de episódio
EPISODE_PATTERNS = [
    re.compile(r'S\d+\s*E\d+', re.IGNORECASE),
    re.compile(r'T\d+\s*E\d+', re.IGNORECASE),
    re.compile(r'\d+\s*x\s*\d+', re.IGNORECASE),
    re.compile(r'Temporada\s*\d+', re.IGNORECASE),
    re.compile(r'Temp\.?\s*\d+', re.IGNORECASE),
    re.compile(r'Season\s*\d+', re.IGNORECASE),
]

# Patterns de info de série
SERIES_INFO_PATTERNS = [
    re.compile(r'^(.+?)\s*S(\d+)\s*E(\d+)', re.IGNORECASE),
    re.compile(r'^(.+?)\s*T(\d+)\s*E(\d+)', re.IGNORECASE),
    re.compile(r'^(.+?)\s*(\d+)\s*x\s*(\d+)', re.IGNORECASE),
]


def should_ignore_category(category: str) -> bool:
    upper = category.upper()
    for ignored in IGNORED_CATEGORIES:
        upper_ignored = ignored.upper()
        if upper.startswith(upper_ignored) or upper == upper_ignored or category == ignored:
            return True
    return False


def is_series_by_category(category: str) -> bool:
    lower = category.lower()
    return any(keyword in lower for keyword in SERIES_CATEGORY_KEYWORDS)


def is_series_by_name(name: str) -> bool:
    return any(pattern.search(name) for pattern in EPISODE_PATTERNS)


def is_adult_content(name: str, category: str) -> bool:
    combined = f'{name} {category}'
    return any(keyword in combined for keyword in ADULT_KEYWORDS)


def parse_series_info(name: str) -> Optional[Tuple[str, int, int]]:
    for pattern in SERIES_INFO_PATTERNS:
        match = pattern.match(name)
        if match:
            return (match.group(1).strip(), int(match.group(2)), int(match.group(3)))
    return None


def clean_name(name: str) -> str:
    name = re.sub(r'^\d+\s*[-–]\s*', '', name)
    name = re.sub(r'\s*\[L\]\s*$', '', name, flags=re.IGNORECASE)
    name = re.sub(r'\s*\(DUB\)\s*', '', name, flags=re.IGNORECASE)
    name = re.sub(r'\s*\(LEG\)\s*', '', name, flags=re.IGNORECASE)
    return name.strip()


def generate_id(name: str, url: str) -> str:
    normalized = re.sub(r'[^a-z0-9\s]', '', name.lower()).strip()
    normalized = re.sub(r'\s+', '-', normalized)
    url_hash = str(abs(hash(url)))
    hash_part = url_hash[:6] if len(url_hash) > 6 else url_hash
    return f'{normalized}-{hash_part}'


def normalize_category(category: str) -> str:
    # Remove prefixos comuns
    if category.startswith('OND /'):
        normalized = category.replace('OND /', '').strip()
        if normalized.endswith(' -'):
            normalized = normalized[:-2].strip()
        if normalized:
            normalized = normalized[0].upper() + normalized[1:]
        category = normalized if normalized else 'Filmes'
    elif category.startswith('Series |'):
        normalized = category.replace('Series |', '').strip()
        category = normalized if normalized else 'Séries'
    elif category.startswith('COLETÂNEA:'):
        category = category.replace('COLETÂNEA:', '').strip()
    
    # Normaliza para categoria padrão
    lower = category.lower()
    
    # Plataformas de streaming
    if 'netflix' in lower:
        return 'Netflix'
    if 'prime video' in lower or 'amazon prime' in lower:
        return 'Prime Video'
    if 'disney' in lower:
        return 'Disney+'
    if 'max' in lower and 'mad max' not in lower:
        return 'Max'
    if 'hbo' in lower:
        return 'Max'
    if 'globoplay' in lower:
        return 'Globoplay'
    if 'paramount' in lower:
        return 'Paramount+'
    if 'apple' in lower:
        return 'Apple TV+'
    if 'star' in lower and 'star plus' in lower:
        return 'Star+'
    if 'discovery' in lower:
        return 'Discovery+'
    if 'crunchyroll' in lower:
        return 'Crunchyroll'
    if 'funimation' in lower:
        return 'Funimation'
    if 'directv' in lower:
        return 'DirecTV'
    if 'claro video' in lower:
        return 'Claro Video'
    if 'lionsgate' in lower:
        return 'Lionsgate'
    if 'plutotv' in lower:
        return 'PlutoTV'
    if 'play plus' in lower:
        return 'Play Plus'
    if 'amc' in lower:
        return 'AMC+'
    if 'brasil paralelo' in lower:
        return 'Brasil Paralelo'
    if 'sbt' in lower:
        return 'SBT'
    if 'univer' in lower:
        return 'Univer'
    
    # Gêneros e categorias
    if 'novela' in lower:
        return 'Novelas'
    if 'dorama' in lower:
        return 'Doramas'
    if 'anime' in lower:
        return 'Animes'
    if 'turca' in lower:
        return 'Turcas'
    if 'programas de tv' in lower or 'programas' == lower:
        return 'Programas de TV'
    if 'stand up' in lower or 'stand-up' in lower:
        return 'Stand Up'
    if 'legendad' in lower:
        return 'Legendados'
    if 'document' in lower or 'docu' == lower:
        return 'Documentário'
    if 'com' in lower and ('dia' in lower or 'edia' in lower or 'édia' in lower):
        return 'Comédia'
    if 'drama' in lower:
        return 'Drama'
    if 'terror' in lower:
        return 'Terror'
    if lower.startswith('a') and ('ção' in lower or 'cao' in lower):
        return 'Ação'
    if 'suspense' in lower:
        return 'Suspense'
    if 'romance' in lower:
        return 'Romance'
    if 'anima' in lower and ('ção' in lower or 'cao' in lower):
        return 'Animação'
    if 'fantasia' in lower or ('fic' in lower and 'o' in lower):
        return 'Fantasia'
    if 'faroeste' in lower:
        return 'Faroeste'
    if 'guerra' in lower:
        return 'Guerra'
    if 'aventura' in lower:
        return 'Aventura'
    if 'religio' in lower:
        return 'Religiosos'
    if 'nacion' in lower:
        return 'Nacionais'
    if 'crime' in lower:
        return 'Crime'
    if 'fam' in lower and 'lia' in lower:
        return 'Família'
    if 'marvel' in lower or 'ucm' in lower:
        return 'Marvel'
    if '4k' in lower or 'uhd' in lower:
        return 'UHD 4K'
    if 'infantil' in lower:
        return 'Infantil'
    if 'esporte' in lower:
        return 'Esportes'
    if 'show' in lower:
        return 'Shows'
    if 'cinema' in lower:
        return 'Cinema'
    if 'oscar' in lower:
        return 'Oscar'
    if 'hot' in lower or 'adult' in lower:
        return 'Adultos'
    if 'sugest' in lower or 'semana' in lower:
        return 'Sugestão da Semana'
    if 'outra' in lower and 'produtora' in lower:
        return 'Outras Produtoras'
    if 'lançamento' in lower or 'lancamento' in lower:
        # Extrai o ano se presente
        import re
        year_match = re.search(r'20\d{2}', category)
        if year_match:
            return f'Lançamentos {year_match.group()}'
        return 'Lançamentos'
    if 'dublagem' in lower and 'oficial' in lower:
        return 'Dublagem Não Oficial'
    
    # Coletâneas específicas
    if 'alien' == lower:
        return 'Coletânea: Alien'
    if 'american pie' in lower:
        return 'Coletânea: American Pie'
    if 'john wick' in lower or 'jhon wick' in lower:
        return 'Coletânea: John Wick'
    if 'denzel' in lower:
        return 'Coletânea: Denzel Washington'
    if 'mad max' in lower:
        return 'Coletânea: Mad Max'
    if 'homem aranha' in lower or 'aranha' in lower:
        return 'Coletânea: Homem Aranha'
    if 'jogos mortais' in lower:
        return 'Coletânea: Jogos Mortais'
    if 'jogos vorazes' in lower:
        return 'Coletânea: Jogos Vorazes'
    if 'mib' in lower or 'homens de preto' in lower:
        return 'Coletânea: MIB'
    if 'exterminador' in lower:
        return 'Coletânea: Exterminador'
    if 'shrek' in lower:
        return 'Coletânea: Shrek'
    if 'p' in lower and 'nico' in lower and 'todo' in lower:
        return 'Coletânea: Todo Mundo em Pânico'
    if 'toy story' in lower:
        return 'Coletânea: Toy Story'
    if 'harry potter' in lower:
        return 'Coletânea: Harry Potter'
    if 'senhor dos' in lower and 'an' in lower:
        return 'Coletânea: Senhor dos Anéis'
    if 'crep' in lower and 'sculo' in lower:
        return 'Coletânea: Crepúsculo'
    
    return category


def category_to_filename(category: str) -> str:
    filename = re.sub(r'[^a-z0-9]+', '_', category.lower())
    filename = re.sub(r'^_+|_+$', '', filename)
    return filename


def parse_m3u8_file(filepath: Path) -> List[Dict[str, Any]]:
    """Parse um arquivo M3U8 e retorna lista de filmes/séries."""
    items = []
    
    print(f'📖 Lendo: {filepath}')
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    
    current_name = None
    current_category = None
    current_logo = None
    
    for line in lines:
        line = line.strip()
        
        if line.startswith('#EXTINF:'):
            # Extrai group-title
            group_match = re.search(r'group-title="([^"]*)"', line)
            current_category = group_match.group(1) if group_match else 'Outros'
            
            # Extrai logo
            logo_match = re.search(r'tvg-logo="([^"]*)"', line)
            current_logo = logo_match.group(1) if logo_match else None
            
            # Extrai nome (após a última vírgula)
            name_match = re.search(r',(.+)$', line)
            current_name = name_match.group(1).strip() if name_match else None
            
        elif line.startswith('http') and current_name:
            url = line
            
            # Ignora .ts (streams ao vivo)
            if url.lower().endswith('.ts'):
                current_name = None
                current_category = None
                current_logo = None
                continue
            
            category = current_category or 'Outros'
            
            # Ignora categorias bloqueadas
            if should_ignore_category(category):
                current_name = None
                current_category = None
                current_logo = None
                continue
            
            cleaned_name = clean_name(current_name)
            is_adult = is_adult_content(current_name, category)
            is_series = is_series_by_category(category) or is_series_by_name(current_name)
            series_info = parse_series_info(current_name)
            content_type = 'series' if (is_series or series_info) else 'movie'
            normalized_category = normalize_category(category)
            
            item = {
                'id': generate_id(cleaned_name, url),
                'name': cleaned_name,
                'url': url,
                'type': content_type,
            }
            
            if current_logo:
                item['logo'] = current_logo
            
            if is_adult:
                item['isAdult'] = True
            
            if series_info:
                item['seriesName'] = series_info[0]
                item['season'] = series_info[1]
                item['episode'] = series_info[2]
            
            item['_category'] = normalized_category
            items.append(item)
            
            current_name = None
            current_category = None
            current_logo = None
    
    return items


def main():
    import time
    start_time = time.time()
    
    print('🎬 Iniciando conversão de M3U8 para JSONs por categoria...\n')
    
    # Diretórios
    base_dir = Path(__file__).parent.parent
    assets_dir = base_dir / 'assets'
    output_dir = assets_dir / 'catalog'
    
    # Configuração
    MAX_ITEMS_PER_FILE = 5000  # Máximo de itens por arquivo para economizar memória
    
    # Cria diretório de saída
    output_dir.mkdir(exist_ok=True)
    
    # Lista de arquivos M3U8
    m3u8_files = [
        assets_dir / 'ListaBR01.m3u8',
        assets_dir / 'ListaBR02.m3u8',
    ]
    
    # Parse todos os arquivos
    all_items = []
    for filepath in m3u8_files:
        if filepath.exists():
            items = parse_m3u8_file(filepath)
            all_items.extend(items)
        else:
            print(f'⚠️ Arquivo não encontrado: {filepath}')
    
    # Remove duplicatas por URL
    seen_urls = set()
    unique_items = []
    duplicates = 0
    
    for item in all_items:
        if item['url'] not in seen_urls:
            seen_urls.add(item['url'])
            unique_items.append(item)
        else:
            duplicates += 1
    
    print(f'\n📊 Estatísticas de parsing:')
    print(f'   ✅ Itens válidos: {len(unique_items)}')
    print(f'   🔄 Duplicatas removidas: {duplicates}\n')
    
    # Agrupa por categoria
    by_category: Dict[str, List[Dict]] = {}
    for item in unique_items:
        category = item.pop('_category')
        by_category.setdefault(category, []).append(item)
    
    print(f'   📁 Categorias: {len(by_category)}\n')
    
    # Gera arquivos por categoria (dividindo categorias grandes)
    category_index = []
    total_saved = 0
    
    for category, items in by_category.items():
        filename_base = category_to_filename(category)
        
        # Separa por tipo
        movies = [m for m in items if m['type'] == 'movie' and not m.get('isAdult')]
        series = [m for m in items if m['type'] == 'series' and not m.get('isAdult')]
        adult = [m for m in items if m.get('isAdult')]
        
        total_items = len(movies) + len(series) + len(adult)
        total_saved += total_items
        
        # Verifica se precisa dividir a categoria
        if total_items > MAX_ITEMS_PER_FILE:
            # Divide em partes
            num_parts = (total_items + MAX_ITEMS_PER_FILE - 1) // MAX_ITEMS_PER_FILE
            print(f'   📦 {category}: dividindo em {num_parts} partes ({total_items} itens)')
            
            # Divide séries em páginas
            series_pages = [series[i:i+MAX_ITEMS_PER_FILE] for i in range(0, len(series), MAX_ITEMS_PER_FILE)]
            movies_pages = [movies[i:i+MAX_ITEMS_PER_FILE] for i in range(0, len(movies), MAX_ITEMS_PER_FILE)]
            
            # Cria arquivos paginados
            page_idx = 1
            for page_series in series_pages:
                filename = f'{filename_base}_p{page_idx}'
                category_data = {
                    'category': category,
                    'page': page_idx,
                    'totalPages': max(len(series_pages), len(movies_pages)),
                    'movies': [],
                    'series': page_series,
                }
                category_file = output_dir / f'{filename}.json'
                with open(category_file, 'w', encoding='utf-8') as f:
                    json.dump(category_data, f, ensure_ascii=False, separators=(',', ':'))
                print(f'      📄 {filename}.json: {len(page_series)} séries')
                page_idx += 1
            
            # Adiciona filmes restantes (geralmente poucos)
            if movies:
                filename = f'{filename_base}_movies'
                category_data = {
                    'category': category,
                    'movies': movies,
                    'series': [],
                }
                category_file = output_dir / f'{filename}.json'
                with open(category_file, 'w', encoding='utf-8') as f:
                    json.dump(category_data, f, ensure_ascii=False, separators=(',', ':'))
                print(f'      📄 {filename}.json: {len(movies)} filmes')
            
            # Adiciona ao índice com info de paginação
            category_index.append({
                'id': filename_base,
                'name': category,
                'movieCount': len(movies),
                'seriesCount': len(series),
                'adultCount': len(adult),
                'totalCount': total_items,
                'pages': max(len(series_pages), 1),
                'hasMovies': len(movies) > 0,
            })
        else:
            # Categoria pequena - arquivo único
            category_index.append({
                'id': filename_base,
                'name': category,
                'movieCount': len(movies),
                'seriesCount': len(series),
                'adultCount': len(adult),
                'totalCount': total_items,
            })
            
            # Salva arquivo da categoria
            category_data = {
                'category': category,
                'movies': movies,
                'series': series,
            }
            
            category_file = output_dir / f'{filename_base}.json'
            with open(category_file, 'w', encoding='utf-8') as f:
                json.dump(category_data, f, ensure_ascii=False, separators=(',', ':'))
            
            print(f'   📄 {filename_base}.json: {len(movies)} filmes, {len(series)} séries')
        
        # Salva conteúdo adulto separadamente (sempre)
        if adult:
            adult_data = {
                'category': category,
                'items': adult,
            }
            adult_file = output_dir / f'{filename_base}_adult.json'
            with open(adult_file, 'w', encoding='utf-8') as f:
                json.dump(adult_data, f, ensure_ascii=False, separators=(',', ':'))
            print(f'   🔞 {filename_base}_adult.json: {len(adult)} itens')
    
    # Ordena índice por quantidade
    category_index.sort(key=lambda c: c['totalCount'], reverse=True)
    
    # Gera arquivo de índice
    index_data = {
        'version': 2,
        'generatedAt': datetime.now().isoformat(),
        'totalMovies': sum(c['movieCount'] for c in category_index),
        'totalSeries': sum(c['seriesCount'] for c in category_index),
        'totalAdult': sum(c['adultCount'] for c in category_index),
        'maxItemsPerPage': MAX_ITEMS_PER_FILE,
        'categories': category_index,
    }
    
    index_file = output_dir / 'index.json'
    with open(index_file, 'w', encoding='utf-8') as f:
        json.dump(index_data, f, ensure_ascii=False, indent=2)
    
    elapsed = time.time() - start_time
    
    print(f'\n✅ Conversão concluída!')
    print(f'   📁 Arquivos salvos em: {output_dir}/')
    print(f'   📊 Total de categorias: {len(category_index)}')
    print(f'   🎬 Total de itens: {total_saved}')
    print(f'   ⏱️ Tempo: {elapsed*1000:.0f}ms')
    
    # Calcula tamanho total
    total_size = sum(f.stat().st_size for f in output_dir.glob('*.json'))
    print(f'   💾 Tamanho total: {total_size/1024/1024:.2f} MB')
    
    # Mostra maior arquivo
    largest = max(output_dir.glob('*.json'), key=lambda f: f.stat().st_size)
    print(f'   📏 Maior arquivo: {largest.name} ({largest.stat().st_size/1024/1024:.2f} MB)')


if __name__ == '__main__':
    main()
