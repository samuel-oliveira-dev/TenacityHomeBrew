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

    EXTENSION=.zip "$DOWNLOAD_RELEASE" "$MANAGER_RELEASE_URL" "$sync_dir" || return 0
    cp -a "$sync_dir/." "$BASE_DIR/"
    rm -rf "$sync_dir"
}

run_recipe() {
    local recipe="$1"
    local action="$2"
    if [ ! -x "$recipe" ]; then
        chmod +x "$recipe" 2>/dev/null || true
    fi
    bash "$recipe" "$action"
}

run_recipe_with_progress() {
    local recipe="$1"
    local action="$2"
    local progress_dir log_file status_file message percent output_status
    progress_dir="$(mktemp -d)"
    log_file="$progress_dir/output.log"
    status_file="$progress_dir/status"
    message="Processando"
    case "$action" in
        install) message="Instalando pacote" ;;
        update) message="Atualizando pacote" ;;
        remove) message="Removendo pacote" ;;
        backups) message="Consultando backups" ;;
    esac

    (run_recipe "$recipe" "$action" >"$log_file" 2>&1; printf '%s' "$?" >"$status_file") &
    (
        percent=5
        while [ ! -f "$status_file" ]; do
            printf '%s\n' "$percent"
            printf 'XXX\n%s\n%s%% - %s\nXXX\n' "$percent" "$percent" "$message"
            percent=$((percent + 5))
            [ "$percent" -le 90 ] || percent=90
            sleep 1
        done
        printf '100\n'
        printf 'XXX\n100\n100%% - Concluído\nXXX\n'
    ) | whiptail --title "Aguarde" --gauge "$message..." 8 70 0

    output_status="$(sed -n '1p' "$status_file" 2>/dev/null || printf '1')"
    cat "$log_file"
    rm -rf "$progress_dir"
    return "$output_status"
}

recipe_value() {
    local recipe="$1"
    local variable_name="$2"
    sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?${variable_name}=([\"']?)([^\"']*)\2[[:space:]]*$/\3/p" "$recipe" | head -n 1
}

current_version() {
    local install_dir="$1"
    if [ -f "$install_dir/version.txt" ]; then
        sed -n '1p' "$install_dir/version.txt"
    else
        printf 'não instalado'
    fi
}

latest_version() {
    local recipe="$1"
    local repo release_url metadata_file latest_tag
    repo="$(recipe_value "$recipe" REPO)"
    [ -n "$repo" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    release_url="${RELEASE_URL:-https://api.github.com/repos/$repo/releases/latest}"
    metadata_file="$(mktemp)"
    if ! curl -fsSL --max-time 8 "$release_url" -o "$metadata_file" 2>/dev/null; then
        rm -f "$metadata_file"
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        latest_tag=$(jq -r '.tag_name // empty' "$metadata_file")
    else
        latest_tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata_file" | head -n 1)
    fi
    rm -f "$metadata_file"
    printf '%s' "$latest_tag"
}

package_status() {
    local recipe="$1"
    local install_dir current_tag latest_tag
    install_dir="$(recipe_value "$recipe" INSTALL_DIR)"
    current_tag="$(current_version "$install_dir")"
    latest_tag="$(latest_version "$recipe")"

    if [ -z "$latest_tag" ]; then
        printf '(%s) | release indisponível' "$current_tag"
    elif [ "$current_tag" = "não instalado" ]; then
        printf 'não instalado | latest: %s' "$latest_tag"
    elif [ "$latest_tag" = "$current_tag" ]; then
        printf '(%s) | Updated' "$current_tag"
    else
        printf '(%s)| Available: %s' "$current_tag" "$latest_tag"
    fi
}

sync_manager
mkdir -p "$RECIPES_DIR"

if ! command -v whiptail >/dev/null 2>&1; then
    show_message "Dependência ausente: whiptail."
    exit 1
fi

while true; do
    menu_options=()
    recipe_files=()
    while IFS= read -r -d '' recipe; do
        filename="$(basename "$recipe")"
        [ "$filename" = "template-port.sh" ] && continue
        title="$(sed -n 's/^# TITLE:[[:space:]]*//p' "$recipe" | head -n 1)"
        [ -n "$title" ] || title="$filename"
        status="$(package_status "$recipe")"
        recipe_files+=("$recipe")
        menu_options+=("$title" "$status")
    done < <(find "$RECIPES_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

    if [ "${#menu_options[@]}" -eq 0 ]; then
        show_message "Nenhuma receita encontrada em recipes/."
        exit 1
    fi

    choice=$(whiptail --title "R36S GitHub Package Manager" \
        --menu "Selecione o item para instalar/atualizar:" \
        16 70 8 "${menu_options[@]}" 3>&1 1>&2 2>&3)
    [ $? -eq 0 ] || exit 0

    selected_recipe=""
    for index in "${!recipe_files[@]}"; do
        menu_index=$((index * 2))
        if [ "${menu_options[$menu_index]}" = "$choice" ]; then
            selected_recipe="${recipe_files[$index]}"
            break
        fi
    done

    [ -n "$selected_recipe" ] || continue

    install_dir="$(recipe_value "$selected_recipe" INSTALL_DIR)"
    current_tag="$(current_version "$install_dir")"
    latest_tag="$(latest_version "$selected_recipe")"
    [ -n "$latest_tag" ] || latest_tag="indisponível"
    if [ "$current_tag" = "não instalado" ]; then
        primary_action="install"
        primary_label="Instalar | atual: não instalado | latest: $latest_tag"
    else
        primary_action="update"
        primary_label="Atualizar | atual: $current_tag | latest: $latest_tag"
    fi

    action=$(whiptail --title "$choice" \
        --menu "Selecione a ação:" \
        16 80 6 \
        "$primary_action" "$primary_label" \
        "remove" "Remover pacote | atual: $current_tag" \
        "backups" "Listar backups" \
        3>&1 1>&2 2>&3)
    [ $? -eq 0 ] || continue

    if [ "$action" = "backups" ]; then
        if output=$(run_recipe_with_progress "$selected_recipe" "$action" 2>&1); then
            whiptail --title "Backups - $choice" --msgbox "$output" 16 80
        else
            whiptail --title "Erro" --msgbox "$output" 14 70
        fi
        continue
    fi

    if whiptail --title "Confirmação" --yesno "Deseja executar:\n\n$action em $choice?" 10 60; then
        if output=$(run_recipe_with_progress "$selected_recipe" "$action" 2>&1); then
            whiptail --title "Sucesso" --msgbox "$output" 12 70
        else
            whiptail --title "Erro" --msgbox "$output" 14 70
        fi
    fi
done
