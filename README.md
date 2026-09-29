# Meu Ônibus

App Flutter para iOS e Android que mostra pontos de ônibus próximos, linhas de cada ponto, trajeto e veículos em tempo real em São Paulo.

## Arquitetura

- **GTFS oficial da SPTrans:** pontos, linhas, dias de operação e `shapes` dos trajetos. O feed atual contém viagens de referência, sem grade completa de partidas.
- **Quadro de itinerários da SPTrans:** partidas por linha, sentido e tipo de dia, consultadas quando a linha é aberta. A primeira, a última e o intervalo são horários de saída do terminal de origem. É uma interface pública do site, mas não faz parte da API documentada do Olho Vivo.
- **API Olho Vivo v2.1:** resolução de linha e ponto, posição dos veículos e previsão em tempo real para a combinação exata de linha e parada.
- **OpenStreetMap + flutter_map:** mapa base.
- **GitHub Actions:** publicação Android e iOS manual, com a versão informada ao iniciar o workflow.

O identificador do app é **`br.com.lopeskuti.meuonibus`** no Android e no iOS.

## Fluxo do app

1. Abre o mapa na localização atual.
2. Exibe os pontos próximos a partir da base GTFS.
3. Ao tocar em um ponto, lista as linhas que passam nele.
4. Ao escolher uma linha, desenha a rota e mostra os ônibus em tempo real.

Quando a Olho Vivo não fornece uma chegada para o ponto selecionado, o app pode mostrar a próxima **partida do terminal de origem** separadamente. Esse horário não representa a passagem no ponto intermediário. Se o serviço de itinerários estiver indisponível, os dias da base GTFS continuam visíveis, mas primeiro/último horário podem ficar indisponíveis.

## Preparação local

Com Flutter instalado, execute `./tools/bootstrap.sh` em Bash/Git Bash. Depois baixe o GTFS oficial da SPTrans e rode `python3 tools/prepare_gtfs.py caminho/gtfs.zip`.

Para executar localmente: `flutter run --dart-define=SPTRANS_TOKEN=SUA_CHAVE`.

## GitHub Actions

### Publicação manual — `.github/workflows/build.yml`
Em **Actions > Publish release > Run workflow**, informe a versão no formato `X.Y.Z` (por exemplo, `1.0.9`) e confirme a execução. O workflow valida o app, gera os artefatos Android e iOS assinados e envia o IPA ao TestFlight. O número de build é definido automaticamente pelo número da execução no GitHub.

## GitHub Secrets

Geral: `SPTRANS_TOKEN`.

Android: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

Apple: `APPLE_TEAM_ID`, `IOS_DISTRIBUTION_CERTIFICATE_BASE64`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_PROVISIONING_PROFILE_NAME`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`.

Nunca versione `.jks`, `key.properties`, `.p12`, `.mobileprovision`, `.p8` ou a chave SPTrans.
