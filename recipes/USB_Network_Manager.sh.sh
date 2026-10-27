#!/bin/bash
# TITLE: USBNetworkManager
# AUTHOR: Comunidade R36S
# REPO: usuario/repositorio-do-app

export REPO=Just-Luis/BatleXP-G350_USBNetworkManager
export APP_NAME=USB Network Manager
export INSTALL_DIR=/roms/tools/USBNetworkManager
export EXTENSION=.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RECIPE_VERSION_FILE="$SCRIPT_DIR/USB_Network_Manager.sh.version"
exec bash "$SCRIPT_DIR/template-port.sh" "$@"
