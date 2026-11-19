#!/bin/bash
# Instala o jfy: confere dependências, coloca o comando no PATH e liga o /pipeline no ~/.claude.
# Pode rodar de novo quando quiser (depois de um git pull, por exemplo).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ok() { printf '\033[32m✓\033[0m %s\n' "$1"; }
aviso() { printf '\033[33m!\033[0m %s\n' "$1"; }
erro() { printf '\033[31m✗\033[0m %s\n' "$1"; exit 1; }

[ "$(uname)" = Darwin ] || erro "O jfy foi feito para macOS."
[ -x /usr/bin/python3 ] && /usr/bin/python3 -c 'import ssl' 2>/dev/null || erro "Falta o Python do macOS. Rode: xcode-select --install"
ok "python3 do macOS"

command -v claude >/dev/null || erro "Falta o Claude Code. Instale: https://docs.claude.com/claude-code"
ok "Claude Code"

if ! command -v tmux >/dev/null; then
  command -v brew >/dev/null || erro "Falta o tmux e o Homebrew. Instale o Homebrew (https://brew.sh) e rode de novo."
  brew install tmux
fi
ok "tmux"

# comando jfy no PATH
for BIN in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  [ -d "$BIN" ] && [ -w "$BIN" ] && break
done
mkdir -p "$BIN"
chmod +x "$DIR/jfy"
ln -sf "$DIR/jfy" "$BIN/jfy"
ok "comando jfy em $BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) aviso "$BIN não está no PATH. Adicione ao ~/.zshrc: export PATH=\"$BIN:\$PATH\"";; esac

# /pipeline, agentes e hooks: do repo oficial da pipeline, por symlink, então atualizar o repo já atualiza.
# Não sobrescreve arquivo seu.
PIPE="$HOME/.jfy/pipeline-Claude"
if [ -d "$PIPE/.git" ]; then
  git -C "$PIPE" pull -q --ff-only || aviso "não consegui atualizar $PIPE, segui com a versão atual"
else
  git clone -q https://github.com/Carloscavalcante97/pipeline-Claude.git "$PIPE" || erro "Não consegui clonar a pipeline"
fi
ligar() {  # ligar <arquivo do repo> <destino em ~/.claude>
  mkdir -p "$(dirname "$2")"
  if [ -L "$2" ] || [ ! -e "$2" ] || cmp -s "$1" "$2"; then
    ln -sf "$1" "$2"
  else
    aviso "${2/#$HOME/~} já existe e é diferente da pipeline oficial, mantive o seu"
  fi
}
ligar "$PIPE/pipeline.md" "$HOME/.claude/commands/pipeline.md"
for f in "$PIPE"/agents/*.md; do ligar "$f" "$HOME/.claude/agents/$(basename "$f")"; done
for f in "$PIPE"/hooks/*.sh; do ligar "$f" "$HOME/.claude/hooks/pipeline/$(basename "$f")"; done
ok "/pipeline, agentes e hooks em ~/.claude (de github.com/Carloscavalcante97/pipeline-Claude)"

# MCP do Journify
if /usr/bin/python3 -c "import json,os,sys; sys.exit(0 if json.load(open(os.path.expanduser('~/.claude.json'))).get('mcpServers',{}).get('journify') else 1)" 2>/dev/null; then
  ok "MCP do Journify"
else
  aviso "Falta o MCP do Journify. Rode (com o SEU token):"
  echo '  claude mcp add --transport http journify https://journify.souv.tech/api/mcp/journify/mcp \'
  echo '    --header "Authorization: Bearer SEU_TOKEN" --scope user'
fi

"$DIR/jfy" --selftest >/dev/null && ok "autoteste"
echo
echo "Pronto. Rode: jfy"
