#!/usr/bin/env bash
# package.sh — Package KOReader plugin, dereference symlinks, create tag & release archive.
# Reads configuration defaults from .env if present.
#
# Usage:
#   ./package.sh                # Build dist/<name>-v<version>.zip & dist/<name>.zip
#   ./package.sh --dev          # Build a dev/test archive: dist/<name>-dev.zip
#   ./package.sh --tag          # Create git tag (v<version>) locally if not already tagged
#   ./package.sh --push-tag     # Create git tag and push to remote origin
#   ./package.sh --release      # Build zip, tag, and publish release via 'gh' CLI if available
#   ./package.sh --get-version  # Output extracted version string (e.g. 1.0.0)
#   ./package.sh --get-tag      # Output tag name (e.g. v1.0.0)
#   ./package.sh --get-zip      # Output path to the generated zip

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

PLUGIN_NAME="${PLUGIN_NAME:-mdns.koplugin}"
PLUGIN_DIR="${PLUGIN_DIR:-mdns.koplugin}"
LIB_DIR="${LIB_DIR:-${PLUGIN_DIR}/lib}"
UPSTREAM_FILE="${UPSTREAM_FILE:-filesync/mdns.lua}"

PLUGIN_SRC="${SCRIPT_DIR}/${PLUGIN_DIR}"
META_FILE="${PLUGIN_SRC}/_meta.lua"
DIST_DIR="${SCRIPT_DIR}/dist"
UPSTREAM_BASENAME="$(basename "${UPSTREAM_FILE}")"
TARGET_LIB_FILE="${SCRIPT_DIR}/${LIB_DIR}/${UPSTREAM_BASENAME}"

# Validate source directory and _meta.lua
if [ ! -d "$PLUGIN_SRC" ]; then
    echo "Error: Plugin source directory '$PLUGIN_SRC' not found." >&2
    exit 1
fi

if [ ! -f "$META_FILE" ]; then
    echo "Error: _meta.lua not found at '$META_FILE'." >&2
    exit 1
fi

# Extract version from _meta.lua (supports version = "1.0.0" or version = '1.0.0')
RAW_VERSION=$(grep -E 'version[[:space:]]*=[[:space:]]*["'\'']' "$META_FILE" | head -n 1 | sed -E 's/.*version[[:space:]]*=[[:space:]]*["'\'']([^"'\'']+)["'\''].*/\1/' || true)

if [ -z "$RAW_VERSION" ]; then
    echo "Warning: No version field found in $META_FILE, defaulting to 0.0.0" >&2
    RAW_VERSION="0.0.0"
fi

TAG_NAME="v${RAW_VERSION}"

# Quick output modes
if [ "${1:-}" = "--get-version" ]; then
    echo "$RAW_VERSION"
    exit 0
fi

if [ "${1:-}" = "--get-tag" ]; then
    echo "$TAG_NAME"
    exit 0
fi

# Mode flags
DO_DEV=false
DO_TAG=false
DO_PUSH_TAG=false
DO_RELEASE=false

for arg in "$@"; do
    case "$arg" in
        --dev)
            DO_DEV=true
            ;;
        --tag)
            DO_TAG=true
            ;;
        --push-tag)
            DO_TAG=true
            DO_PUSH_TAG=true
            ;;
        --release)
            DO_TAG=true
            DO_PUSH_TAG=true
            DO_RELEASE=true
            ;;
        --help|-h)
            sed -ne '2,13p' "$0" | sed 's/^#//'
            exit 0
            ;;
    esac
done

if [ "$DO_DEV" = true ]; then
    GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
    ZIP_BASENAME="${PLUGIN_NAME}-dev"
    DISPLAY_VERSION="${RAW_VERSION}-dev+${GIT_SHA}"
else
    ZIP_BASENAME="${PLUGIN_NAME}-${TAG_NAME}"
    DISPLAY_VERSION="${RAW_VERSION}"
fi

PRIMARY_ZIP="${DIST_DIR}/${ZIP_BASENAME}.zip"
GENERIC_ZIP="${DIST_DIR}/${PLUGIN_NAME}.zip"

if [ "${1:-}" = "--get-zip" ]; then
    echo "$PRIMARY_ZIP"
    exit 0
fi

