#!/bin/zsh
# Builds a Release copy and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project Clipboard.xcodeproj -scheme Clipboard -configuration Release \
  -derivedDataPath build -quiet build

pkill -x Clipboard || true
rm -rf /Applications/Clipboard.app
ditto build/Build/Products/Release/Clipboard.app /Applications/Clipboard.app
open /Applications/Clipboard.app
echo "Installed. Press ⌥⌘V to open the history."
