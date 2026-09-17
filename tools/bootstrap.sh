#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . --platforms=android,ios --org br.com.lopeskuti --project-name meu_onibus

# O flutter create gera o teste de exemplo apontando para MyApp, mas o app usa
# uma classe raiz diferente. Removemos o teste do template para que o analyze
# valide somente os testes reais versionados no projeto.
rm -f test/widget_test.dart

python3 - <<'PY'
from pathlib import Path
import re
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
insert = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />'''
if 'ACCESS_FINE_LOCATION' not in s:
    s = s.replace(marker, insert)
s = s.replace('android:label="meu_onibus"', 'android:label="Meu Ônibus SP"')
p.write_text(s)

p = Path('android/app/build.gradle.kts')
s = p.read_text()
s = s.replace('namespace = "br.com.lopeskuti.meu_onibus"', 'namespace = "br.com.lopeskuti.meuonibus"')
s = s.replace('applicationId = "br.com.lopeskuti.meu_onibus"', 'applicationId = "br.com.lopeskuti.meuonibus"')
if 'keystoreProperties' not in s:
    s = s.replace('plugins {', 'import java.util.Properties\nimport java.io.FileInputStream\n\nplugins {', 1)
    s = s.replace('android {', 'val keystoreProperties = Properties()\nval keystorePropertiesFile = rootProject.file("key.properties")\nif (keystorePropertiesFile.exists()) { keystoreProperties.load(FileInputStream(keystorePropertiesFile)) }\n\nandroid {', 1)
    s = s.replace('    buildTypes {', '''    signingConfigs {\n        create("release") {\n            if (keystorePropertiesFile.exists()) {\n                keyAlias = keystoreProperties["keyAlias"] as String\n                keyPassword = keystoreProperties["keyPassword"] as String\n                storeFile = file(keystoreProperties["storeFile"] as String)\n                storePassword = keystoreProperties["storePassword"] as String\n            }\n        }\n    }\n\n    buildTypes {''', 1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', '''signingConfig = if (keystorePropertiesFile.exists()) {\n                signingConfigs.getByName("release")\n            } else {\n                signingConfigs.getByName("debug")\n            }''')
p.write_text(s)

p = Path('android/app/src/main/kotlin/br/com/lopeskuti/meu_onibus/MainActivity.kt')
if p.exists():
    p.write_text(p.read_text().replace('package br.com.lopeskuti.meu_onibus', 'package br.com.lopeskuti.meuonibus'))

# Altera somente o dicionário-raiz. A substituição textual de </dict> também
# mudava os dicionários internos de UIApplicationSceneManifest e fazia o iOS
# abortar na abertura do app.
import plistlib
p = Path('ios/Runner/Info.plist')
with p.open('rb') as plist_file:
    info = plistlib.load(plist_file)
info.update({
    'NSLocationWhenInUseUsageDescription': 'Sua localização é usada para mostrar os pontos de ônibus próximos.',
    'NSLocationAlwaysAndWhenInUseUsageDescription': 'Sua localização é usada para mostrar pontos de ônibus próximos e atualizar o mapa enquanto você usa o app.',
    'CFBundleDisplayName': 'Meu Ônibus SP',
    'CFBundleName': 'Meu Ônibus SP',
    # O app usa apenas TLS fornecido pelo sistema operacional. Isto elimina a
    # pergunta repetida de compliance de exportação no App Store Connect.
    'ITSAppUsesNonExemptEncryption': False,
})
with p.open('wb') as plist_file:
    plistlib.dump(info, plist_file, sort_keys=False)

p = Path('ios/Runner.xcodeproj/project.pbxproj')
s = p.read_text().replace('br.com.lopeskuti.meuOnibus', 'br.com.lopeskuti.meuonibus')
# A Apple exige iOS 15 ou superior para novos envios. Mantemos o target do
# projeto e dos pods alinhados para evitar um archive com configuração mista.
s, replacements = re.subn(
    r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;',
    'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
    s,
)
if replacements == 0:
    raise SystemExit('Não encontrei o deployment target do iOS no projeto Xcode.')
p.write_text(s)

# No runner Linux o flutter create não gera o Podfile. No macOS, quando ele
# existir, deixamos os pods no mesmo mínimo do projeto sem bloquear o build.
p = Path('ios/Podfile')
if p.exists():
    s = p.read_text()
    s, replacements = re.subn(
        r"(?m)^\s*#?\s*platform :ios, '[^']+'",
        "platform :ios, '15.0'",
        s,
        count=1,
    )
    if replacements == 0:
        raise SystemExit('Não encontrei a plataforma iOS no Podfile.')
    p.write_text(s)

PY

flutter pub get
dart run flutter_launcher_icons
printf '\nBootstrap concluído.\n'