echo "================================================="
echo " Packaging: ${PLUGIN_NAME}"
echo " Version:   ${DISPLAY_VERSION}"
echo " Tag:       ${TAG_NAME}"
echo "================================================="

# Ensure submodule is initialized if target lib file is missing or broken
if [ ! -e "$TARGET_LIB_FILE" ]; then
    echo "${TARGET_LIB_FILE} not found or broken. Running sync-mdns.sh..."
    bash "${SCRIPT_DIR}/sync-mdns.sh"
fi

# Prepare clean staging area
STAGING_DIR="${DIST_DIR}/.staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "Copying plugin files and dereferencing symlinks (-L)..."
# cp -rL dereferences all symlinks, converting them to native standalone files
cp -rL "$PLUGIN_SRC" "$STAGING_DIR/"

# Remove undesirable metadata/cache files
find "$STAGING_DIR" -name ".DS_Store" -delete 2>/dev/null || true
find "$STAGING_DIR" -name "._*" -delete 2>/dev/null || true
find "$STAGING_DIR" -name "*.swp" -delete 2>/dev/null || true

# Relative path of LIB_DIR within PLUGIN_DIR
LIB_REL_DIR="${LIB_DIR#"${PLUGIN_DIR}/"}"
STAGED_TARGET="${STAGING_DIR}/${PLUGIN_DIR}/${LIB_REL_DIR}/${UPSTREAM_BASENAME}"

# Verify that target lib file is a real file, not a symlink
if [ -L "$STAGED_TARGET" ]; then
    echo "Error: Symlink was not dereferenced at $STAGED_TARGET" >&2
    exit 1
fi

if [ ! -f "$STAGED_TARGET" ]; then
    echo "Error: Expected file not found at $STAGED_TARGET" >&2
    exit 1
fi

# Build zip archive
mkdir -p "$DIST_DIR"
rm -f "$PRIMARY_ZIP" "$GENERIC_ZIP"

echo "Creating zip archive: $(basename "$PRIMARY_ZIP")..."
(
    cd "$STAGING_DIR"
    zip -q -r "$PRIMARY_ZIP" "$PLUGIN_DIR"
)

# Also create/update generic <name>.zip for convenience
cp "$PRIMARY_ZIP" "$GENERIC_ZIP"

# Clean up staging directory
rm -rf "$STAGING_DIR"

echo "✓ Archive created successfully:"
echo "  - ${PRIMARY_ZIP} ($(du -h "$PRIMARY_ZIP" | cut -f1))"
echo "  - ${GENERIC_ZIP}"
echo ""
echo "Archive contents:"
unzip -l "$PRIMARY_ZIP"

# Handle git tagging if requested
if [ "$DO_TAG" = true ]; then
    echo ""
    echo "Checking git tag '${TAG_NAME}'..."
    if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        echo "Git tag '${TAG_NAME}' already exists."
    else
        echo "Creating git tag '${TAG_NAME}'..."
        git tag -a "$TAG_NAME" -m "Release ${TAG_NAME}"
        echo "✓ Git tag '${TAG_NAME}' created."
    fi

    if [ "$DO_PUSH_TAG" = true ]; then
        echo "Pushing tag '${TAG_NAME}' to origin..."
        git push origin "$TAG_NAME"
        echo "✓ Pushed tag '${TAG_NAME}' to origin."
    else
        echo "To push this tag to GitHub run:"
        echo "  git push origin ${TAG_NAME}"
    fi
fi

# Handle GitHub release creation if requested
if [ "$DO_RELEASE" = true ]; then
    echo ""
    if command -v gh >/dev/null 2>&1; then
        echo "Creating GitHub Release via gh CLI..."
        gh release create "$TAG_NAME" "$PRIMARY_ZIP" "$GENERIC_ZIP" \
            --title "${TAG_NAME}" \
            --notes "Release ${TAG_NAME} of ${PLUGIN_NAME}." \
            || echo "Release creation skipped or already exists."
    else
        echo "Note: 'gh' CLI not found. To create a release manually:"
        echo "  gh release create ${TAG_NAME} ${PRIMARY_ZIP} ${GENERIC_ZIP} --title ${TAG_NAME}"
    fi
fi

echo ""
echo "Done."
