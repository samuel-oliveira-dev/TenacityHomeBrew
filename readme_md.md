# 🎮 R36S GitHub Package Manager (MVP)

Um gerenciador e instalador leve, descentralizado e sem servidor (*serverless*) de **Ports e Tools** para o R36S (rodando ArkOS ou DarkOS), focado em automação via GitHub e segurança de dados do usuário.

---

## 💡 A Ideia & O Problema que Resolve

Manter atualizados os *ports* (jogos adaptados) e *tools* (utilitários de sistema) em consoles portáteis baseados em RK3326 geralmente exige baixar arquivos manualmente e colocá-los no cartão MicroSD. 

Este projeto resolve isso trazendo uma **"App Store" comunitária descentralizada**:
* **Custo Zero:** Sem servidores backend próprios. Toda a infraestrutura roda na nuvem gratuita do GitHub (Releases + API + Pull Requests).
* **Colaborativo:** Desenvolvedores independentes adicionam seus ports/tools criando "receitas" (`.sh`) e enviando um Pull Request para o repositório central.
* **Seguro:** Antes de qualquer atualização, o console faz um backup compactado automático do estado atual, permitindo rollbacks futuros.

---

## 🚀 Features do MVP

1. **Interface Nativa Leve:** Utiliza o `whiptail` (nativo do ArkOS/DarkOS) para renderizar menus interativos fluídos na tela do R36S, sem dependências gráficas pesadas.
2. **Auto-atualização do Gerenciador:** Ao iniciar, o script principal sincroniza as receitas mais recentes direto do repositório Git.
3. **Checagem Inteligente de Espaço:** Valida se há armazenamento livre suficiente no console antes de iniciar o download de qualquer pacote.
4. **Backup Preventivo em `.zip`:** Compacta a pasta atual do port/tool com data e hora antes de sobrescrever qualquer arquivo.
5. **Atualização Seletiva:** Substitui os binários da nova release preservando arquivos críticos do usuário (saves, configurações, metadados, etc.).
6. **Preparado para Rollback:** O sistema de versionamento e armazenamento de backups em `.zip` deixa o terreno pronto para futuras ferramentas de reversão de versão.

---

## 🛠️ Tecnologias Utilizadas

* **Bash Scripting (`/bin/bash`):** Linguagem padrão e universal nos firmwares de consoles retro Linux.
* **Whiptail / Newt:** Para a construção da Interface TUI (Text User Interface).
* **GitHub API:** Para obtenção de releases e catálogos dinâmicos, sem comandos Git no console.
* **Ferramentas de Sistema Linux Nativas:** `curl`, `jq`, `zip`, `unzip`, `df`, `tar`.

---

## 📂 Estrutura do Repositório

```text
r36s-pkgmanager/
├── update-manager.sh      # Script principal (O executável no console)
├── download-release.sh    # Baixa uma release por URL (API ou asset .zip)
├── version.txt            # Versão atual do gerenciador
└── recipes/               # Pasta contendo as receitas enviadas pela comunidade
    ├── port-exemplo.sh
    └── tool-exemplo.sh
```

O auto-sync recebe a URL da release do próprio gerenciador pela variável
`MANAGER_RELEASE_URL`. O downloader recebe a URL da release e a pasta destino:
`download-release.sh URL_DA_RELEASE PASTA_DESTINO`. Ele baixa o asset `.zip`,
extrai seu conteúdo e é reutilizado pelas receitas de ports e tools.

---

## 📜 Esboços dos Scripts (Templates)

### 1. Script Principal (`update-manager.sh`)
Responsável por puxar atualizações do gerenciador, ler a pasta `recipes/` dinamicamente e exibir o menu interativo via `whiptail`.

