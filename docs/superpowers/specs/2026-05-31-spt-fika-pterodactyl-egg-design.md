# SPT + Fika Pterodactyl Egg — Design Spec

**Date:** 2026-05-31
**Status:** Approved

## Overview

A Pterodactyl egg that runs a Single Player Tarkov (SPT) + Fika multiplayer server with full feature parity to the upstream Docker image at `ghcr.io/zhliau/fika-spt-server-docker`. The egg is a single JSON export file (`egg-spt-fika.json`) importable into any Pterodactyl panel.

**Reference:** https://github.com/zhliau/fika-spt-server-docker

---

## Architecture

### Files Produced
- `egg-spt-fika.json` — the Pterodactyl egg export

### Runtime Docker Image
`ghcr.io/zhliau/fika-spt-server-docker:latest`

Used as a toolbox only. Its entrypoint is fully overridden. It provides:
- .NET 9 ASP.NET runtime (required by SPT.Server.Linux)
- 7zip, curl, aria2, unzip, jq, exiftool, cron

### Installer Container
`debian:bookworm-slim`

Runs once before first start. Downloads and configures SPT + Fika into `/mnt/server` (Pterodactyl maps this to `/home/container`).

### Startup Command
```
bash /home/container/startup.sh
```

`startup.sh` is written by the install script and persists in the server directory. It is a clean rewrite of the upstream `entrypoint.sh` adapted for Pterodactyl paths.

### Path Mapping vs Upstream

| Upstream Docker image | This egg |
|---|---|
| `/opt/server` | `/home/container` |
| `/opt/server/SPT` | `/home/container/SPT` |
| `/opt/build` (SPT baked into image) | downloaded fresh by install script |
| `su - $uid -c "./SPT.Server.Linux"` | `./SPT.Server.Linux` directly |

### Dropped from Upstream
Pterodactyl handles these natively:
- `UID`/`GID` env vars and in-container user creation
- `chown`/`chmod` of server files (`TAKE_OWNERSHIP`, `CHANGE_PERMISSIONS` are kept as no-ops or optional)
- Volume mount validation check (`mount | grep /opt/server`)
- `su -` wrapper around the server binary

---

## Environment Variables

All 13 variables exposed as Pterodactyl egg variables (user-viewable and user-editable).

| Variable | Default | Description |
|---|---|---|
| `SPT_VERSION` | `4.0.13-40087-2891fd4` | SPT release string (`VERSION-EFT_BUILD-GIT_SHA`) |
| `FIKA_VERSION` | `2.2.6` | Fika server mod version |
| `FIKA_MODE` | `disabled` | `disabled` / `install` / `auto-update` / `custom` |
| `AUTO_UPDATE_SPT` | `false` | Auto-update SPT on version mismatch at startup |
| `FORCE_SPT_VERSION` | *(empty)* | Force a specific SPT version string; disables auto-update |
| `LISTEN_ALL_NETWORKS` | `true` | Patch SPT `ip`/`backendIp` to `0.0.0.0` (default `true` for Pterodactyl) |
| `ENABLE_PROFILE_BACKUP` | `true` | Enable daily profile backup cron job |
| `TAKE_OWNERSHIP` | `true` | Let container set file ownership |
| `CHANGE_PERMISSIONS` | `true` | Let container set file permissions |
| `NUM_HEADLESS_PROFILES` | *(empty)* | Number of Fika headless profiles to auto-generate |
| `INSTALL_OTHER_MODS` | `false` | Enable automated mod downloader |
| `MOD_URLS_TO_DOWNLOAD` | *(empty)* | Space-separated mod download URLs |
| `TZ` | *(empty)* | TZ identifier e.g. `America/New_York` |

**Intentional deviation from upstream:** `LISTEN_ALL_NETWORKS` defaults to `true` (upstream: `false`) because on Pterodactyl the server always runs inside a container and must listen on all interfaces to be reachable.

---

## Install Script

**Container:** `debian:bookworm-slim`
**Entrypoint:** `bash`

### Steps

