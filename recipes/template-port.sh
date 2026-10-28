#!/bin/bash
# TITLE: Template de Port/Tool
# AUTHOR: Comunidade R36S
# REPO: usuario/repositorio-do-app

set -euo pipefail

APP_NAME="${APP_NAME:-exemplo_app}"
INSTALL_DIR="${INSTALL_DIR:-/roms/ports/$APP_NAME}"
INSTALL_FILE="${INSTALL_FILE-}"
REPO="${REPO:-usuario/repositorio-do-app}"
REQUIRED_SPACE_MB="${REQUIRED_SPACE_MB:-30}"
TEMP_DIR="${TMPDIR:-/tmp}/${APP_NAME}-update"
BACKUP_DIR="$INSTALL_DIR/backups"
DOWNLOAD_RELEASE="${DOWNLOAD_RELEASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/download-release.sh}"
RECIPE_VERSION_FILE="${RECIPE_VERSION_FILE:-$INSTALL_DIR/version.txt}"
PRESERVE_LIST=("gamedata/saves" "conf/settings.cfg" "media")
EXTENSION="${EXTENSION-sh}"
ACTION="${1:-update}"
IGNORE_ON_INSTALL="${IGNORE_ON_INSTALL-}"

die() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

require_commands() {
    local command_name
    for command_name in curl unzip zip df awk sed mktemp; do
        command -v "$command_name" >/dev/null 2>&1 || die "comando ausente: $command_name"
    done
    [ -x "$DOWNLOAD_RELEASE" ] || die "downloader não encontrado: $DOWNLOAD_RELEASE"
}

if [ "$ACTION" = "remove" ]; then
    if [ -n "$INSTALL_FILE" ]; then
        [ "$INSTALL_FILE" != "/" ] || die "arquivo de instalação inválido"
        if [ ! -f "$INSTALL_FILE" ]; then
            printf 'Item não está instalado.\n'
        else
            rm -f "$INSTALL_FILE"
            printf 'Item removido. Backups preservados em %s.\n' "$BACKUP_DIR"
        fi
    elif [ ! -d "$INSTALL_DIR" ]; then
        printf 'Item não está instalado.\n'
    else
        [ -n "$INSTALL_DIR" ] && [ "$INSTALL_DIR" != "/" ] || die "diretório de instalação inválido"
        find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name backups -exec rm -rf -- {} +
        printf 'Item removido. Backups preservados em %s.\n' "$BACKUP_DIR"
    fi
    exit 0
fi

if [ "$ACTION" = "backups" ]; then
    if [ ! -d "$BACKUP_DIR" ]; then
        printf 'Nenhum backup encontrado.\n'
    else
        backups_found=0
        while IFS= read -r backup; do
            backups_found=1
            basename "$backup"
        done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.zip' -print | sort)
        [ "$backups_found" -eq 1 ] || printf 'Nenhum backup encontrado.\n'
    fi
    exit 0
fi

latest_release_json=$(mktemp)
cleanup() {
    rm -rf "$TEMP_DIR" "$latest_release_json"
}
trap cleanup EXIT
require_commands

mkdir -p "$(dirname "$INSTALL_DIR")"
release_url="${RELEASE_URL:-https://api.github.com/repos/$REPO/releases/latest}"
curl -fsSL "$release_url" -o "$latest_release_json" || die "não foi possível consultar a release de $REPO"

if [ -z "$EXTENSION" ]; then die "A extensão da release não foi definida."
fi

if command -v jq >/dev/null 2>&1; then
    latest_tag=$(jq -r '.tag_name // empty' "$latest_release_json")
    download_url=$(jq -r --arg extension "$EXTENSION" '[.assets[]? | select(.browser_download_url | endswith($extension))][0].browser_download_url // empty' "$latest_release_json")
else
    latest_tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$latest_release_json" | head -n 1)
    download_url=$(sed -n "s|.*\"browser_download_url\"[[:space:]]*:[[:space:]]*\"\([^\"]*${EXTENSION}\)\".*|\1|p" "$latest_release_json" | head -n 1)
fi

