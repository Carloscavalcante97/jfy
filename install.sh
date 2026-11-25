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
  aviso "Falta o MCP do Journify: na primeira vez, o jfy pede o seu token e configura"
fi

# ---------- extras: cada um pergunta antes; o que já está ligado só é atualizado, sem perguntar de novo ----------
quer() { local r; read -r -p "  $1 (s/n) [s] " r </dev/tty || return 1; [ "${r:-s}" = s ]; }
ja() { grep -qs -- "$1" "$HOME/.claude/settings.json"; }
ajustar() {  # ajustar ia|aviso: liga a barra de uso da IA ou o aviso do Claude no ~/.claude/settings.json
  /usr/bin/python3 - "$1" "$DIR/jfy" <<'EOF'
import json, os, shlex, sys
p = os.path.expanduser("~/.claude/settings.json")
try:
    s = json.load(open(p)) if os.path.exists(p) else {}
except ValueError as e:
    sys.exit(f"  ~/.claude/settings.json não é um JSON válido ({e}): não mexi nele")
if sys.argv[1] == "ia":  # o statusline passa a gravar uma cópia do que recebe em ~/.jfy/claude-status.json
    sl = s.get("statusLine") or {"type": "command", "command": "cat >/dev/null"}
    if "claude-status.json" not in sl.get("command", ""):
        sl["command"] = "tee ~/.jfy/claude-status.json | " + sl["command"]
        s["statusLine"] = sl
else:  # hooks Stop/Notification: jfy --avisar
    cmd, hooks = shlex.quote(sys.argv[2]) + " --avisar", s.setdefault("hooks", {})
    for ev, grupo in (("Stop", {}), ("Notification", {"matcher": "permission_prompt|elicitation_dialog"})):
        if not any("jfy" in h.get("command", "") and "--avisar" in h.get("command", "")
                   for g in hooks.get(ev, []) for h in g.get("hooks", [])):
            hooks.setdefault(ev, []).append(dict(grupo, hooks=[{"type": "command", "command": cmd}]))
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(s, open(p, "w"), indent=2, ensure_ascii=False)
EOF
}
echo
echo "Extras (opcionais; n em todos deixa só o menu de tasks):"
if ja "claude-status.json" || quer "Uso da IA na barra do jfy? Muda o statusLine do ~/.claude/settings.json."; then
  mkdir -p "$HOME/.jfy"
  ajustar ia && ok "uso da IA na barra do jfy" || aviso "não liguei o uso da IA"
fi
if ja "jfy.*--avisar" || quer "Aviso no macOS quando o Claude responde ou pede permissão? Liga dois hooks no ~/.claude/settings.json (valem para todo Claude Code, dentro e fora do jfy) e instala o terminal-notifier."; then
  if ! command -v terminal-notifier >/dev/null; then  # notificação clicável; sem ele, a do osascript (clique não faz nada)
    if command -v brew >/dev/null; then brew install terminal-notifier; else aviso "sem Homebrew: notificações sem clique"; fi
  fi
  ajustar aviso && ok "aviso do Claude no macOS" || aviso "não liguei o aviso do Claude"
fi
# fonte JFY Mono (Maple Mono + ícones em pixel art dos temas): sempre; sem ela os temas mostram "?"
mkdir -p "$HOME/Library/Fonts"
cp "$DIR/fonte/JFYMono.ttf" "$HOME/Library/Fonts/JFYMono.ttf"
ok "fonte JFY Mono instalada"
if quer "Usar a JFY Mono neste terminal? (Terminal do macOS ou Warp; o tamanho da letra continua)"; then
  ok "$("$DIR/jfy" --fonte)"
else
  aviso "escolha \"JFY Mono\" como fonte do seu terminal e reabra ele, senão os ícones dos temas aparecem como ?"
fi
# ícone do jfy na barra de cima do Mac: plugin do SwiftBar que roda o jfy --mac a cada minuto e quando o menu abre
PLUG="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || echo "$HOME/.jfy/swiftbar")"
if [ -f "$PLUG/jfy.1m.sh" ] || quer "Ícone do jfy na barra de cima do Mac (abrir o jfy, jornada, reuniões, foco, portas abertas)? Instala o SwiftBar."; then
  if [ ! -d /Applications/SwiftBar.app ]; then
    if command -v brew >/dev/null; then brew install --cask swiftbar; else aviso "sem Homebrew: instale o SwiftBar (swiftbar.app) e rode de novo"; fi
  fi
  if [ -d /Applications/SwiftBar.app ]; then
    mkdir -p "$PLUG"
    defaults write com.ameba.SwiftBar PluginDirectory "$PLUG"
    cat > "$PLUG/jfy.1m.sh" <<EOF
#!/bin/sh
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec "$DIR/jfy" --mac
EOF
    chmod +x "$PLUG/jfy.1m.sh"
    # abre o SwiftBar quando o Mac liga (e o jfy reabre se ele for fechado)
    SB="$HOME/Library/LaunchAgents/jfy.swiftbar.plist"
    mkdir -p "$(dirname "$SB")"
    cat > "$SB" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>jfy.swiftbar</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>/Applications/SwiftBar.app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
    launchctl bootout "gui/$(id -u)/jfy.swiftbar" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$SB" && ok "ícone do jfy na barra de cima, abre junto com o Mac (SwiftBar, plugins em ${PLUG/#$HOME/~})"
  fi
fi
PLIST="$HOME/Library/LaunchAgents/jfy.dia.plist"
if [ -f "$PLIST" ] || quer "Notificação às 7h (seg a sex) com as reuniões e as tasks no foco? Cria um LaunchAgent."; then
  DIAS=""; for d in 1 2 3 4 5; do DIAS="$DIAS<dict><key>Weekday</key><integer>$d</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>"; done
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>jfy.dia</string>
  <key>ProgramArguments</key><array><string>$DIR/jfy</string><string>--notificar</string></array>
  <key>StartCalendarInterval</key><array>$DIAS</array>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)/jfy.dia" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" && ok "notificação do dia às 7h (seg a sex)"
fi
echo

"$DIR/jfy" --selftest >/dev/null && ok "autoteste"
echo
echo "Pronto. Rode: jfy"
echo "Na primeira vez ele te guia pelo resto: Journify, notificações, agenda e Gmail, seus projetos e tema."
