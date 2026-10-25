#!/bin/bash
# sync-mdns.sh — Update the filesync submodule with sparse-checkout and copy mdns.lua
#
# Usage:
#   ./sync-mdns.sh              # update submodule to latest upstream master
#   ./sync-mdns.sh <git-ref>    # checkout a specific commit, tag, or branch

set -euo pipefail

SUBMODULE_DIR=".submodules/filesync-koplugin"
SOURCES_DIR="mdns.koplugin"
LIB_DIR="${SOURCES_DIR}/lib"
REF="${1:-master}"

# 1. Initialize submodule if needed
if [ ! -d "$SUBMODULE_DIR/.git" ] && [ ! -f "$SUBMODULE_DIR/.git" ]; then
    echo "Initializing submodule..."
    git submodule update --init --recursive "$SUBMODULE_DIR"
fi

# 2. Configure sparse-checkout inside submodule
echo "Configuring sparse-checkout in $SUBMODULE_DIR..."
cd "$SUBMODULE_DIR"
git sparse-checkout init --no-cone
git sparse-checkout set /filesync/mdns.lua

# 3. Fetch and update ref
echo "Fetching ref '$REF'..."
git fetch origin "$REF"
git checkout FETCH_HEAD
cd - >/dev/null

# 4. Copy the file into lib/ (do NOT use a symlink: e-readers use FAT32
#    which cannot handle POSIX symlinks and causes XSym corruption)
mkdir -p "$LIB_DIR"
slashes="${LIB_DIR//[^\/]/}"   # keep only '/' chars
up="../"
for ((i=0; i<${#slashes}; i++)); do up+="../"; done
echo "${up}${SUBMODULE_DIR}/filesync/mdns.lua"
ln -sf "${up}${SUBMODULE_DIR}/filesync/mdns.lua" "${LIB_DIR}/mdns.lua"

echo "✓ Updated $SUBMODULE_DIR to $(git -C "$SUBMODULE_DIR" rev-parse --short HEAD)"
echo "✓ Copied real file to $LIB_DIR/mdns.lua"
