#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -t sptrans-gtfs-XXXXXX.zip)"
trap 'rm -f "$tmp"' EXIT

official_url='https://www.sptrans.com.br/umbraco/Surface/PerfilDesenvolvedor/BaixarGTFS?memberName=sptrans'
mobility_url='https://storage.googleapis.com/storage/v1/b/mdb-latest/o/br-sao-paulo-sao-paulo-transporte-sptrans-gtfs-8.zip?alt=media'

validate_gtfs() {
  python3 - "$1" <<'PY'
import sys, zipfile
path = sys.argv[1]
required = {'stops.txt', 'routes.txt', 'trips.txt', 'stop_times.txt', 'shapes.txt'}
try:
    with zipfile.ZipFile(path) as z:
        missing = required - set(z.namelist())
        if missing:
            raise SystemExit(1)
except (zipfile.BadZipFile, OSError):
    raise SystemExit(1)
PY
}

download() {
  local url="$1"
  echo "Baixando GTFS: $url"
  rm -f "$tmp"
  curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 \
    "$url" --output "$tmp" || return 1
  validate_gtfs "$tmp"
}

if ! download "$official_url"; then
  echo 'Download direto da SPTrans não ficou disponível; usando o espelho atualizado da Mobility Database.'
  download "$mobility_url"
fi

echo "GTFS válido: $(du -h "$tmp" | cut -f1)"
python3 tools/prepare_gtfs.py "$tmp"
