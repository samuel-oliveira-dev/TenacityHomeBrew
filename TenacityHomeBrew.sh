#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER_DIR="${TENACITY_HOMEBREW_DIR:-$SCRIPT_DIR}"

if [ ! -x "$MANAGER_DIR/update-manager.sh" ] && [ -x "$SCRIPT_DIR/TenacityHomeBrew/update-manager.sh" ]; then
    MANAGER_DIR="$SCRIPT_DIR/TenacityHomeBrew"
fi

if [ ! -x "$MANAGER_DIR/update-manager.sh" ]; then
    printf 'Erro: update-manager.sh não encontrado em %s\n' "$MANAGER_DIR" >&2
    exit 1
fi

exec "$MANAGER_DIR/update-manager.sh" "$@"
