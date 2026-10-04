#!/bin/sh
# Agent Office'i bildirimlerin çalışabileceği bir .app paketine koyar: build/AgentOffice.app
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/AgentOffice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/AgentOffice" "$BIN/agent-office-hook" "$APP/Contents/MacOS/"
codesign --force --sign - "$APP" >/dev/null
echo "$APP"
