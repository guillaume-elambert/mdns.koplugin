# mdns.koplugin — mDNS for KOReader

Announces your e-reader on the local network via **multicast DNS**
(Bonjour / Avahi) so you can reach it at `<hostname>.local` from any
device on the same Wi-Fi network.

Works on **Kobo, Kindle, and Android**.

## Features

- **Automatic lifecycle** — starts when Wi-Fi connects, stops when it
  disconnects; also starts if Wi-Fi is already up when the plugin loads.
- **Custom hostname** — set via a text input in the KOReader menu;
  persisted across reboots.
- **Zero extra dependencies** — uses only libraries KOReader already
  ships (LuaSocket, UIManager, logger).
- **Kindle firewall handling** — automatically opens/closes UDP port
  5353 via `iptables` on Kindle devices.

## Installation

### 1. From a Release ZIP (Recommended)

1. Download the latest `mdns.koplugin-vX.Y.Z.zip` from [Releases](../../releases).
2. Extract the archive. It contains an `mdns.koplugin/` folder.
3. Copy the `mdns.koplugin/` folder to your device's KOReader `plugins/` directory:

| Device  | Plugin path                                           |
|---------|-------------------------------------------------------|
| Kobo    | `/mnt/onboard/.adds/koreader/plugins/mdns.koplugin/`  |
| Kindle  | `/mnt/us/koreader/plugins/mdns.koplugin/`              |
| Android | Wherever KOReader is installed → `plugins/mdns.koplugin/` |

4. Restart KOReader.

### 2. From Git (Development)

Clone recursively:

```bash
git clone --recurse-submodules https://github.com/<you>/mdns.koplugin.git
cd mdns.koplugin
make setup
```

To build a standalone zip archive with all symlinks resolved into real files:

```bash
make package
# Creates dist/mdns.koplugin-v1.0.0.zip and dist/mdns.koplugin.zip
```

Copy the plugin to your e-reader:
```bash
# Over SSH (example for Kobo):
rsync -avL --exclude='.git*' mdns.koplugin/ root@<reader-ip>:/mnt/onboard/.adds/koreader/plugins/mdns.koplugin/

# Or via USB:
cp -rL mdns.koplugin /Volumes/KOBOeReader/.adds/koreader/plugins/
```

## Usage

1. Open KOReader → **☰ Menu** → **Network** → **mDNS**.
2. Tap **Hostname** to set a custom name (e.g. `my-kobo`).
3. The responder starts automatically when Wi-Fi connects.  
   You can also tap **Start now** / **Stop** manually.
4. From any computer on the same network:
   ```bash
   ping my-kobo.local
   ```

## Directory Structure

```
repository root/
├── mdns.koplugin/                           # The KOReader plugin directory
│   ├── _meta.lua                            # Plugin name, description, version
│   ├── main.lua                             # Plugin entry point: lifecycle, menu, events
│   └── lib/
│       └── mdns.lua -> ../../.submodules/filesync-koplugin/filesync/mdns.lua
├── .env                                     # Central configuration for paths & workflows
├── .gitmodules                              # Git submodule config
├── .submodules/
│   └── filesync-koplugin/                   # Sparse submodule (only filesync/mdns.lua)
├── sync-mdns.sh                             # Helper: sparse-checkout & update submodule
├── package.sh                               # Packaging & tagging script
├── Makefile                                 # Convenience targets
├── .github/
│   └── workflows/
│       ├── release.yml                      # Automated tag & release workflow
│       └── sync-mdns.yml                    # Automated weekly dependency updates
├── .gitignore
└── README.md
```

## Packaging & Releases (`package.sh`)

[`package.sh`](file:///Users/guillaume/Downloads/mdns.koplugin/package.sh) automates version extraction from `_meta.lua`, symlink dereferencing, and zip creation:

```bash
# Build release zip (reads version from _meta.lua):
make package
# Or: ./package.sh

# Build a dev/test archive (appends git commit hash):
make dev
# Or: ./package.sh --dev

# Tag git repository with version from _meta.lua (e.g. v1.0.0):
make tag
# Or: ./package.sh --tag

# Tag, push tag, and publish release via GitHub CLI ('gh'):
make release
# Or: ./package.sh --release
```

### Symlink Dereferencing

In the git repository, `mdns.koplugin/lib/mdns.lua` is a relative symlink to the sparse submodule.
When creating zip archives, `package.sh` uses `cp -rL` to **dereference all symlinks** into real files.
This guarantees that the resulting zip can be extracted on any e-reader FAT32 filesystem without triggering `XSym` syntax errors.

## GitHub Actions Release Workflow

The workflow [`.github/workflows/release.yml`](file:///Users/guillaume/Downloads/mdns.koplugin/.github/workflows/release.yml):
1. Runs whenever changes to `mdns.koplugin/**` are pushed to `master`/`main` (or via manual trigger).
2. Extracts the `version` field from `_meta.lua`.
3. Checks if a git tag `v<version>` already exists:
   - If **new**: creates and pushes git tag `v<version>`, builds the zip archive, and creates a GitHub Release with the archive attached.
   - If **already existing**: skips to avoid duplicate releases.
4. Can also be triggered manually from GitHub Actions UI (`workflow_dispatch`) with optional `force_release` or `prerelease` flags.

## Updating the mDNS Upstream Dependency

To update `filesync/mdns.lua` to the latest upstream commit:

```bash
# Update to latest upstream master:
make sync-mdns

# Or pin to a specific release tag/commit:
make sync-mdns MDNS_REF=v1.11.1
```

Commit the updated submodule:
```bash
git add .submodules/filesync-koplugin mdns.koplugin/lib/mdns.lua
git commit -m "chore: update filesync submodule (mdns.lua)"
```

A scheduled GitHub Action (`sync-mdns.yml`) also checks for updates weekly and opens a PR automatically.
