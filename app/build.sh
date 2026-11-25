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

# assinatura com um certificado local, o mesmo em toda montagem: o macOS reconhece o app pelo certificado e lembra das
# permissões que você deu (pasta Documentos, notificações). Ad hoc, cada montagem virava "outro app" e pedia tudo de
# novo. O certificado "jfy local" é criado na primeira vez, no seu Chaves, liberado só para o codesign.
# ponytail: vale para este Mac. Para mandar o .app a outra pessoa: Developer ID + notarização
ID="jfy local"
if ! security find-identity -p codesigning | grep -q "\"$ID\""; then
  T="$(mktemp -d)"
  SENHA="$(openssl rand -hex 16)"
  printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=%s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$ID" > "$T/cfg"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/chave.pem" -out "$T/cert.pem" -days 3650 -config "$T/cfg" 2>/dev/null
  openssl pkcs12 -export -inkey "$T/chave.pem" -in "$T/cert.pem" -name "$ID" -out "$T/id.p12" -passout "pass:$SENHA"
  security import "$T/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$SENHA" -T /usr/bin/codesign -f pkcs12 >/dev/null
  rm -rf "$T"
  printf '\033[32m✓\033[0m certificado "%s" criado no seu Chaves (assinatura estável do app)\n' "$ID"
fi
codesign --force --sign "$ID" "$APP" 2>/dev/null || codesign --force --sign - "$APP"  # sem o certificado: ad hoc

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
rm -rf "$DEST/jfy.app"
cp -R "$APP" "$DEST/"
printf '\033[32m✓\033[0m jfy.app em %s\n' "$DEST"
