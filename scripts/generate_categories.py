#!/usr/bin/env python3
"""
Gera categories.json a partir dos arquivos JSON enriched.
O nome da categoria é extraído diretamente do campo 'category' do primeiro item de cada JSON.
"""
import os
import json

enriched_path = "json/enriched"
categories = []

for filename in sorted(os.listdir(enriched_path)):
    if filename.endswith(".json"):
        filepath = os.path.join(enriched_path, filename)
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
            count = len(data) if isinstance(data, list) else 0
            file_id = filename.replace(".json", "")
            is_adult = "adulto" in file_id.lower()
            
            # Extrai o nome da categoria do primeiro item do JSON
            if isinstance(data, list) and len(data) > 0 and "category" in data[0]:
                name = data[0]["category"]
            else:
                name = file_id.replace("-", " ").title()
            
            categories.append({
                "name": name,
                "file": filename,
                "count": count,
                "isAdult": is_adult
            })
        except Exception as e:
            print(f"Erro em {filename}: {e}")

with open("json/categories.json", "w", encoding="utf-8") as f:
    json.dump(categories, f, indent=2, ensure_ascii=False)

total = sum(c["count"] for c in categories)
print(f"✅ Criado json/categories.json com {len(categories)} categorias")
print(f"📊 Total de itens: {total}")