#!/usr/bin/env python3
import json
import os

enriched_dir = 'json/enriched'
total_movies = 0
total_series = 0

for file in os.listdir(enriched_dir):
    if file.endswith('.json'):
        with open(os.path.join(enriched_dir, file)) as f:
            data = json.load(f)
            for item in data:
                if item and item.get('type') == 'series':
                    total_series += 1
                else:
                    total_movies += 1

print(f'Total filmes: {total_movies}')
print(f'Total series: {total_series}')

# Apple TV
with open('json/enriched/apple-tv.json') as f:
    data = json.load(f)
    series = [item for item in data if item and item.get('type') == 'series']
    print(f'\nApple TV+ series: {len(series)} de {len(data)}')
    if series:
        print(f'  Exemplo: {series[0].get("name")}')