1. `apt-get install -y curl jq p7zip-full unzip libimage-exiftool-perl`
2. If `/mnt/server/SPT/SPT.Server.Linux` already exists → skip download (supports re-install over existing data and migration from an existing SPT install)
3. Otherwise: download `https://spt-releases.modd.in/SPT-${SPT_VERSION}.7z`, extract to `/mnt/server/SPT/`
4. If `FIKA_MODE` is `install` or `auto-update` and `/mnt/server/SPT/user/mods/fika-server` does not exist: download `https://github.com/project-fika/Fika-Server-CSharp/releases/download/v${FIKA_VERSION}/Fika.Server.Release.${FIKA_VERSION}.zip` and extract into `/mnt/server/SPT/user/mods/fika-server/`
5. If `LISTEN_ALL_NETWORKS=true` and `http.json` already exists: patch `ip` and `backendIp` to `0.0.0.0`
6. Write `startup.sh` to `/mnt/server/startup.sh` via heredoc
7. `chmod +x /mnt/server/startup.sh`

### What the Install Script Does NOT Handle
Auto-update, Fika version validation, mod installer, profile backup — these are startup-time concerns in `startup.sh`.

---

## startup.sh

A direct adaptation of the upstream `entrypoint.sh`. Written to `/home/container/startup.sh` by the install script. Runs on every server start.

### Execution Order

1. **`enforce_spt_4_structure`** — if SPT 4.x files are loose in `/home/container` (migration from older layout), moves them into the `SPT/` subdirectory
2. **`validate`** — checks SPT version via `exiftool` on `SPT.Server.dll`; if mismatch, aborts or calls `try_update_spt` based on `AUTO_UPDATE_SPT`; validates Fika version based on `FIKA_MODE` (checks remote SHA via GitHub API)
3. **First-boot check** — if `SPT.Server.Linux` not present, calls `install_spt` (downloads + extracts SPT archive from `spt-releases.modd.in`)
4. **`spt_listen_on_all_networks`** — patches `SPT_Data/configs/http.json` and Fika config if `LISTEN_ALL_NETWORKS=true`
5. **Fika install/update** — installs or updates Fika server mod based on `FIKA_MODE`
6. **`set_num_headless_profiles`** — patches `fika.jsonc` if `NUM_HEADLESS_PROFILES` is set
7. **`install_requested_mods`** — runs mod downloader if `INSTALL_OTHER_MODS=true`
8. **`start_crond`** — if `ENABLE_PROFILE_BACKUP=true`: writes a custom `/home/container/backup.sh` (the image's `/usr/bin/backup` is hardcoded to `/opt/server` and would fail), registers it in cron via a dynamically written cron file, then starts the cron daemon
9. **`set_timezone`** — configures TZ from env var or `/etc/timezone`
10. **Run:** `cd /home/container/SPT && ./SPT.Server.Linux`

### Functions Retained from Upstream (with path changes)
- `enforce_spt_4_structure`
- `validate` (SPT + Fika version checks)
- `install_spt` / `try_update_spt` / `backup_spt_user_dirs`
- `install_fika_mod` / `try_update_fika` / `backup_fika`
- `spt_listen_on_all_networks`
- `set_num_headless_profiles`
- `install_requested_mods`
- `start_crond`
- `set_timezone`

### Functions Removed vs Upstream
- `create_running_user` — Pterodactyl manages container user
- `change_owner` / `set_permissions` — Pterodactyl manages permissions
- Volume mount check — not applicable; `/home/container` is always present

---

## Egg Config

### Stop Signal
`^C` (SIGINT — standard for SPT server)

### Server Ready Detection
Log line match: `"started"` (best guess at SPT Server's startup confirmation output — verify against actual server logs and adjust if needed)

### Config Files Parsed
None — all configuration is done via environment variables and the startup script's JSON patching.

---

## Constraints and Known Limitations

- The startup.sh is written once by the install script and stored in the server directory. If the egg's startup logic is updated in a future version, users must re-run the install script (or manually replace `startup.sh`) to get the updated logic.
- ARM64 is not supported by SPT 4.0+ (upstream limitation).
- The `FORCE_SPT_VERSION` feature disables SPT auto-update, matching upstream behavior.
- `TAKE_OWNERSHIP` and `CHANGE_PERMISSIONS` are kept as variables for user familiarity but have no effect in the Pterodactyl context (Pterodactyl controls ownership).
- `ENABLE_PROFILE_BACKUP` — the image's `/usr/bin/backup` is hardcoded to `/opt/server` and cannot be used directly. `startup.sh` writes its own `/home/container/backup.sh` and a custom cron entry. Note: upstream considers this feature deprecated since SPT Server now has built-in profile backups; the cron backup is a secondary safeguard.
- Server ready detection string (`"started"`) is an assumption — verify against actual SPT Server log output and update the egg's startup config if needed.
