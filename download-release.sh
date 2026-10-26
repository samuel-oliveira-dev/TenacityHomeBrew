#!/bin/bash

set -euo pipefail

release_url="${1:-}"
destination_dir="${2:-}"

if [ -z "$release_url" ] || [ -z "$destination_dir" ]; then
    printf 'Uso: %s URL_DA_RELEASE PASTA_DESTINO\n' "$0" >&2
    exit 2
fi

command -v curl >/dev/null 2>&1 || {
    printf 'Erro: comando ausente: curl\n' >&2
    exit 1
}
command -v unzip >/dev/null 2>&1 || {
    printf 'Erro: comando ausente: unzip\n' >&2
    exit 1
}

if [ -z "$output_file" ]; then
    output_file="${TMPDIR:-/tmp}/r36s-release.zip"
fi

mkdir -p "$destination_dir"
metadata_file=""
archive_file="$(mktemp)"
cleanup() {
    rm -f "$metadata_file" "$archive_file"
}
trap cleanup EXIT

metadata_file=$(mktemp)
if [[ "$release_url" == *.zip || "$release_url" == *.zip\?* ]]; then
    asset_url="$release_url"
else
    curl -fsSL "$release_url" -o "$metadata_file"

    if command -v jq >/dev/null 2>&1; then
        asset_url=$(jq -r '[.assets[]? | select(.browser_download_url | endswith(".zip"))][0].browser_download_url // empty' "$metadata_file")
    else
        asset_url=$(sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.zip\)".*/\1/p' "$metadata_file" | head -n 1)
    fi
fi

[ -n "$asset_url" ] || {
    printf 'Erro: a release não possui um asset .zip.\n' >&2
    exit 1
}

curl -fsSL "$asset_url" -o "$archive_file"
unzip -q "$archive_file" -d "$destination_dir"
