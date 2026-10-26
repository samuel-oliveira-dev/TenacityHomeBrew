#!/bin/bash

set -euo pipefail

release_url="${1:-}"
destination_dir="${2:-}"
extension="${EXTENSION-}"

if [ -z "$release_url" ] || [ -z "$destination_dir" ]; then
    printf 'Uso: %s URL_DA_RELEASE PASTA_DESTINO\n' "$0" >&2
    exit 2
fi

if [ -z "$extension" ]; then
    printf 'Erro: EXTENSION não foi definida.\n' >&2
    exit 1
fi

case "$extension" in
    .*) ;;
    *) extension=".$extension" ;;
esac

command -v curl >/dev/null 2>&1 || {
    printf 'Erro: comando ausente: curl\n' >&2
    exit 1
}
mkdir -p "$destination_dir"
metadata_file=""
archive_file="$(mktemp)"
cleanup() {
    rm -f "$metadata_file" "$archive_file"
}
trap cleanup EXIT

metadata_file=$(mktemp)
case "$release_url" in
    *"$extension"|*"$extension"\?*)
    asset_url="$release_url"
    ;;
    *)
    curl -fsSL "$release_url" -o "$metadata_file"

    if command -v jq >/dev/null 2>&1; then
        asset_url=$(jq -r --arg extension "$extension" '[.assets[]? | select(.browser_download_url | endswith($extension))][0].browser_download_url // empty' "$metadata_file")
    else
        asset_url=$(sed -n "s|.*\"browser_download_url\"[[:space:]]*:[[:space:]]*\"\([^\"]*${extension}\)\".*|\1|p" "$metadata_file" | head -n 1)
    fi
    ;;
esac

[ -n "$asset_url" ] || {
    printf 'Erro: a release não possui um asset %s.\n' "$extension" >&2
    exit 1
}

curl -fsSL "$asset_url" -o "$archive_file"
if [ "$extension" = ".zip" ]; then
    command -v unzip >/dev/null 2>&1 || {
        printf 'Erro: comando ausente: unzip\n' >&2
        exit 1
    }
    unzip -q "$archive_file" -d "$destination_dir"
else
    filename="$(basename "${asset_url%%\?*}")"
    cp "$archive_file" "$destination_dir/$filename"
fi
