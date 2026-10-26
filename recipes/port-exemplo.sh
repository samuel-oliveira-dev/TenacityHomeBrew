#!/bin/bash
# TITLE: Exemplo de Port/Tool
# AUTHOR: Comunidade R36S
# REPO: usuario/repositorio-do-app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/template-port.sh"
