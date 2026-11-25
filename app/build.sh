#!/bin/bash
# Monta o jfy.app (o jfy numa janela própria, com uso da IA e chat) e instala em /Applications.
# Rode de novo depois de um git pull. Precisa do Xcode (ou das Command Line Tools) para o Swift.
set -e
cd "$(dirname "$0")"
REPO="$(cd .. && pwd)"
APP="build/jfy.app"

swift build -c release --product JFY
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp .build/release/JFY "$APP/Contents/MacOS/JFY"
cp "$REPO/fonte/JFYMono.ttf" "$APP/Contents/Resources/"  # carregada pelo ATSApplicationFontsPath, sem instalar

# ícone: a chama do jfy nos tamanhos que o macOS pede
"$REPO/jfy" --icone build/chama.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/chama.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/chama.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.jfy.mac</string>
  <key>CFBundleName</key><string>jfy</string>
  <key>CFBundleDisplayName</key><string>jfy</string>
  <key>CFBundleExecutable</key><string>JFY</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.$(git -C "$REPO" rev-list --count HEAD)</string>
  <key>CFBundleVersion</key><string>$(git -C "$REPO" rev-list --count HEAD)</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>.</string>
  <key>JFYScript</key><string>$REPO/jfy</string>
</dict></plist>
EOF

# ponytail: assinatura local (ad hoc), roda neste Mac. Para mandar o .app a outra pessoa: Developer ID + notarização
codesign --force --sign - "$APP"

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
rm -rf "$DEST/jfy.app"
cp -R "$APP" "$DEST/"
printf '\033[32m✓\033[0m jfy.app em %s\n' "$DEST"
