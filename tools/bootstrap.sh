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

p = Path('ios/Runner/Info.plist')
s = p.read_text()
if 'NSLocationWhenInUseUsageDescription' not in s:
    s = s.replace('</dict>', '\t<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>Sua localização é usada para mostrar os pontos de ônibus próximos.</string>\n</dict>')
p.write_text(s)

p = Path('ios/Runner/Info.plist')
s = p.read_text()
for key in ('CFBundleDisplayName', 'CFBundleName'):
    entry = f'\t<key>{key}</key>\n\t<string>Meu Ônibus SP</string>'
    if f'<key>{key}</key>' in s:
        import re
        s = re.sub(
            rf'\t<key>{key}</key>\s*\n\s*<string>.*?</string>',
            entry,
            s,
            count=1,
        )
    else:
        s = s.replace('</dict>', f'{entry}\n</dict>')
p.write_text(s)

p = Path('ios/Runner.xcodeproj/project.pbxproj')
s = p.read_text().replace('br.com.lopeskuti.meuOnibus', 'br.com.lopeskuti.meuonibus')
p.write_text(s)
PY

flutter pub get
printf '\nBootstrap concluído.\n'
