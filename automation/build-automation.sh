#!/usr/bin/env bash
# Build bundle otomatisasi VL Suite (auto farm):
# ambil automation/auto-farm.lua,
# lalu obfuscate dengan Prometheus (config light) menjadi
# dist/vl-automation.lua -- file yang dimuat VL Suite dari
# GitHub Pages saat runtime.
#
# Yang dibutuhkan di PATH / env:
#   LUA51       biner Lua 5.1 (default: lua5.1)
#   PROMETHEUS  folder Prometheus (default: ~/workspace/tools/prometheus)
#   OBF_CONFIG  config Prometheus (default: automation/obfuscate-config.lua)
#
# Di GitHub Actions langkah ini boleh dilewati bila secret /
# repo privat belum diatur: suite tetap jalan, panel farm
# saja yang tidak terbuka (loader suite menanganinya).
set -euo pipefail
cd "$(dirname "$0")/.."

LUA51="${LUA51:-lua5.1}"
PROMETHEUS="${PROMETHEUS:-$HOME/workspace/tools/prometheus}"
OBF_CONFIG="${OBF_CONFIG:-automation/obfuscate-config.lua}"

TMP_PLAIN="$(mktemp)"
trap 'rm -f "$TMP_PLAIN"' EXIT

cat automation/auto-farm.lua > "$TMP_PLAIN"

mkdir -p dist
"$LUA51" "$PROMETHEUS/cli.lua" --config "$OBF_CONFIG" --out dist/vl-automation.lua "$TMP_PLAIN"

echo "built dist/vl-automation.lua ($(wc -c < dist/vl-automation.lua) bytes, obfuscated)"
