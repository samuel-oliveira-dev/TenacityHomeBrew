#!/bin/bash
# TITLE: Need for Speed Underground 2 (R36S)
# AUTHOR: manuelpllull
# REPO: manuelpllull/nfsu2-recompiled-r36s

export REPO=manuelpllull/nfsu2-recompiled-r36s
export APP_NAME=nfsu2
export INSTALL_DIR=/home/samueloliveira/Documentos/Ports
export EXTENSION=.zip
export IGNORE_ON_INSTALL=gamedata

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/template-port.sh" "$@"
