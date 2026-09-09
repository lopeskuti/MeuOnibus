# Meu Ônibus

App Flutter para iOS e Android que mostra pontos de ônibus próximos, linhas de cada ponto, trajeto e veículos em tempo real em São Paulo.

## Arquitetura

- **GTFS oficial da SPTrans:** pontos, linhas e `shapes` dos trajetos.
- **API Olho Vivo v2.1:** resolução das linhas e posições dos veículos em tempo real.
- **OpenStreetMap + flutter_map:** mapa base.
- **GitHub Actions:** build automático em `develop` e `master`; publish Android e iOS separados e manuais.

O identificador do app é **`br.com.lopeskuti.meuonibus`** no Android e no iOS.

## Fluxo do app

1. Abre o mapa na localização atual.
2. Exibe os pontos próximos a partir da base GTFS.
3. Ao tocar em um ponto, lista as linhas que passam nele.
4. Ao escolher uma linha, desenha a rota e mostra os ônibus em tempo real.

## Preparação local

Com Flutter instalado, execute `./tools/bootstrap.sh` em Bash/Git Bash. Depois baixe o GTFS oficial da SPTrans e rode `python3 tools/prepare_gtfs.py caminho/gtfs.zip`.

Para executar localmente: `flutter run --dart-define=SPTRANS_TOKEN=SUA_CHAVE`.

## GitHub Actions

### Build automático — `.github/workflows/build.yml`
Executa em todo push para `develop` e `master`. Faz análise e gera AAB Android de validação e build iOS release sem assinatura.

### Publish Android — `.github/workflows/publish-android.yml`
Somente manual em **Actions > Publish Android > Run workflow**. Gera AAB release assinado como artifact para upload manual no Google Play Console.

### Publish iOS — `.github/workflows/publish-ios.yml`
Somente manual em **Actions > Publish iOS > Run workflow**. Gera IPA assinado como artifact e, com `upload=true`, envia automaticamente ao App Store Connect/TestFlight.

## GitHub Secrets

Geral: `SPTRANS_TOKEN`.

Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

Apple: `APPLE_TEAM_ID`, `IOS_DISTRIBUTION_CERTIFICATE_BASE64`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`.

Nunca versione `.jks`, `key.properties`, `.p12`, `.mobileprovision`, `.p8` ou a chave SPTrans.
