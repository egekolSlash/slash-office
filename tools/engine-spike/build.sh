#!/bin/sh
# Motor denemesini derler: .build/EngineSpike (+ LayaAir modu için .build/laya).
set -eu
cd "$(dirname "$0")"
mkdir -p .build/laya/engine
swiftc -O main.swift -o .build/EngineSpike
cp laya/index.html .build/laya/
ENGINE=${LAYA_ENGINE:-$HOME/git/slash-playable/skills/playable-forge/engine}
if [ -d "$ENGINE" ]; then cp "$ENGINE"/*.js .build/laya/engine/; else echo "LayaAir motoru bulunamadı ($ENGINE); sadece metal modu çalışır."; fi
echo "$(pwd)/.build/EngineSpike"
