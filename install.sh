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

# /pipeline e agentes: symlink, então um git pull já atualiza. Não sobrescreve arquivo seu.
for f in "$DIR"/claude/commands/*.md "$DIR"/claude/agents/*.md; do
  rel="${f#$DIR/claude/}"
  dest="$HOME/.claude/$rel"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] || [ ! -e "$dest" ]; then
    ln -sf "$f" "$dest"
  elif cmp -s "$f" "$dest"; then
    ln -sf "$f" "$dest"  # igual ao do repo: troca pelo link para receber as atualizações
  else
    aviso "~/.claude/$rel já existe e é diferente do repo, mantive o seu"
    continue
  fi
done
ok "/pipeline e agentes em ~/.claude"

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
