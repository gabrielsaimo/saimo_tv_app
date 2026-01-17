from PIL import Image, ImageDraw, ImageFont
import os

base_path = "/Users/gabrielespindola/Documents/saimo_tv_app/android/app/src/main/res"
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

def create_icon(size):
    img = Image.new('RGBA', (size, size), (229, 9, 20, 255))
    draw = ImageDraw.Draw(img)
    font_size = int(size * 0.6)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        font = ImageFont.load_default()
    text = "S"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (size - text_width) / 2
    y = (size - text_height) / 2 - bbox[1]
    draw.text((x, y), text, fill='white', font=font)
    return img

for folder, size in sizes.items():
    path = os.path.join(base_path, folder)
    os.makedirs(path, exist_ok=True)
    icon = create_icon(size)
    icon.save(os.path.join(path, "ic_launcher.png"), "PNG")
    print(f"Criado: {folder}/ic_launcher.png")
    
    fg_size = int(size * 108 / 48)
    fg = Image.new('RGBA', (fg_size, fg_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(fg)
    inner_size = int(size * 72 / 48)
    font_size = int(inner_size * 0.6)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), "S", font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (fg_size - text_width) / 2
    y = (fg_size - text_height) / 2 - bbox[1]
    draw.text((x, y), "S", fill='white', font=font)
    fg.save(os.path.join(path, "ic_launcher_foreground.png"), "PNG")
    print(f"Criado: {folder}/ic_launcher_foreground.png")

print("Todos os icones criados!")
