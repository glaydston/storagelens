#!/usr/bin/env bash
# Builds StorageLens-<version>.dmg — the drag-to-Applications installer.
#
# A DMG is the least-effort thing to hand someone: open it, drag the icon onto
# the Applications shortcut, done. No Terminal, no unzip-to-the-wrong-folder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="StorageLens"
APP="$ROOT/build/$APP_NAME.app"
STAGING="$ROOT/build/dmg"

[[ -d "$APP" ]] || "$ROOT/Scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"

echo "==> Staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
# ditto rather than cp: it preserves the code signature and extended attributes.
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# The build isn't notarized, so Gatekeeper blocks the first double-click. Ship
# the way around it in the window itself, in the three languages the app speaks.
cat > "$STAGING/First launch — Leia-me — Léeme.txt" <<'TXT'
StorageLens

EN — First launch
   1. Drag StorageLens onto the Applications shortcut.
   2. In Applications, right-click StorageLens and choose Open, then Open
      again. macOS asks once because this build is signed ad-hoc rather than
      notarized; a normal double-click works from then on.
   3. Optional, to measure protected folders (Mail, some app containers):
      System Settings > Privacy & Security > Full Disk Access > add StorageLens.

PT-BR — Primeira abertura
   1. Arraste o StorageLens para o atalho Applications.
   2. Em Aplicativos, clique com o botão direito no StorageLens, escolha Abrir
      e confirme em Abrir. O macOS pergunta uma única vez porque esta versão é
      assinada localmente, sem notarização.
   3. Opcional, para medir pastas protegidas (Mail, contêineres de apps):
      Ajustes do Sistema > Privacidade e Segurança > Acesso Total ao Disco.

ES — Primera apertura
   1. Arrastra StorageLens al acceso directo Applications.
   2. En Aplicaciones, haz clic derecho en StorageLens, elige Abrir y confirma.
      macOS lo pregunta una sola vez porque esta versión está firmada de forma
      ad-hoc, sin notarización.
   3. Opcional, para medir carpetas protegidas (Mail, contenedores de apps):
      Ajustes del Sistema > Privacidad y seguridad > Acceso Total al Disco.

https://github.com/glaydston/storagelens
TXT

echo "==> Building $DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGING"
echo "==> Built $DMG ($(du -h "$DMG" | cut -f1))"
