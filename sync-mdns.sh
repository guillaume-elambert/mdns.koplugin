#!/usr/bin/env bash
# sync-mdns.sh — Update upstream submodule with sparse-checkout and setup symlink.
# Reads defaults from .env if present.
#
# Usage:
#   ./sync-mdns.sh              # update submodule to default branch from .env
#   ./sync-mdns.sh <git-ref>    # checkout a specific commit, tag, or branch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load .env if present
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# Fallback defaults if not set in .env
SUBMODULE_DIR="${SUBMODULE_DIR:-.submodules/filesync-koplugin}"
PLUGIN_DIR="${PLUGIN_DIR:-mdns.koplugin}"
LIB_DIR="${LIB_DIR:-${PLUGIN_DIR}/lib}"
UPSTREAM_FILE="${UPSTREAM_FILE:-filesync/mdns.lua}"
DEFAULT_REF="${DEFAULT_REF:-master}"
REF="${1:-$DEFAULT_REF}"

# 1. Initialize submodule if needed
if [ ! -d "${SCRIPT_DIR}/${SUBMODULE_DIR}/.git" ] && [ ! -f "${SCRIPT_DIR}/${SUBMODULE_DIR}/.git" ]; then
    echo "Initializing submodule in ${SUBMODULE_DIR}..."
    git submodule update --init --recursive "${SUBMODULE_DIR}"
fi

# 2. Configure sparse-checkout inside submodule
echo "Configuring sparse-checkout in ${SUBMODULE_DIR} for /${UPSTREAM_FILE}..."
(
    cd "${SCRIPT_DIR}/${SUBMODULE_DIR}"
    git sparse-checkout init --no-cone
    git sparse-checkout set "/${UPSTREAM_FILE#/}"
)

# 3. Fetch and update ref
echo "Fetching ref '${REF}'..."
(
    cd "${SCRIPT_DIR}/${SUBMODULE_DIR}"
    git fetch origin "${REF}"
    git checkout FETCH_HEAD
)

# 4. Create relative symlink in LIB_DIR pointing to SUBMODULE_DIR/UPSTREAM_FILE
TARGET_LIB_FILE="${SCRIPT_DIR}/${LIB_DIR}/$(basename "${UPSTREAM_FILE}")"
mkdir -p "${SCRIPT_DIR}/${LIB_DIR}"

slashes="${LIB_DIR//[^\/]/}"   # count '/' chars in LIB_DIR
up="../"
for ((i=0; i<${#slashes}; i++)); do up+="../"; done

REL_TARGET="${up}${SUBMODULE_DIR}/${UPSTREAM_FILE}"
ln -sf "${REL_TARGET}" "${TARGET_LIB_FILE}"

SUBMODULE_HEAD=$(git -C "${SCRIPT_DIR}/${SUBMODULE_DIR}" rev-parse --short HEAD)
echo "✓ Updated ${SUBMODULE_DIR} to ${SUBMODULE_HEAD}"
echo "✓ Symlink created: ${LIB_DIR}/$(basename "${UPSTREAM_FILE}") -> ${REL_TARGET}"
