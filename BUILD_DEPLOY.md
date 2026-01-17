# 📺 Saimo TV - Build e Deploy

## Pré-requisitos

### Ferramentas Necessárias
- Flutter SDK 3.0+ instalado
- Android SDK com API 21+ (Lollipop)
- Java JDK 11 ou superior
- ADB (Android Debug Bridge)

### Verificar Instalação
```bash
flutter doctor
```

---

## 🔧 Configuração do Projeto

### 1. Clonar e Instalar Dependências
```bash
cd saimo_tv_app
flutter pub get
```

### 2. Verificar Dispositivos
```bash
flutter devices
```

---

## 📱 Build para TV Box / Fire TV

### Build Debug (para testes)
```bash
flutter build apk --debug
```
APK gerado em: `build/app/outputs/flutter-apk/app-debug.apk`

### Build Release (para produção)
```bash
flutter build apk --release
```
APK gerado em: `build/app/outputs/flutter-apk/app-release.apk`

### Build com Split por Arquitetura
```bash
flutter build apk --split-per-abi --release
```
Gera APKs separados para:
- `app-armeabi-v7a-release.apk` (ARM 32-bit)
- `app-arm64-v8a-release.apk` (ARM 64-bit) ← **Recomendado para Fire TV**
- `app-x86_64-release.apk` (x86 64-bit)

---

## 🔥 Instalação no Fire TV / TV Box

### Via ADB (Recomendado)

#### 1. Habilitar Modo Desenvolvedor no Fire TV
1. Configurações → Meu Fire TV → Sobre
2. Clique 7 vezes em "Fire TV Stick" para ativar
3. Volte e acesse "Opções do desenvolvedor"
4. Ative "Depuração ADB" e "Apps de fontes desconhecidas"

#### 2. Descobrir IP do dispositivo
No Fire TV: Configurações → Meu Fire TV → Sobre → Rede

#### 3. Conectar via ADB
```bash
adb connect <IP_DO_FIRETV>:5555
# Exemplo: adb connect 192.168.1.100:5555
```

#### 4. Instalar APK
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Verificar Instalação
```bash
adb shell pm list packages | grep saimo
```

---

## 🖥️ Instalação em TV Box Android

### Método 1: Via USB
1. Copie o APK para um pendrive
2. Conecte ao TV Box
3. Use um gerenciador de arquivos para instalar

### Método 2: Via Rede Local
1. Instale "Send Files to TV" no celular e TV Box
2. Envie o APK pelo app

### Método 3: Via ADB WiFi
```bash
# Conectar ao TV Box (mesma rede)
adb connect <IP_DO_TVBOX>:5555

# Instalar
adb install -r app-release.apk
```

---

## 🎮 Testando com Controle Remoto

### Mapeamento de Teclas
| Controle Remoto | Ação no App |
|----------------|-------------|
| D-Pad Up/Down/Left/Right | Navegação |
| OK / Select | Selecionar item |
| Back | Voltar / Sair player |
| Menu | Abrir configurações |
| Play/Pause | Pausar/Continuar vídeo |

### Atalhos do Teclado (para debug)
- **Setas**: Navegação
- **Enter**: Selecionar
- **Escape**: Voltar
- **Espaço**: Play/Pause
- **F**: Fullscreen

---

## 🔍 Debug e Logs

### Ver logs em tempo real
```bash
adb logcat | grep -E "flutter|saimo"
```

### Capturar screenshot
```bash
adb shell screencap /sdcard/screen.png
adb pull /sdcard/screen.png
```

### Executar em modo debug
```bash
flutter run -d <device_id>
```

---

## ⚙️ Configurações Avançadas

### Personalizar Ícone
1. Substitua os arquivos em `android/app/src/main/res/mipmap-*/`
2. Use [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/)

### Gerar APK Assinado para Publicação
```bash
# Gerar keystore (apenas uma vez)
keytool -genkey -v -keystore saimo_tv.keystore -alias saimo_tv -keyalg RSA -keysize 2048 -validity 10000

# Configurar em android/key.properties
storePassword=<sua_senha>
keyPassword=<sua_senha>
keyAlias=saimo_tv
storeFile=../saimo_tv.keystore

# Build assinado
flutter build apk --release
```

---

## 🐛 Solução de Problemas

### APK não aparece no launcher do Fire TV
- Verifique se o `AndroidManifest.xml` tem `LEANBACK_LAUNCHER`
- Reinicie o Fire TV após instalar

### Erro de conexão ADB
```bash
adb kill-server
adb start-server
adb connect <IP>:5555
```

### Vídeo não reproduz
- Verifique conexão com internet
- Teste URL do stream em outro player
- Verifique se o canal está no ar

### App trava ao abrir
```bash
adb logcat | grep "FATAL\|Exception"
```

---

## 📊 Informações do APK

| Propriedade | Valor |
|-------------|-------|
| Package | com.saimo.tv |
| Min SDK | 21 (Android 5.0) |
| Target SDK | 33 (Android 13) |
| Arquiteturas | armeabi-v7a, arm64-v8a, x86_64 |
| Tamanho Aprox. | 25-35 MB |

---

## 🚀 Deploy Rápido

Script para build e deploy automático:

```bash
#!/bin/bash
echo "🔨 Building Saimo TV..."
flutter build apk --release

echo "📱 Installing on device..."
adb install -r build/app/outputs/flutter-apk/app-release.apk

echo "🚀 Launching app..."
adb shell am start -n com.saimo.tv/.MainActivity

echo "✅ Done!"
```

Salve como `deploy.sh` e execute:
```bash
chmod +x deploy.sh
./deploy.sh
```
