#!/bin/bash
# TITLE: Auto-atualizar R36S Package Manager
# AUTHOR: R36S Package Manager
# AUTO_UPDATE: true

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANAGER_RELEASE_URL="${MANAGER_RELEASE_URL:-}"
ACTION="${1:-update}"
TEMP_DIR="${TMPDIR:-/tmp}/r36s-manager-self-update"

die() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

case "$ACTION" in
    remove)
        die "o gerenciador não pode ser removido por esta receita"
        ;;
    backups)
        printf 'O gerenciador não possui backups próprios.\n'
        exit 0
        ;;
esac

[ -n "$MANAGER_RELEASE_URL" ] || die "MANAGER_RELEASE_URL não foi definida"
[ -x "$BASE_DIR/download-release.sh" ] || die "download-release.sh não encontrado"
command -v curl >/dev/null 2>&1 || die "comando ausente: curl"
command -v jq >/dev/null 2>&1 || die "comando ausente: jq"

metadata_file="$(mktemp)"
cleanup() {
    rm -rf "$TEMP_DIR" "$metadata_file"
}
trap cleanup EXIT

curl -fsSL "$MANAGER_RELEASE_URL" -o "$metadata_file" || die "não foi possível consultar a release do gerenciador"
latest_tag=$(jq -r '.tag_name // empty' "$metadata_file")
[ -n "$latest_tag" ] || die "a API não retornou uma tag de release"

current_tag="v0.0.0"
[ -f "$BASE_DIR/version.txt" ] && current_tag=$(sed -n '1p' "$BASE_DIR/version.txt")
if [ "$ACTION" = "update" ] && [ "$latest_tag" = "$current_tag" ]; then
    printf 'Gerenciador já está na versão mais recente (%s).\n' "$current_tag"
    exit 0
fi

mkdir -p "$TEMP_DIR"
EXTENSION=.zip "$BASE_DIR/download-release.sh" "$MANAGER_RELEASE_URL" "$TEMP_DIR" || \
    die "falha ao baixar e extrair a release do gerenciador"
cp -a "$TEMP_DIR/." "$BASE_DIR/"
printf '%s\n' "$latest_tag" > "$BASE_DIR/version.txt"
printf 'Gerenciador atualizado para a versão %s.\n' "$latest_tag"
