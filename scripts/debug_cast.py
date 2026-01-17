#!/usr/bin/env python3
import json
import os

enriched_dir = 'json/enriched'
total = 0
items_with_cast = 0
actor_counts = {}

for file in os.listdir(enriched_dir):
    if file.endswith('.json'):
        with open(os.path.join(enriched_dir, file)) as f:
            data = json.load(f)
            for item in data:
                if item is None:
                    continue
                total += 1
                tmdb = item.get('tmdb', {})
                if tmdb:
                    cast = tmdb.get('cast', [])
                    if cast:
                        items_with_cast += 1
                        for actor in cast:
                            aid = actor.get('id', 0)
                            aname = actor.get('name', '')
                            if aid not in actor_counts:
                                actor_counts[aid] = {'name': aname, 'count': 0}
                            actor_counts[aid]['count'] += 1

print(f'Total itens: {total}')
print(f'Com cast: {items_with_cast}')

# Top 10 atores
top = sorted(actor_counts.items(), key=lambda x: x[1]['count'], reverse=True)[:10]
print('\nTop 10 atores:')
for aid, info in top:
    print(f"  {info['name']} (ID: {aid}): {info['count']} aparicoes")
