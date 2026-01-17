#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

def create_icon(size):
    # Criar imagem com fundo
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Background gradiente escuro
    for y in range(size):
        ratio = y / size
        r = int(10 + ratio * 10)
        g = int(14 + ratio * 11)
        b = int(33 + ratio * 18)
        for x in range(size):
            img.putpixel((x, y), (r, g, b, 255))
    
    center = size // 2
    
    # TV Frame
    frame_w = int(size * 0.55)
    frame_h = int(size * 0.42)
    frame_x = center - frame_w // 2
    frame_y = int(size * 0.22)
    border = max(2, size // 200)
    
    # Frame com borda cyan
    draw.rounded_rectangle(
        [frame_x - border*2, frame_y - border*2, frame_x + frame_w + border*2, frame_y + frame_h + border*2],
        radius=int(size * 0.04),
        fill=(0, 212, 255, 255)
    )
    draw.rounded_rectangle(
        [frame_x, frame_y, frame_x + frame_w, frame_y + frame_h],
        radius=int(size * 0.035),
        fill=(26, 31, 54, 255)
    )
    
    # Tela
    margin = int(size * 0.025)
    draw.rounded_rectangle(
        [frame_x + margin, frame_y + margin, 
         frame_x + frame_w - margin, frame_y + frame_h - margin],
        radius=int(size * 0.02),
        fill=(13, 18, 32, 255)
    )
    
    # Botao play
    play_cx = center
    play_cy = frame_y + frame_h // 2
    play_r = int(size * 0.08)
    
    # Circulo do play
    draw.ellipse(
        [play_cx - play_r, play_cy - play_r, play_cx + play_r, play_cy + play_r],
        fill=(255, 255, 255, 40),
        outline=(255, 255, 255, 100),
        width=max(1, size // 300)
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
    live_x = frame_x + int(size * 0.03)
    live_y = frame_y + int(size * 0.03)
    live_r = int(size * 0.015)
    draw.ellipse(
        [live_x, live_y, live_x + live_r * 2, live_y + live_r * 2],
        fill=(255, 59, 92, 255)
    )
    
    # Suporte da TV
    stand_w = int(size * 0.16)
    stand_h = int(size * 0.02)
    stand_x = center - stand_w // 2
    stand_y = frame_y + frame_h + int(size * 0.02)
    draw.rounded_rectangle(
        [stand_x, stand_y, stand_x + stand_w, stand_y + stand_h],
        radius=max(1, stand_h // 2),
        fill=(26, 31, 54, 255)
    )
    
    # Base cyan
    base_w = int(size * 0.26)
    base_h = int(size * 0.015)
    base_x = center - base_w // 2
    base_y = stand_y + stand_h + int(size * 0.01)
    draw.rounded_rectangle(
        [base_x, base_y, base_x + base_w, base_y + base_h],
        radius=max(1, base_h // 2),
        fill=(0, 212, 255, 255)
    )
    
    # Texto SAIMO
    if size >= 192:
        try:
            font_size = int(size * 0.085)
            font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', font_size)
            text = 'SAIMO'
            bbox = draw.textbbox((0, 0), text, font=font)
            text_w = bbox[2] - bbox[0]
            text_x = center - text_w // 2
            text_y = int(size * 0.76)
            draw.text((text_x, text_y), text, fill=(255, 255, 255, 255), font=font)
            
            # Texto TV
            font_small = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', int(size * 0.045))
            tv_bbox = draw.textbbox((0, 0), 'TV', font=font_small)
            tv_w = tv_bbox[2] - tv_bbox[0]
            draw.text((center - tv_w // 2, text_y + font_size + 2), 'TV', fill=(0, 212, 255, 255), font=font_small)
        except Exception as e:
            print(f"Aviso: Nao foi possivel adicionar texto: {e}")
    
    return img

# Criar diretorios se necessario
os.makedirs('assets/icons', exist_ok=True)

# Criar icones em diferentes tamanhos
sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192
}

# Criar icone principal (1024x1024)
main_icon = create_icon(1024)
main_icon.save('assets/icons/app_icon.png')
print('Criado: assets/icons/app_icon.png')

# Criar foreground para adaptive icon
main_icon.save('assets/icons/app_icon_foreground.png')
print('Criado: assets/icons/app_icon_foreground.png')

# Criar icones para cada densidade
for folder, size in sizes.items():
    icon = create_icon(size)
    path = f'android/app/src/main/res/{folder}/ic_launcher.png'
    icon.save(path)
    print(f'Criado: {path}')

print('\nTodos os icones criados com sucesso!')
