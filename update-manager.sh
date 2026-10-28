#!/bin/bash

set -u

if [ "$(id -u)" -ne 0 ] && [ -x /opt/inttools/gptokeyb ]; then
    exec sudo -- "$0" "$@"
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="$BASE_DIR/recipes"
MANAGER_RELEASE_URL="${MANAGER_RELEASE_URL:-}"
DOWNLOAD_RELEASE="$BASE_DIR/download-release.sh"
GPTOKEYB_BIN="${GPTOKEYB:-}"
DIALOG_TTY="${DIALOG_TTY:-/dev/tty1}"
KEYMAP_FILE="$BASE_DIR/r36s-manager.gptk"

[ -e "$DIALOG_TTY" ] || DIALOG_TTY="/dev/tty"
export TERM="${TERM:-linux}"

if [ -z "$GPTOKEYB_BIN" ] && [ -x /opt/inttools/gptokeyb ]; then
    GPTOKEYB_BIN=/opt/inttools/gptokeyb
fi

if [ -z "$GPTOKEYB_BIN" ]; then
    GPTOKEYB_BIN="$(command -v gptokeyb 2>/dev/null || true)"
fi

if [ -f /opt/inttools/keys.gptk ]; then
    KEYMAP_FILE=/opt/inttools/keys.gptk
fi

if [ -x "$GPTOKEYB_BIN" ] && [ "${R36S_GPTOKEYB_ACTIVE:-0}" != "1" ]; then
    export R36S_GPTOKEYB_ACTIVE=1
    if [ -f /opt/inttools/gamecontrollerdb.txt ]; then
        export SDL_GAMECONTROLLERCONFIG_FILE=/opt/inttools/gamecontrollerdb.txt
    fi
    [ -e /dev/uinput ] && chmod 666 /dev/uinput 2>/dev/null || true
    pkill -f gptokeyb 2>/dev/null || true
    "$GPTOKEYB_BIN" -1 "$(basename "$0")" \
        -c "$KEYMAP_FILE" \
        >>"$BASE_DIR/gptokeyb.log" 2>&1 &
    GPTOKEYB_PID=$!
    trap 'kill "$GPTOKEYB_PID" 2>/dev/null || true' EXIT
fi

log() {
    printf '%s\n' "$*"
}

show_message() {
    if command -v dialog >/dev/null 2>&1; then
        dialog --title "R36S Manager" --msgbox "$1" 10 60 >"$DIALOG_TTY"
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
    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#"$sync_dir/"}"
        destination_file="$BASE_DIR/$relative_path"
        mkdir -p "$(dirname "$destination_file")"
        cp -a "$source_file" "$destination_file"
    done < <(find "$sync_dir" -type f ! -name '*.version' -print0)
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
    local progress_dir log_file message output_status worker spinner_index spinner_char terminal
    progress_dir="$(mktemp -d)"
    log_file="$progress_dir/output.log"
    message="Processando"
    case "$action" in
        install) message="Instalando pacote" ;;
        update) message="Atualizando pacote" ;;
        remove) message="Removendo pacote" ;;
        backups) message="Consultando backups" ;;
    esac

    (run_recipe "$recipe" "$action" >"$log_file" 2>&1) &
    worker=$!
    spinner_index=0
    spinner='|/-\\'
    terminal="$DIALOG_TTY"

    while kill -0 "$worker" 2>/dev/null; do
        spinner_char="${spinner:spinner_index:1}"
        if [ -w "$terminal" ]; then
            printf '\r[%s] %s...' "$spinner_char" "$message" >"$terminal"
        fi
        spinner_index=$(((spinner_index + 1) % 4))
        sleep 0.2
    done

    wait "$worker"
    output_status=$?
    if [ -w "$terminal" ]; then
        if [ "$output_status" -eq 0 ]; then
            printf '\r[OK] %s concluído.\n' "$message" >"$terminal"
        else
            printf '\r[ERRO] %s falhou.\n' "$message" >"$terminal"
        fi
    fi
    cat "$log_file"
    rm -rf "$progress_dir"
    return "$output_status"
}

recipe_value() {
    local recipe="$1"
    local variable_name="$2"
    sed -n -E "s/^[[:space:]]*(export[[:space:]]+)?${variable_name}=([\"']?)([^\"']*)\2[[:space:]]*$/\3/p" "$recipe" | head -n 1
}

is_auto_update() {
    grep -q '^# AUTO_UPDATE:[[:space:]]*true' "$1"
}

recipe_version_file() {
    local recipe="$1"
    if is_auto_update "$recipe"; then
        printf '%s/version.txt' "$BASE_DIR"
    elif [[ "$recipe" == *.sh.sh ]]; then
        printf '%s.version' "${recipe%.sh}"
    else
        printf '%s.version' "$recipe"
    fi
}