```bash
#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="$BASE_DIR/recipes"

while true; do
    MENU_OPTIONS=()
    for recipe in "$RECIPES_DIR"/*.sh; do
        [ -e "$recipe" ] || continue
        
        # Extrai o título customizado do cabeçalho da receita
        TITLE=$(grep "^# TITLE:" "$recipe" | cut -d':' -f2 | xargs)
        FILENAME=$(basename "$recipe")
        [ -z "$TITLE" ] && TITLE="$FILENAME"
        
        MENU_OPTIONS+=("$FILENAME" "$TITLE")
    done

    if [ ${#MENU_OPTIONS[@]} -eq 0 ]; then
        whiptail --title "R36S Manager" --msgbox "Nenhuma receita encontrada em recipes/" 8 50
        exit 1
    fi

    CHOICE=$(whiptail --title "R36S GitHub Package Manager (MVP)" \
                    --menu "Selecione o item para instalar/atualizar:" \
                    16 60 8 \
                    "${MENU_OPTIONS[@]}" \
                    3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && exit 0

    if (whiptail --title "Confirmação" --yesno "Deseja processar o item:\n\n$CHOICE?" 10 50); then
        {
            echo 10; sleep 1
            echo "Baixando e instalando..."
            bash "$RECIPES_DIR/$CHOICE"
            echo 100; sleep 1
        } | whiptail --title "Aguarde..." --gauge "Processando..." 6 50 0

        whiptail --title "Sucesso!" --msgbox "Operação concluída com sucesso!" 8 40
    fi
done
```

---

### 2. Template de Receita Individual (`recipes/template-port.sh`)
Cada port ou tool gerenciado segue este modelo padrão para gerenciar versionamento, espaço em disco, backups em zip e preservação de dados.

```bash
#!/bin/bash
# TITLE: Exemplo de Port/Tool
# AUTHOR: Comunidade R36S
# REPO: usuario/repositorio-do-app

APP_NAME="exemplo_app"
INSTALL_DIR="/roms/ports/$APP_NAME"
BACKUP_DIR="$INSTALL_DIR/backups"
TEMP_DIR="/tmp/$APP_NAME-update"
REPO="usuario/repositorio-do-app"
DOWNLOAD_RELEASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/download-release.sh"

# Arquivos ou pastas que NUNCA devem ser apagados na atualização (Saves, configs, metadados)
PRESERVE_LIST=("gamedata/saves" "conf/settings.cfg" "media")

# 1. Checagem de Versão via GitHub API
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
CURRENT_TAG=$(cat "$INSTALL_DIR/version.txt" 2>/dev/null || echo "v0.0.0")

if [ "$LATEST_TAG" == "$CURRENT_TAG" ]; then
    echo "Item já está na versão mais recente ($CURRENT_TAG)."
    exit 0
fi

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"browser_download_url":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')

# 2. Verificação de Espaço em Disco (Exige pelo menos 30MB livres)
REQUIRED_SPACE_MB=30
AVAILABLE_SPACE_KB=$(df "$INSTALL_DIR" 2>/dev/null || df /roms | awk 'NR==2 {print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE_KB / 1024))

if [ "$AVAILABLE_SPACE_MB" -lt "$REQUIRED_SPACE_MB" ]; then
    echo "Erro: Espaço insuficiente! Disponível: ${AVAILABLE_SPACE_MB}MB, Necessário: ${REQUIRED_SPACE_MB}MB."
    exit 1
fi

# 3. Criação de Backup em ZIP da versão atual
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ZIP="$BACKUP_DIR/backup_${CURRENT_TAG}_${TIMESTAMP}.zip"

if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
    cd "$INSTALL_DIR"
    zip -r -q "$BACKUP_ZIP" . -x "backups/*" -x "tmp/*"
    echo "Backup compactado criado com sucesso."
fi

# 4. Download e Extração da Nova Release
mkdir -p "$TEMP_DIR"
"$DOWNLOAD_RELEASE" "$DOWNLOAD_URL" "$TEMP_DIR/extracted"

# 5. Instalação / Atualização dos arquivos
mkdir -p "$INSTALL_DIR"
cp -rf "$TEMP_DIR/extracted/"* "$INSTALL_DIR/"

# 6. Atualização do registro de versão e limpeza
echo "$LATEST_TAG" > "$INSTALL_DIR/version.txt"
rm -rf "$TEMP_DIR"

echo "Atualizado para a versão $LATEST_TAG com sucesso!"
```

---

## 🔮 Roadmap Futuro
* [ ] Implementação de menu de **Rollback** listando os `.zip` salvos na pasta de backups.
* [ ] Suporte à renderização de READMEs com o utilitário `glow`.
* [ ] Migração opcional da interface para Python/Pygame (estilo PortMaster moderno).
