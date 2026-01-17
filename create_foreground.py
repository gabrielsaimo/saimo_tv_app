#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

def create_foreground(size):
    # Foreground precisa ser maior para o safe zone do adaptive icon
    # O conteúdo deve estar no centro (66% do tamanho)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Centro e escala para safe zone
    center = size // 2
    scale = 0.6  # Conteudo no centro
    
    # TV Frame
    frame_w = int(size * 0.38 * scale)
    frame_h = int(size * 0.30 * scale)
    frame_x = center - frame_w // 2
    frame_y = center - frame_h // 2 - int(size * 0.08)
    border = max(2, size // 150)
    
    # Frame com borda cyan
    draw.rounded_rectangle(
        [frame_x - border*2, frame_y - border*2, frame_x + frame_w + border*2, frame_y + frame_h + border*2],
        radius=int(size * 0.025),
        fill=(0, 212, 255, 255)
    )
    draw.rounded_rectangle(
        [frame_x, frame_y, frame_x + frame_w, frame_y + frame_h],
        radius=int(size * 0.02),
        fill=(26, 31, 54, 255)
    )
    
    # Tela
    margin = int(size * 0.015)
    draw.rounded_rectangle(
        [frame_x + margin, frame_y + margin, 
         frame_x + frame_w - margin, frame_y + frame_h - margin],
        radius=int(size * 0.012),
        fill=(13, 18, 32, 255)
    )
    
    # Botao play
    play_cx = center
    play_cy = frame_y + frame_h // 2
    play_r = int(size * 0.05)
    
    # Circulo do play
    draw.ellipse(
        [play_cx - play_r, play_cy - play_r, play_cx + play_r, play_cy + play_r],
        fill=(255, 255, 255, 50),
        outline=(255, 255, 255, 120),
        width=max(1, size // 200)
    )
    
    # Triangulo play
    tri_size = int(play_r * 0.7)
    points = [
        (play_cx - tri_size//3, play_cy - tri_size//2),
        (play_cx - tri_size//3, play_cy + tri_size//2),
        (play_cx + tri_size//2, play_cy)
    ]
    draw.polygon(points, fill=(255, 255, 255, 255))
    
    # Indicador LIVE
    live_x = frame_x + int(size * 0.02)
    live_y = frame_y + int(size * 0.02)
    live_r = int(size * 0.01)
    draw.ellipse(
        [live_x, live_y, live_x + live_r * 2, live_y + live_r * 2],
        fill=(255, 59, 92, 255)
    )
    
    # Suporte da TV
    stand_w = int(size * 0.10)
    stand_h = int(size * 0.012)
    stand_x = center - stand_w // 2
    stand_y = frame_y + frame_h + int(size * 0.012)
    draw.rounded_rectangle(
        [stand_x, stand_y, stand_x + stand_w, stand_y + stand_h],
        radius=max(1, stand_h // 2),
        fill=(26, 31, 54, 255)
    )
    
    # Base cyan
    base_w = int(size * 0.16)
    base_h = int(size * 0.01)
    base_x = center - base_w // 2
    base_y = stand_y + stand_h + int(size * 0.008)
    draw.rounded_rectangle(
        [base_x, base_y, base_x + base_w, base_y + base_h],
        radius=max(1, base_h // 2),
        fill=(0, 212, 255, 255)
    )
    
    # Texto SAIMO TV
    if size >= 200:
        try:
            font_size = int(size * 0.055)
            font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', font_size)
            text = 'SAIMO TV'
            bbox = draw.textbbox((0, 0), text, font=font)
            text_w = bbox[2] - bbox[0]
            text_x = center - text_w // 2
            text_y = base_y + int(size * 0.04)
            draw.text((text_x, text_y), text, fill=(255, 255, 255, 255), font=font)
        except Exception as e:
            pass
    
    return img

# Tamanhos para foreground do adaptive icon
sizes = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432
}

for folder, size in sizes.items():
    icon = create_foreground(size)
    path = f'android/app/src/main/res/{folder}/ic_launcher_foreground.png'
    icon.save(path)
    print(f'Criado: {path}')

print('\nForegrounds criados com sucesso!')