current_version() {
    local recipe="$1"
    local version_file version install_file install_dir
    if ! is_auto_update "$recipe"; then
        install_file="$(recipe_value "$recipe" INSTALL_FILE)"
        install_dir="$(recipe_value "$recipe" INSTALL_DIR)"
        if [ -n "$install_file" ]; then
            [ -f "$install_file" ] || {
                printf 'não instalado'
                return
            }
        elif [ -n "$install_dir" ]; then
            [ -f "$install_dir/version.txt" ] || {
                printf 'não instalado'
                return
            }
        fi
    fi
    version_file="$(recipe_version_file "$recipe")"
    if [ -f "$version_file" ]; then
        version="$(sed -n '1p' "$version_file")"
        if [ -n "$version" ] && [ "$version" != "v0.0.0" ]; then
            printf '%s' "$version"
        else
            printf 'não instalado'
        fi
    else
        printf 'não instalado'
    fi
}

latest_version() {
    local recipe="$1"
    local repo release_url metadata_file latest_tag
    if is_auto_update "$recipe"; then
        release_url="${MANAGER_RELEASE_URL:-}"
        [ -n "$release_url" ] || return 0
    else
        repo="$(recipe_value "$recipe" REPO)"
        [ -n "$repo" ] || return 0
        release_url="${RELEASE_URL:-https://api.github.com/repos/$repo/releases/latest}"
    fi
    command -v curl >/dev/null 2>&1 || return 0

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
    local current_tag latest_tag
    current_tag="$(current_version "$recipe")"
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

if ! command -v dialog >/dev/null 2>&1; then
    show_message "Dependência ausente: dialog."
    exit 1
fi

while true; do
    menu_options=()
    recipe_files=()
    manager_version="v0.0.0"
    [ -f "$BASE_DIR/version.txt" ] && manager_version=$(sed -n '1p' "$BASE_DIR/version.txt")
    while IFS= read -r -d '' recipe; do
        filename="$(basename "$recipe")"
        [ "$filename" = "template-port.sh" ] && continue
        title="$(sed -n 's/^# TITLE:[[:space:]]*//p' "$recipe" | head -n 1)"
        [ -n "$title" ] || title="$filename"
        current_tag="$(current_version "$recipe")"
        status="$(package_status "$recipe")"
        recipe_files+=("$recipe")
        menu_options+=("$title ($current_tag)" "$status")
    done < <(find "$RECIPES_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

    if [ "${#menu_options[@]}" -eq 0 ]; then
        show_message "Nenhuma receita encontrada em recipes/."
        exit 1
    fi

    choice=$(dialog --backtitle "R36S GitHub Package Manager ($manager_version)" \
        --title "Pacotes disponíveis" \
        --ok-label "Selecionar" --cancel-label "Sair" \
        --menu "Selecione o item para instalar/atualizar:" \
        16 80 8 "${menu_options[@]}" 2>&1 >"$DIALOG_TTY")
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

    current_tag="$(current_version "$selected_recipe")"
    latest_tag="$(latest_version "$selected_recipe")"
    [ -n "$latest_tag" ] || latest_tag="indisponível"
    if [ "$current_tag" = "não instalado" ]; then
        primary_action="install"
        primary_label="Instalar | atual: não instalado | latest: $latest_tag"
    else
        primary_action="update"
        primary_label="Atualizar | atual: $current_tag | latest: $latest_tag"
    fi

    action=$(dialog --backtitle "R36S GitHub Package Manager ($manager_version)" \
        --title "$choice" \
        --ok-label "Selecionar" --cancel-label "Voltar" \
        --menu "Selecione a ação:" \
        16 80 6 \
        "$primary_action" "$primary_label" \
        "remove" "Remover pacote | atual: $current_tag" \
        "backups" "Listar backups" \
        2>&1 >"$DIALOG_TTY")
    [ $? -eq 0 ] || continue

    if [ "$action" = "backups" ]; then
        if output=$(run_recipe_with_progress "$selected_recipe" "$action" 2>&1); then
            dialog --backtitle "R36S GitHub Package Manager ($manager_version)" \
                --title "Backups - $choice" --msgbox "$output" 16 80 >"$DIALOG_TTY"
        else
            dialog --title "Erro" --msgbox "$output" 14 70 >"$DIALOG_TTY"
        fi
        continue
    fi

    if dialog --title "Confirmação" --yesno "Deseja executar:\n\n$action em $choice?" 10 60 >"$DIALOG_TTY"; then
        if output=$(run_recipe_with_progress "$selected_recipe" "$action" 2>&1); then
            dialog --title "Sucesso" --msgbox "$output" 12 70 >"$DIALOG_TTY"
        else
            dialog --title "Erro" --msgbox "$output" 14 70 >"$DIALOG_TTY"
        fi
    fi
done
