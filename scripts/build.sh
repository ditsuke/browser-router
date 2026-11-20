#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product BrowserRouter
app="$PWD/dist/Browser Router.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/BrowserRouter "$app/Contents/MacOS/BrowserRouter"
cp scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