[ -n "$latest_tag" ] || die "a API não retornou uma tag de release"
[ -n "$download_url" ] || die "a release não possui um arquivo ${EXTENSION}"

current_tag="v0.0.0"
[ -f "$RECIPE_VERSION_FILE" ] && current_tag=$(sed -n '1p' "$RECIPE_VERSION_FILE")
if [ "$latest_tag" = "$current_tag" ]; then
    printf 'Item já está na versão mais recente (%s).\n' "$current_tag"
    exit 0
fi

available_space_kb=$(df -Pk "$(dirname "$INSTALL_DIR")" | awk 'NR==2 {print $4}')
[ "${available_space_kb:-0}" -ge $((REQUIRED_SPACE_MB * 1024)) ] || \
    die "espaço insuficiente: disponível ${available_space_kb:-0}KB, necessário ${REQUIRED_SPACE_MB}MB"

mkdir -p "$BACKUP_DIR"
timestamp=$(date +%Y%m%d_%H%M%S)
backup_zip="$BACKUP_DIR/backup_${current_tag}_${timestamp}.zip"
if [ -n "$INSTALL_FILE" ] && [ -f "$INSTALL_FILE" ]; then
    zip -q -j "$backup_zip" "$INSTALL_FILE" || die "não foi possível criar o backup"
    printf 'Backup criado: %s\n' "$backup_zip"
elif [ -d "$INSTALL_DIR" ] && find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name backups -print -quit | grep -q .; then
    (cd "$INSTALL_DIR" && zip -qr "$backup_zip" . -x 'backups/*' -x 'tmp/*') || die "não foi possível criar o backup"
    printf 'Backup criado: %s\n' "$backup_zip"
fi

mkdir -p "$TEMP_DIR/extracted"
EXTENSION="$EXTENSION" "$DOWNLOAD_RELEASE" "$download_url" "$TEMP_DIR/extracted" || die "falha ao baixar e extrair a release"

if [ "$ACTION" = "install" ] && [ -n "$IGNORE_ON_INSTALL" ]; then
    IFS=: read -r -a ignored_paths <<< "$IGNORE_ON_INSTALL"
    for relative_path in "${ignored_paths[@]}"; do
        [ -n "$relative_path" ] && rm -rf "$TEMP_DIR/extracted/$relative_path"
    done
fi

preserve_dir="$TEMP_DIR/preserved"
mkdir -p "$preserve_dir"
for relative_path in "${PRESERVE_LIST[@]}"; do
    if [ -e "$INSTALL_DIR/$relative_path" ]; then
        mkdir -p "$preserve_dir/$(dirname "$relative_path")"
        cp -a "$INSTALL_DIR/$relative_path" "$preserve_dir/$relative_path"
    fi
done

if [ -n "$INSTALL_FILE" ]; then
    source_file="$(find "$TEMP_DIR/extracted" -type f -name "*${EXTENSION}" -print -quit)"
    [ -n "$source_file" ] || die "nenhum arquivo ${EXTENSION} encontrado na release"
    mkdir -p "$(dirname "$INSTALL_FILE")"
    cp -a "$source_file" "$INSTALL_FILE"
    chmod +x "$INSTALL_FILE"
else
    mkdir -p "$INSTALL_DIR"
    cp -a "$TEMP_DIR/extracted/." "$INSTALL_DIR/"
fi
for relative_path in "${PRESERVE_LIST[@]}"; do
    if [ -e "$preserve_dir/$relative_path" ]; then
        rm -rf "$INSTALL_DIR/$relative_path"
        mkdir -p "$(dirname "$INSTALL_DIR/$relative_path")"
        cp -a "$preserve_dir/$relative_path" "$INSTALL_DIR/$relative_path"
    fi
done

printf '%s\n' "$latest_tag" > "$RECIPE_VERSION_FILE"
if [ -z "$INSTALL_FILE" ] && [ "$RECIPE_VERSION_FILE" != "$INSTALL_DIR/version.txt" ]; then
    printf '%s\n' "$latest_tag" > "$INSTALL_DIR/version.txt"
fi
printf 'Atualizado para a versão %s com sucesso!\n' "$latest_tag"
