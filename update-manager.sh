#!/bin/bash

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="$BASE_DIR/recipes"
MANAGER_RELEASE_URL="${MANAGER_RELEASE_URL:-}"
DOWNLOAD_RELEASE="$BASE_DIR/download-release.sh"

log() {
    printf '%s\n' "$*"
}

show_message() {
    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "R36S Manager" --msgbox "$1" 10 60
    else
        log "$1"
    fi
}

sync_manager() {
    [ -n "$MANAGER_RELEASE_URL" ] || return 0
    [ -x "$DOWNLOAD_RELEASE" ] || return 0

    local sync_dir
    sync_dir="${TMPDIR:-/tmp}/r36s-manager-sync"
    rm -rf "$sync_dir"
    mkdir -p "$sync_dir"

    "$DOWNLOAD_RELEASE" "$MANAGER_RELEASE_URL" "$sync_dir" || return 0
    cp -a "$sync_dir/." "$BASE_DIR/"
    rm -rf "$sync_dir"
}

run_recipe() {
    local recipe="$1"
    if [ ! -x "$recipe" ]; then
        chmod +x "$recipe" 2>/dev/null || true
    fi
    bash "$recipe"
}

sync_manager
mkdir -p "$RECIPES_DIR"

if ! command -v whiptail >/dev/null 2>&1; then
    show_message "Dependência ausente: whiptail."
    exit 1
fi

while true; do
    menu_options=()
    while IFS= read -r -d '' recipe; do
        title="$(sed -n 's/^# TITLE:[[:space:]]*//p' "$recipe" | head -n 1)"
        filename="$(basename "$recipe")"
        [ -n "$title" ] || title="$filename"
        menu_options+=("$filename" "$title")
    done < <(find "$RECIPES_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

    if [ "${#menu_options[@]}" -eq 0 ]; then
        show_message "Nenhuma receita encontrada em recipes/."
        exit 1
    fi

    choice=$(whiptail --title "R36S GitHub Package Manager" \
        --menu "Selecione o item para instalar/atualizar:" \
        16 70 8 "${menu_options[@]}" 3>&1 1>&2 2>&3)
    [ $? -eq 0 ] || exit 0

    if whiptail --title "Confirmação" --yesno "Deseja processar o item:\n\n$choice?" 10 60; then
        if output=$(run_recipe "$RECIPES_DIR/$choice" 2>&1); then
            whiptail --title "Sucesso" --msgbox "$output" 12 70
        else
            whiptail --title "Erro" --msgbox "$output" 14 70
        fi
    fi
done
