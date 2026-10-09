#!/usr/bin/env bash
# Downloads the free, open-source tools used to TEST and BUILD the Roblox kit
# into .tools/ at the repo root (git-ignored). Nothing is installed system-wide,
# nothing costs money, no account is needed.
#   luau      - official Luau runtime/analyzer  (github.com/luau-lang/luau)
#   rojo      - builds .rbxlx place files         (github.com/rojo-rbx/rojo)
#   luau-lsp  - type checks against Roblox APIs   (github.com/JohnnyMorganz/luau-lsp)
# Linux x86_64 only. On macOS/Windows download the matching assets by hand.
set -euo pipefail
LUAU_VERSION="0.700"
ROJO_VERSION="7.4.4"
LUAU_LSP_VERSION="1.70.1"

DIR="$(cd "$(dirname "$0")/.." && pwd)/.tools"
mkdir -p "$DIR"
cd "$DIR"
fetch() { curl -fsSL --max-time 120 -o "$1" "$2"; }

if [ ! -x luau/luau ]; then
  fetch luau.zip "https://github.com/luau-lang/luau/releases/download/${LUAU_VERSION}/luau-ubuntu.zip"
  unzip -o -q luau.zip -d luau && rm luau.zip
fi
if [ ! -x rojo/rojo ]; then
  fetch rojo.zip "https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/rojo-${ROJO_VERSION}-linux-x86_64.zip"
  unzip -o -q rojo.zip -d rojo && rm rojo.zip
fi
if [ ! -x lsp/luau-lsp ]; then
  fetch lsp.zip "https://github.com/JohnnyMorganz/luau-lsp/releases/download/${LUAU_LSP_VERSION}/luau-lsp-linux-x86_64.zip"
  unzip -o -q lsp.zip -d lsp && rm lsp.zip
fi
if [ ! -f globalTypes.d.luau ]; then
  fetch globalTypes.d.luau "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LUAU_LSP_VERSION}/scripts/globalTypes.d.luau"
fi
echo "Tools ready in $DIR"
ls "$DIR"
