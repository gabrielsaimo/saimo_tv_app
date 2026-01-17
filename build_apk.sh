#!/bin/bash

# ===========================================
# 📺 SAIMO TV - Script de Setup e Build
# ===========================================

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║        📺 SAIMO TV - Setup & Build APK                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretório do projeto
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# ========== 1. VERIFICAR FLUTTER ==========
echo -e "${BLUE}📦 Verificando Flutter SDK...${NC}"

if ! command -v flutter &> /dev/null; then
    echo -e "${YELLOW}⚠️  Flutter não encontrado no PATH${NC}"
    echo ""
    echo -e "${YELLOW}Para instalar o Flutter:${NC}"
    echo "1. Baixe em: https://docs.flutter.dev/get-started/install/macos"
    echo "2. Extraia para ~/development/flutter"
    echo "3. Adicione ao PATH no ~/.zshrc:"
    echo '   export PATH="$PATH:$HOME/development/flutter/bin"'
    echo "4. Execute: source ~/.zshrc"
    echo "5. Execute: flutter doctor"
    echo ""
    
    # Tentar encontrar Flutter em locais comuns
    FLUTTER_PATHS=(
        "$HOME/development/flutter/bin/flutter"
        "$HOME/flutter/bin/flutter"
        "/opt/flutter/bin/flutter"
        "/usr/local/flutter/bin/flutter"
    )
    
    for path in "${FLUTTER_PATHS[@]}"; do
        if [ -f "$path" ]; then
            echo -e "${GREEN}✅ Flutter encontrado em: $path${NC}"
            export PATH="$(dirname $path):$PATH"
            break
        fi
    done
fi

# Verificar novamente
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter SDK não está instalado ou não está no PATH${NC}"
    echo ""
    echo "Instalação rápida:"
    echo "  curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.24.0-stable.zip"
    echo "  mkdir -p ~/development && cd ~/development"
    echo "  unzip ~/flutter_macos_arm64_3.24.0-stable.zip"
    echo '  echo '\''export PATH="$PATH:$HOME/development/flutter/bin"'\'' >> ~/.zshrc'
    echo "  source ~/.zshrc"
    exit 1
fi

echo -e "${GREEN}✅ Flutter encontrado: $(flutter --version | head -1)${NC}"

# ========== 2. VERIFICAR DEPENDÊNCIAS ==========
echo ""
echo -e "${BLUE}🔍 Verificando dependências...${NC}"
flutter doctor --android-only

# ========== 3. INSTALAR PACOTES ==========
echo ""
echo -e "${BLUE}📥 Instalando dependências do projeto...${NC}"
flutter pub get

# ========== 4. BUILD APK ==========
echo ""
echo -e "${BLUE}🔨 Compilando APK Release...${NC}"

# Build para arm64 (Fire TV e dispositivos modernos)
flutter build apk --release

# Verificar se APK foi gerado
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✅ BUILD CONCLUÍDO COM SUCESSO!              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "📁 APK gerado: ${YELLOW}$PROJECT_DIR/$APK_PATH${NC}"
    echo -e "📊 Tamanho: ${YELLOW}$APK_SIZE${NC}"
    echo ""
    echo -e "${BLUE}📱 Para instalar no dispositivo:${NC}"
    echo "   Via ADB:  adb install -r $APK_PATH"
    echo "   Via USB:  Copie o APK para o dispositivo"
    echo ""
    
    # Copiar APK para pasta mais acessível
    cp "$APK_PATH" "$PROJECT_DIR/saimo_tv.apk"
    echo -e "${GREEN}📋 APK copiado para: $PROJECT_DIR/saimo_tv.apk${NC}"
else
    echo -e "${RED}❌ Erro: APK não foi gerado${NC}"
    exit 1
fi
