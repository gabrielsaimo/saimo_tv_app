#!/bin/bash

# Script de deploy rápido para Saimo TV
# Uso: ./deploy.sh [IP_DO_DISPOSITIVO]

set -e

echo "╔════════════════════════════════════════╗"
echo "║        📺 SAIMO TV - Deploy            ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter não encontrado. Instale o Flutter SDK.${NC}"
    exit 1
fi

# Verificar ADB
if ! command -v adb &> /dev/null; then
    echo -e "${RED}❌ ADB não encontrado. Instale o Android SDK.${NC}"
    exit 1
fi

# Limpar build anterior
echo -e "${YELLOW}🧹 Limpando builds anteriores...${NC}"
flutter clean

# Instalar dependências
echo -e "${YELLOW}📦 Instalando dependências...${NC}"
flutter pub get

# Build APK Release
echo -e "${YELLOW}🔨 Compilando APK Release...${NC}"
flutter build apk --release --target-platform android-arm64

# Verificar se APK foi gerado
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}❌ Erro: APK não foi gerado.${NC}"
    exit 1
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
echo -e "${GREEN}✅ APK gerado: $APK_PATH ($APK_SIZE)${NC}"

# Conectar ao dispositivo se IP fornecido
if [ ! -z "$1" ]; then
    echo -e "${YELLOW}📡 Conectando ao dispositivo: $1${NC}"
    adb connect "$1:5555"
    sleep 2
fi

# Verificar dispositivos conectados
DEVICE_COUNT=$(adb devices | grep -c "device$" || true)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ Nenhum dispositivo conectado.${NC}"
    echo "Para instalar manualmente, copie o APK de:"
    echo "$APK_PATH"
    exit 0
fi

# Instalar no dispositivo
echo -e "${YELLOW}📱 Instalando no dispositivo...${NC}"
adb install -r "$APK_PATH"

# Iniciar app
echo -e "${YELLOW}🚀 Iniciando Saimo TV...${NC}"
adb shell am start -n com.saimo.tv/.MainActivity

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Deploy concluído com sucesso!   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
