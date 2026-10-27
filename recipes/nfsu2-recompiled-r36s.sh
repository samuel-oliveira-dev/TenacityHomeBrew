#!/bin/bash
# TITLE: Need for Speed Underground 2 (R36S)
# AUTHOR: manuelpllull
# REPO: manuelpllull/nfsu2-recompiled-r36s

export REPO=manuelpllull/nfsu2-recompiled-r36s
export APP_NAME=nfsu2
export INSTALL_DIR=/roms/ports/nfsu2
export EXTENSION=.zip
export IGNORE_ON_INSTALL=gamedata

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RECIPE_VERSION_FILE="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}").version"
exec bash "$SCRIPT_DIR/template-port.sh" "$@"
