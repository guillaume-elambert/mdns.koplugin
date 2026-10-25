# mdns.koplugin — mDNS Responder for KOReader

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

### 1. From Git (with submodules)

Clone the repository recursively:

```bash
git clone --recurse-submodules https://github.com/<you>/mdns.koplugin.git
cd mdns.koplugin
make setup
```

### 2. Copying to your device

Copy the plugin directory to your device's KOReader `plugins/` directory:

| Device  | Plugin path                                           |
|---------|-------------------------------------------------------|
| Kobo    | `/mnt/onboard/.adds/koreader/plugins/mdns.koplugin/`  |
| Kindle  | `/mnt/us/koreader/plugins/mdns.koplugin/`              |
| Android | Wherever KOReader is installed → `plugins/mdns.koplugin/` |

> [!TIP]
> Some e-reader partitions (such as FAT32/vfat over USB mass storage) do not
> support symlinks. When copying from your computer, use **`-L`** to dereference
> the `lib/mdns.lua` symlink into a regular file:
> ```bash
> # Over SSH with rsync (recommended):
> rsync -avL --exclude='.git*' . root@<reader-ip>:/mnt/onboard/.adds/koreader/plugins/mdns.koplugin/
>
> # Or using cp:
> cp -rL . /Volumes/KOBOeReader/.adds/koreader/plugins/mdns.koplugin/
> ```

### 3. Restart KOReader

After copying, restart KOReader.

## Usage

1. Open KOReader → **☰ Menu** → **Network** → **mDNS Responder**.
2. Tap **Hostname** to set a custom name (e.g. `my-kobo`).
3. The responder starts automatically when Wi-Fi connects.  
   You can also tap **Start now** / **Stop** manually.
4. From any computer on the same network:
   ```bash
   ping my-kobo.local
   ```

## Directory Structure

```
mdns.koplugin/
├── _meta.lua                                # Plugin name, description
├── main.lua                                 # Plugin entry point: lifecycle, menu, events
├── .gitmodules                              # Submodule definition
├── .submodules/
│   └── filesync-koplugin/                   # Sparse submodule (only filesync/mdns.lua on disk)
│       └── filesync/
│           └── mdns.lua
├── lib/
│   └── mdns.lua -> ../.submodules/filesync-koplugin/filesync/mdns.lua
├── sync-mdns.sh                             # Helper script: sparse-checkout & submodule update
├── Makefile                                 # `make setup` and `make sync-mdns`
├── .github/
│   └── workflows/
│       └── sync-mdns.yml                    # Automated weekly CI updates
├── .gitignore
└── README.md
```

## Dependency Management: Submodule + Sparse-Checkout + Symlink

This plugin uses a clean single-file dependency mechanism to track `filesync/mdns.lua`
from [filesync.koplugin](https://github.com/abrahamnm/filesync.koplugin) without
bloating the repository with the rest of `filesync`:

### How it was set up

```bash
# 1. Add the submodule into a hidden auxiliary path
git submodule add https://github.com/abrahamnm/filesync.koplugin.git .submodules/filesync-koplugin

# 2. Configure sparse-checkout to checkout only filesync/mdns.lua
cd .submodules/filesync-koplugin
git sparse-checkout init --no-cone
git sparse-checkout set /filesync/mdns.lua
cd ../..

# 3. Create relative symlink into lib/
mkdir -p lib
ln -s ../.submodules/filesync-koplugin/filesync/mdns.lua lib/mdns.lua
```

### Keeping the mDNS module updated

To update to the latest upstream version at any time:

```bash
# Update to latest upstream master:
make sync-mdns

# Or pin to a specific release tag/commit:
make sync-mdns MDNS_REF=v1.11.1
```

This runs `sync-mdns.sh`, which fetches the ref, re-applies sparse checkout, updates the HEAD in `.submodules/filesync-koplugin`, and ensures the symlink is intact.

Commit the updated submodule reference:
```bash
git add .submodules/filesync-koplugin
git commit -m "chore: update filesync submodule (mdns.lua)"
```

## How It Works

1. **Plugin loads** (`init`) → opens `LuaSettings` from
   `<koreader-settings>/mdns.lua`, registers menu items, and checks
   if Wi-Fi is already connected.
2. **`onNetworkConnected`** → detects the device IP (via NetworkMgr,
   `ifconfig`, or UDP socket trick), reads the saved hostname, creates
   an `Mdns` instance via `dofile(_plugin_dir .. "/lib/mdns.lua")`, and calls `start()`.
3. **`onNetworkDisconnected`** → calls `stop()` (sends mDNS goodbye
   packet) and cleans up.
4. **Hostname change** → persists via `LuaSettings`, then restarts the
   responder if it was running.

## Dependencies

The `mdns.lua` module requires only:
- `socket` (LuaSocket) — **ships with KOReader** ✓
- `ui/uimanager` (UIManager) — **KOReader core** ✓
- `logger` — **KOReader core** ✓

No extra external native libraries or Lua rocks are required.
