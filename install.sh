#!/bin/zsh
# Builds a Release copy and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project Magpie.xcodeproj -scheme Magpie -configuration Release \
  -derivedDataPath build -quiet build

pkill -x Magpie || true
rm -rf /Applications/Magpie.app
ditto build/Build/Products/Release/Magpie.app /Applications/Magpie.app
open /Applications/Magpie.app
echo "Installed. Press ⌥⌘V to open the history."
