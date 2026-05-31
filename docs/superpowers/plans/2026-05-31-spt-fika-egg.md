# SPT + Fika Pterodactyl Egg Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `egg-spt-fika.json`, a Pterodactyl egg that runs SPT + Fika with full feature parity to the upstream Docker image.

**Architecture:** Three source files (`egg-template.json`, `scripts/startup.sh`, `scripts/install.sh`) are assembled by `build.py` into the final `egg-spt-fika.json`. The install script (`debian:bookworm-slim`) downloads SPT/Fika and writes `startup.sh` to the server directory. At runtime, `startup.sh` inside `ghcr.io/zhliau/fika-spt-server-docker:latest` handles version validation, auto-updates, Fika management, cron backup, and launches the SPT server from `/home/container/SPT/`.

**Tech Stack:** Bash, Python 3 (build tooling only), Pterodactyl PTDL_v2 egg JSON format, SPT 4.0+ release archives (`spt-releases.modd.in`), Fika server mod (GitHub releases)

---

## File Map

| File | Role |
|---|---|
| `egg-template.json` | Pterodactyl egg JSON with all 13 env vars; empty install script field (filled by build.py) |
| `scripts/startup.sh` | Runtime script written to `/home/container/startup.sh` by install.sh; full startup logic |
| `scripts/install.sh` | Installer script; contains `__STARTUP_SH__` placeholder replaced by build.py |
| `build.py` | Inlines startup.sh into install.sh, fills `scripts.installation.script` in template, writes `egg-spt-fika.json` |
| `egg-spt-fika.json` | Final assembled egg — importable into Pterodactyl panel |

---

### Task 1: Project scaffold

**Files:**
- Create: `scripts/startup.sh`
- Create: `scripts/install.sh`
- Create: `egg-template.json`
- Create: `build.py`
- Create: `.gitignore`

- [ ] **Step 1: Create directory and placeholder scripts**

```bash
mkdir -p scripts
touch scripts/startup.sh scripts/install.sh
chmod +x scripts/startup.sh scripts/install.sh
```

- [ ] **Step 2: Create `.gitignore`**

File: `.gitignore`
```
__pycache__/
*.pyc
```

- [ ] **Step 3: Create `egg-template.json`**

File: `egg-template.json`
```json
{
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {
        "version": "PTDL_v2",
        "update_url": null
    },
    "exported_at": "2026-05-31T00:00:00+00:00",
    "name": "SPT + Fika",
    "author": "theboss@ericisaboss.com",
    "uuid": "a8c48cba-6abc-4d5e-8d2f-1a2b3c4d5e6f",
    "description": "Single Player Tarkov (SPT) server with optional Fika multiplayer mod. Based on https://github.com/zhliau/fika-spt-server-docker.",
    "features": null,
    "docker_images": {
        "ghcr.io/zhliau/fika-spt-server-docker:latest": "latest (SPT 4.x)"
    },
    "file_denylist": [],
    "startup": "bash /home/container/startup.sh",
    "config": {
        "files": "{}",
        "startup": "{\"done\": \"started\"}",
        "logs": "{}",
        "stop": "^C"
    },
    "scripts": {
        "installation": {
            "script": "",
            "container": "debian:bookworm-slim",
            "entrypoint": "bash"
        }
    },
    "variables": [
        {
            "name": "SPT Version",
            "description": "SPT release version string. Format: VERSION-EFT_BUILD-GIT_SHA (e.g. 4.0.13-40087-2891fd4). Find valid versions at https://spt-releases.modd.in/",
            "env_variable": "SPT_VERSION",
            "default_value": "4.0.13-40087-2891fd4",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string|max:40",
            "field_type": "text"
        },
        {
            "name": "Fika Version",
            "description": "Fika server mod version to install or validate (e.g. 2.2.6). Only used when FIKA_MODE is not disabled.",
            "env_variable": "FIKA_VERSION",
            "default_value": "2.2.6",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string|max:20",
            "field_type": "text"
        },
        {
            "name": "Fika Mode",
            "description": "Controls Fika installation and updates. disabled: no Fika. install: install and validate, abort on version mismatch. auto-update: install and auto-update on mismatch. custom: skip all validation for custom Fika builds.",
            "env_variable": "FIKA_MODE",
            "default_value": "disabled",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|string|in:disabled,install,auto-update,custom",
            "field_type": "text"
        },
        {
            "name": "Auto Update SPT",
            "description": "Automatically update SPT server files on startup if the installed version does not match SPT_VERSION.",
            "env_variable": "AUTO_UPDATE_SPT",
            "default_value": "false",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Force SPT Version",
            "description": "Force a specific SPT version. Format: VERSION-EFT_BUILD-GIT_SHA (e.g. 4.0.1-40087-1eacf0f). Disables AUTO_UPDATE_SPT. Leave blank to use SPT_VERSION normally.",
            "env_variable": "FORCE_SPT_VERSION",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:40",
            "field_type": "text"
        },
        {
            "name": "Listen On All Networks",
            "description": "Set SPT server IP bindings to 0.0.0.0 so the server is reachable inside Pterodactyl. Should be true in almost all cases.",
            "env_variable": "LISTEN_ALL_NETWORKS",
            "default_value": "true",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Enable Profile Backup",
            "description": "Enable a daily cron job that backs up player profiles to the backups/profiles/ directory at midnight UTC.",
            "env_variable": "ENABLE_PROFILE_BACKUP",
            "default_value": "true",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Take Ownership",
            "description": "Kept for compatibility with upstream Docker image. Has no functional effect in Pterodactyl.",
            "env_variable": "TAKE_OWNERSHIP",
            "default_value": "true",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Change Permissions",
            "description": "Kept for compatibility with upstream Docker image. Has no functional effect in Pterodactyl.",
            "env_variable": "CHANGE_PERMISSIONS",
            "default_value": "true",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Number of Headless Profiles",
            "description": "Auto-generate this many Fika headless client profiles. Requires fika.jsonc to exist (created automatically on first Fika startup). Leave blank to skip.",
            "env_variable": "NUM_HEADLESS_PROFILES",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|integer|min:0",
            "field_type": "text"
        },
        {
            "name": "Install Other Mods",
            "description": "Enable automatic mod downloader. Downloads and installs mods from MOD_URLS_TO_DOWNLOAD or SPT/mods_download/mod_urls_to_download.txt on each startup.",
            "env_variable": "INSTALL_OTHER_MODS",
            "default_value": "false",
            "user_viewable": true,
            "user_editable": true,
            "rules": "required|boolean",
            "field_type": "text"
        },
        {
            "name": "Mod URLs To Download",
            "description": "Space-separated list of mod download URLs. Requires INSTALL_OTHER_MODS=true. Supports .zip, .7z, .tar.gz, and .dll files.",
            "env_variable": "MOD_URLS_TO_DOWNLOAD",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string",
            "field_type": "text"
        },
        {
            "name": "Timezone",
            "description": "Server timezone. Use TZ database identifiers e.g. America/New_York, Europe/London. Leave blank for UTC. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones",
            "env_variable": "TZ",
            "default_value": "",
            "user_viewable": true,
            "user_editable": true,
            "rules": "nullable|string|max:50",
            "field_type": "text"
        }
    ]
}
```

- [ ] **Step 4: Create `build.py`**

File: `build.py`
```python
#!/usr/bin/env python3
"""Assembles egg-spt-fika.json from egg-template.json + scripts/install.sh + scripts/startup.sh."""

import json
from datetime import datetime, timezone


def build():
    with open('scripts/startup.sh') as f:
        startup_sh = f.read()

    with open('scripts/install.sh') as f:
        install_sh = f.read()

    # Inline startup.sh content into the install script's placeholder
    install_sh = install_sh.replace('__STARTUP_SH__', startup_sh)

    with open('egg-template.json') as f:
        egg = json.load(f)

    egg['scripts']['installation']['script'] = install_sh
    egg['exported_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S+00:00')

    with open('egg-spt-fika.json', 'w') as f:
        json.dump(egg, f, indent=4)

    print('Built egg-spt-fika.json successfully')


if __name__ == '__main__':
    build()
```

- [ ] **Step 5: Verify Python syntax**

```bash
python3 -m py_compile build.py && echo "OK"
```

Expected output: `OK`

- [ ] **Step 6: Commit scaffold**

```bash
git add scripts/startup.sh scripts/install.sh egg-template.json build.py .gitignore
git commit -m "chore: scaffold project structure for SPT+Fika egg"
```

---

### Task 2: Write startup.sh — variables and SPT functions

**Files:**
- Modify: `scripts/startup.sh`

- [ ] **Step 1: Write variable declarations and backwards-compat mapping**

Replace the full contents of `scripts/startup.sh`:

```bash
#!/bin/bash -e

# Paths
MOUNTED_DIR=/home/container
SPT_DIR=$MOUNTED_DIR/SPT
SPT_BINARY=SPT.Server.Linux
SPT_DATA_DIR=$SPT_DIR/SPT_Data

BACKUP_DIR_NAME=${BACKUP_DIR:-backups}
BACKUP_ROOT=$MOUNTED_DIR/$BACKUP_DIR_NAME

# SPT version
SPT_VERSION=${SPT_VERSION:-4.0.13-40087-2891fd4}
SPT_VERSION_SHORT=$(echo $SPT_VERSION | cut -d '-' -f 1)
SPT_BACKUP_DIR=$BACKUP_ROOT/spt/$(date +%Y%m%dT%H%M)
FORCE_SPT_VERSION=${FORCE_SPT_VERSION:=}
FORCED_SPT_VERSION_ARCHIVE=SPT-${FORCE_SPT_VERSION}.7z
AUTO_UPDATE_SPT=${AUTO_UPDATE_SPT:-false}

# Fika
FIKA_VERSION=${FIKA_VERSION:-2.2.6}
FIKA_MODE=${FIKA_MODE:-disabled}
FIKA_BACKUP_DIR=$BACKUP_ROOT/fika/$(date +%Y%m%dT%H%M)
FIKA_CONFIG_PATH=assets/configs/fika.jsonc
FIKA_MOD_DIR=$SPT_DIR/user/mods/fika-server
FIKA_ARTIFACT=Fika.Server.Release.$FIKA_VERSION.zip
FIKA_RELEASE_URL="https://github.com/project-fika/Fika-Server-CSharp/releases/download/v$FIKA_VERSION/$FIKA_ARTIFACT"
FIKA_REMOTE_SHA=$(curl -s "https://api.github.com/repos/project-fika/Fika-Server-CSharp/git/refs/tags/v$FIKA_VERSION" | grep -oP '"sha":\s*"\K[^"]+')

# Other settings
LISTEN_ALL_NETWORKS=${LISTEN_ALL_NETWORKS:-true}
ENABLE_PROFILE_BACKUP=${ENABLE_PROFILE_BACKUP:-true}
INSTALL_OTHER_MODS=${INSTALL_OTHER_MODS:-false}
NUM_HEADLESS_PROFILES=${NUM_HEADLESS_PROFILES:+"$NUM_HEADLESS_PROFILES"}

# Backwards compatibility for deprecated variables
INSTALL_FIKA=${INSTALL_FIKA:-}
AUTO_UPDATE_FIKA=${AUTO_UPDATE_FIKA:-}

if [[ -n "${INSTALL_FIKA}" || -n "${AUTO_UPDATE_FIKA}" ]]; then
    echo "=========================================="
    echo "WARNING: INSTALL_FIKA and AUTO_UPDATE_FIKA are deprecated."
    echo "Please use FIKA_MODE instead."
    echo "=========================================="
    if [[ "${AUTO_UPDATE_FIKA}" == "true" ]]; then
        FIKA_MODE="auto-update"
    elif [[ "${INSTALL_FIKA}" == "true" ]]; then
        FIKA_MODE="install"
    else
        FIKA_MODE="disabled"
    fi
    echo "Mapped to FIKA_MODE=$FIKA_MODE"
    echo "=========================================="
fi
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/startup.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 3: Append SPT functions**

Append to `scripts/startup.sh`:

```bash

# -----------------------------------------------------------------------
# SPT Functions
# -----------------------------------------------------------------------

enforce_spt_4_structure() {
    # If SPT.Server.Linux is loose in MOUNTED_DIR this is a migrated install.
    # Move all loose files into the SPT/ subdirectory.
    if [[ -f $MOUNTED_DIR/$SPT_BINARY ]]; then
        echo "Enforcing SPT 4.0 directory structure"
        mkdir -p $SPT_DIR
        for item in $MOUNTED_DIR/*; do
            base_item=$(basename "$item")
            if [[ "$base_item" != "SPT" ]]; then
                mv "$item" $SPT_DIR
            fi
        done
    fi
}

make_spt_dirs() {
    mkdir -p $SPT_DIR/user/mods
    mkdir -p $SPT_DIR/user/profiles
}

install_spt() {
    if [[ -n ${FORCE_SPT_VERSION} ]]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! Forcing SPT version: $FORCE_SPT_VERSION"
        echo "!! SPT auto-update is disabled while FORCE_SPT_VERSION is set"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        cd ${MOUNTED_DIR}
        if [[ ! -f ${FORCED_SPT_VERSION_ARCHIVE} ]]; then
            echo "Downloading https://spt-releases.modd.in/SPT-${FORCE_SPT_VERSION}.7z"
            curl -sL "https://spt-releases.modd.in/SPT-${FORCE_SPT_VERSION}.7z" \
                -o ${FORCED_SPT_VERSION_ARCHIVE}
            rm -rf $SPT_DATA_DIR
            7zz x ${FORCED_SPT_VERSION_ARCHIVE} -o${MOUNTED_DIR} -aoa
        else
            echo "Version archive already present, presumed installed. Skipping."
            echo "Remove ${FORCED_SPT_VERSION_ARCHIVE} from server files to force reinstall."
        fi
    else
        rm -rf $SPT_DATA_DIR
        cd /tmp
        echo "Downloading SPT $SPT_VERSION"
        curl -sL "https://spt-releases.modd.in/SPT-${SPT_VERSION}.7z" -o spt.7z
        7zz x spt.7z -o${MOUNTED_DIR} -aoa
        rm spt.7z
    fi
    make_spt_dirs
}

backup_spt_user_dirs() {
    mkdir -p $SPT_BACKUP_DIR
    cp -r $SPT_DIR/user $SPT_BACKUP_DIR/
}

try_update_spt() {
    local existing_version=$1
    if [[ "$AUTO_UPDATE_SPT" != "true" ]]; then
        echo "SPT version mismatch: installed=$existing_version expected=$SPT_VERSION_SHORT"
        echo "Set AUTO_UPDATE_SPT=true to enable automatic updates."
        echo "Aborting."
        exit 1
    fi

    echo "Updating SPT from $existing_version to $SPT_VERSION_SHORT"
    backup_spt_user_dirs
    install_spt

    echo "SPT update complete: $existing_version -> $SPT_VERSION_SHORT"
    echo ""
    echo "  ==============="
    echo "  === WARNING ==="
    echo ""
    echo "  user/ was backed up to $SPT_BACKUP_DIR but is otherwise UNTOUCHED."
    echo "  Verify your mods and profiles work with the new SPT version."
    echo "  Restart this server to bring it back up."
    echo ""
    echo "  ==============="
    exit 0
}
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n scripts/startup.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/startup.sh
git commit -m "feat: add startup.sh variable declarations and SPT functions"
```

---

### Task 3: Write startup.sh — Fika functions and validate

**Files:**
- Modify: `scripts/startup.sh`

- [ ] **Step 1: Append Fika functions**

Append to `scripts/startup.sh`:

```bash

# -----------------------------------------------------------------------
# Fika Functions
# -----------------------------------------------------------------------

install_fika_mod() {
    echo "Installing Fika server mod $FIKA_VERSION"
    mkdir -p $SPT_DIR/user/mods
    cd /tmp
    curl -sL $FIKA_RELEASE_URL -O
    unzip -q $FIKA_ARTIFACT -d /tmp/fika_temp/
    mv /tmp/fika_temp/SPT/user/mods/fika-server $FIKA_MOD_DIR
    rm -rf /tmp/fika_temp /tmp/$FIKA_ARTIFACT
    echo "Fika installation complete"
}

backup_fika() {
    mkdir -p $FIKA_BACKUP_DIR
    cp -r $FIKA_MOD_DIR $FIKA_BACKUP_DIR
}

try_update_fika() {
    echo "Updating Fika server mod to $FIKA_VERSION"
    backup_fika
    rm -rf $FIKA_MOD_DIR
    install_fika_mod
    # Restore previous config if it exists
    mkdir -p $FIKA_MOD_DIR/assets/configs
    local existing_config=$FIKA_BACKUP_DIR/fika-server/$FIKA_CONFIG_PATH
    if [[ -f $existing_config ]]; then
        cp $existing_config $FIKA_MOD_DIR/$FIKA_CONFIG_PATH
    fi
    echo "Successfully updated Fika to $FIKA_VERSION"
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/startup.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 3: Append validate function**

Append to `scripts/startup.sh`:

```bash

# -----------------------------------------------------------------------
# Validate
# -----------------------------------------------------------------------

validate() {
    if [[ ${NUM_HEADLESS_PROFILES:+1} && ! $NUM_HEADLESS_PROFILES =~ ^[0-9]+$ ]]; then
        echo "NUM_HEADLESS_PROFILES must be an integer. Got: $NUM_HEADLESS_PROFILES"
        exit 1
    fi

    enforce_spt_4_structure

    echo "Validating SPT version"
    if [[ -d $SPT_DATA_DIR ]]; then
        local existing_version
        existing_version=$(exiftool -s -s -s -ProductVersion $SPT_DIR/SPT.Server.dll \
            | cut -d '-' -f 1)

        if [[ -n ${FORCE_SPT_VERSION} ]]; then
            install_spt
        elif [[ $existing_version != "$SPT_VERSION_SHORT" ]]; then
            try_update_spt "$existing_version"
        else
            echo "SPT version OK: $existing_version"
        fi

        case "$FIKA_MODE" in
            custom)
                echo "Skipping Fika validation (FIKA_MODE=custom)"
                ;;
            install|auto-update)
                local fika_local_sha=""
                if [[ -f $FIKA_MOD_DIR/FikaServer.dll ]]; then
                    fika_local_sha=$(exiftool -s -s -s -ProductVersion \
                        $FIKA_MOD_DIR/FikaServer.dll | grep -oP '[0-9.]+\+\K.*')
                fi
                if [[ "$fika_local_sha" != "$FIKA_REMOTE_SHA" ]]; then
                    echo "Fika SHA mismatch: local=$fika_local_sha expected=$FIKA_REMOTE_SHA"
                    if [[ "$FIKA_MODE" == "auto-update" ]]; then
                        echo "Auto-updating Fika to $FIKA_VERSION"
                        try_update_fika
                    else
                        echo "Fika version mismatch. Set FIKA_MODE=auto-update to auto-update."
                        echo "Aborting."
                        exit 1
                    fi
                else
                    echo "Fika version OK"
                fi
                ;;
            disabled)
                ;;
            *)
                echo "Invalid FIKA_MODE: $FIKA_MODE"
                echo "Valid options: disabled, install, auto-update, custom"
                exit 1
                ;;
        esac
    fi
}
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n scripts/startup.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/startup.sh
git commit -m "feat: add Fika functions and validate to startup.sh"
```

---

### Task 4: Write startup.sh — config functions and main block

**Files:**
- Modify: `scripts/startup.sh`

- [ ] **Step 1: Append config, backup, mods, and timezone functions**

Append to `scripts/startup.sh`:

```bash

# -----------------------------------------------------------------------
# Config + Runtime Functions
# -----------------------------------------------------------------------

spt_listen_on_all_networks() {
    local http_json=$SPT_DATA_DIR/configs/http.json
    if [[ ! -f $http_json ]]; then
        echo "WARNING: $http_json not found, skipping LISTEN_ALL_NETWORKS config"
        return
    fi
    local modified
    modified="$(jq '.ip = "0.0.0.0" | .backendIp = "0.0.0.0"' $http_json)"
    echo -E "${modified}" > $http_json

    if [[ -f "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH" ]]; then
        echo "Applying LISTEN_ALL_NETWORKS to Fika config"
        local modified_fika
        modified_fika="$(jq '.server.SPT.http.ip = "0.0.0.0" | .server.SPT.http.backendIp = "0.0.0.0"' \
            "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH")"
        echo -E "${modified_fika}" > "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH"
    fi
}

set_num_headless_profiles() {
    if [[ ${NUM_HEADLESS_PROFILES:+1} && -f $FIKA_MOD_DIR/$FIKA_CONFIG_PATH ]]; then
        echo "Setting headless profile count to $NUM_HEADLESS_PROFILES"
        local modified
        modified="$(jq --arg n "$NUM_HEADLESS_PROFILES" \
            '.headless.profiles.amount=($n | tonumber)' \
            "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH")"
        echo -E "${modified}" > "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH"
    fi
}

install_requested_mods() {
    echo "Downloading and installing other mods"
    /usr/bin/download_unzip_install_mods $SPT_DIR
}

start_crond() {
    echo "Setting up profile backup cron"
    # Write a custom backup script using /home/container paths.
    # The runtime image's /usr/bin/backup is hardcoded to /opt/server and cannot be used.
    cat > /home/container/backup.sh << 'BACKUP_SCRIPT_EOF'
#!/bin/bash -e
PROFILES_DIR=/home/container/SPT/user/profiles
TIMESTAMP=$(date +%Y%m%dT%H%M)
BACKUP_TARGET=/home/container/backups/profiles/$TIMESTAMP
echo "Backing up profiles to $BACKUP_TARGET" >> /proc/1/fd/1
mkdir -p $BACKUP_TARGET
cp -r $PROFILES_DIR $BACKUP_TARGET
echo "Backup complete." >> /proc/1/fd/1
BACKUP_SCRIPT_EOF
    chmod +x /home/container/backup.sh
    echo "0 0 * * * root /home/container/backup.sh" > /etc/cron.d/spt_backup
    chmod 0644 /etc/cron.d/spt_backup
    /etc/init.d/cron start
}

set_timezone() {
    if [[ -n "${TZ}" ]]; then
        echo $TZ > /etc/timezone
    else
        local before_hour
        before_hour=$(date +"%H")
        TZ=$(cat /etc/timezone)
    fi
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
    if [[ ${before_hour:-} != $(date +"%H") ]]; then
        echo "Timezone set to $TZ"
    fi
}
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/startup.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 3: Append main execution block**

Append to `scripts/startup.sh`:

```bash

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------

validate

if [[ ! -f "$SPT_DIR/$SPT_BINARY" ]]; then
    echo "Server files not found, initializing first boot..."
    install_spt
else
    echo "Found server files at $SPT_DIR, skipping initial install"
fi

if [[ "$LISTEN_ALL_NETWORKS" == "true" ]]; then
    spt_listen_on_all_networks
fi

case "$FIKA_MODE" in
    install|auto-update)
        if [[ ! -d $FIKA_MOD_DIR ]]; then
            echo "No Fika mod found (FIKA_MODE=$FIKA_MODE). Installing."
            install_fika_mod
        else
            echo "Fika mod already present, skipping install"
        fi
        ;;
    custom)
        if [[ ! -d $FIKA_MOD_DIR ]]; then
            echo "WARNING: FIKA_MODE=custom but no Fika mod found at $FIKA_MOD_DIR"
            echo "Manually install your custom Fika build to that directory."
        fi
        ;;
    disabled)
        ;;
esac

set_num_headless_profiles

if [[ "$INSTALL_OTHER_MODS" == "true" ]]; then
    install_requested_mods
fi

if [[ "$ENABLE_PROFILE_BACKUP" == "true" ]]; then
    start_crond
fi

set_timezone

echo "Starting SPT server..."
cd $SPT_DIR && ./$SPT_BINARY
```

- [ ] **Step 4: Final syntax check**

```bash
bash -n scripts/startup.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 5: Commit**

```bash
git add scripts/startup.sh
git commit -m "feat: add config functions and main block to startup.sh"
```

---

### Task 5: Write install.sh

**Files:**
- Modify: `scripts/install.sh`

- [ ] **Step 1: Write the install script**

Replace the full contents of `scripts/install.sh`:

```bash
#!/bin/bash
# SPT + Fika Pterodactyl installer
# Runs in: debian:bookworm-slim
# Server files destination: /mnt/server (= /home/container at runtime)

SPT_DIR=/mnt/server/SPT
SPT_VERSION=${SPT_VERSION:-4.0.13-40087-2891fd4}
FIKA_VERSION=${FIKA_VERSION:-2.2.6}
FIKA_MODE=${FIKA_MODE:-disabled}
LISTEN_ALL_NETWORKS=${LISTEN_ALL_NETWORKS:-true}

echo "=== SPT + Fika Installer ==="
echo "SPT_VERSION=$SPT_VERSION"
echo "FIKA_MODE=$FIKA_MODE"
echo "FIKA_VERSION=$FIKA_VERSION"
echo "LISTEN_ALL_NETWORKS=$LISTEN_ALL_NETWORKS"
echo ""

# Install required tools
echo "Installing tools..."
apt-get update -y -q
apt-get install -y -q --no-install-recommends \
    curl \
    jq \
    p7zip-full \
    unzip \
    libimage-exiftool-perl
echo "Tools installed"

# Install SPT if not already present
# SPT archive extracts with a top-level SPT/ directory, so binary lands at /mnt/server/SPT/SPT.Server.Linux
if [[ -f "$SPT_DIR/SPT.Server.Linux" ]]; then
    echo "SPT server binary found at $SPT_DIR, skipping download"
else
    echo "Downloading SPT $SPT_VERSION..."
    mkdir -p /mnt/server
    cd /tmp
    curl -L "https://spt-releases.modd.in/SPT-${SPT_VERSION}.7z" -o spt.7z
    7za x spt.7z -o/mnt/server
    rm spt.7z
    mkdir -p $SPT_DIR/user/mods $SPT_DIR/user/profiles
    echo "SPT installed to $SPT_DIR"
fi

# Install Fika server mod if requested and not already present
FIKA_MOD_DIR=$SPT_DIR/user/mods/fika-server
if [[ "$FIKA_MODE" == "install" || "$FIKA_MODE" == "auto-update" ]]; then
    if [[ -d "$FIKA_MOD_DIR" ]]; then
        echo "Fika server mod already present at $FIKA_MOD_DIR, skipping download"
    else
        echo "Downloading Fika server mod $FIKA_VERSION..."
        FIKA_ARTIFACT=Fika.Server.Release.$FIKA_VERSION.zip
        FIKA_URL="https://github.com/project-fika/Fika-Server-CSharp/releases/download/v${FIKA_VERSION}/${FIKA_ARTIFACT}"
        mkdir -p $SPT_DIR/user/mods
        cd /tmp
        curl -L "$FIKA_URL" -o $FIKA_ARTIFACT
        unzip -q $FIKA_ARTIFACT -d /tmp/fika_temp/
        mv /tmp/fika_temp/SPT/user/mods/fika-server $FIKA_MOD_DIR
        rm -rf /tmp/fika_temp /tmp/$FIKA_ARTIFACT
        echo "Fika server mod installed to $FIKA_MOD_DIR"
    fi
fi

# Patch http.json for listen-on-all-interfaces if the config file exists
HTTP_JSON=$SPT_DIR/SPT_Data/configs/http.json
if [[ "$LISTEN_ALL_NETWORKS" == "true" && -f "$HTTP_JSON" ]]; then
    echo "Configuring SPT to listen on all network interfaces"
    modified=$(jq '.ip = "0.0.0.0" | .backendIp = "0.0.0.0"' $HTTP_JSON)
    echo -E "$modified" > $HTTP_JSON
fi

# Write startup.sh — build.py replaces __STARTUP_SH__ with scripts/startup.sh content
echo "Writing /mnt/server/startup.sh..."
cat > /mnt/server/startup.sh << 'STARTUP_SCRIPT_EOF'
__STARTUP_SH__
STARTUP_SCRIPT_EOF
chmod +x /mnt/server/startup.sh
echo "startup.sh written"

echo ""
echo "=== Installation complete ==="
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/install.sh && echo "OK"
```

Expected output: `OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: add install.sh for Pterodactyl installer container"
```

---

### Task 6: Build and validate the egg

**Files:**
- Create: `egg-spt-fika.json`

- [ ] **Step 1: Run the build**

```bash
python3 build.py
```

Expected output: `Built egg-spt-fika.json successfully`

- [ ] **Step 2: Validate the JSON is well-formed**

```bash
python3 -m json.tool egg-spt-fika.json > /dev/null && echo "Valid JSON"
```

Expected output: `Valid JSON`

- [ ] **Step 3: Verify install script is embedded and placeholder replaced**

```bash
python3 -c "
import json
with open('egg-spt-fika.json') as f:
    egg = json.load(f)
script = egg['scripts']['installation']['script']
assert 'apt-get install' in script, 'apt-get install not found in install script'
assert '__STARTUP_SH__' not in script, 'placeholder __STARTUP_SH__ was not replaced'
assert 'SPT.Server.Linux' in script, 'SPT binary reference not in embedded startup.sh'
assert 'FIKA_REMOTE_SHA' in script, 'Fika validation logic not in embedded startup.sh'
assert '/home/container/backup.sh' in script, 'custom backup.sh not in embedded startup.sh'
print('Install script embedding: OK')
"
```

Expected output: `Install script embedding: OK`

- [ ] **Step 4: Verify all 13 env vars are present**

```bash
python3 -c "
import json
with open('egg-spt-fika.json') as f:
    egg = json.load(f)
expected = {
    'SPT_VERSION', 'FIKA_VERSION', 'FIKA_MODE', 'AUTO_UPDATE_SPT',
    'FORCE_SPT_VERSION', 'LISTEN_ALL_NETWORKS', 'ENABLE_PROFILE_BACKUP',
    'TAKE_OWNERSHIP', 'CHANGE_PERMISSIONS', 'NUM_HEADLESS_PROFILES',
    'INSTALL_OTHER_MODS', 'MOD_URLS_TO_DOWNLOAD', 'TZ'
}
found = {v['env_variable'] for v in egg['variables']}
missing = expected - found
assert not missing, f'Missing variables: {missing}'
print(f'All {len(found)} env vars present: OK')
"
```

Expected output: `All 13 env vars present: OK`

- [ ] **Step 5: Verify egg metadata**

```bash
python3 -c "
import json
with open('egg-spt-fika.json') as f:
    egg = json.load(f)
assert egg['startup'] == 'bash /home/container/startup.sh', f'Wrong startup: {egg[\"startup\"]}'
assert egg['scripts']['installation']['container'] == 'debian:bookworm-slim'
assert egg['scripts']['installation']['entrypoint'] == 'bash'
assert 'ghcr.io/zhliau/fika-spt-server-docker:latest' in egg['docker_images']
assert egg['meta']['version'] == 'PTDL_v2'
print('Egg metadata: OK')
"
```

Expected output: `Egg metadata: OK`

- [ ] **Step 6: Commit**

```bash
git add egg-spt-fika.json
git commit -m "feat: generate egg-spt-fika.json Pterodactyl egg"
```

---

### Task 7: Smoke test the install script

Verifies that install.sh runs without error and produces the correct file structure. Requires Docker on the host.

**Files:** None modified (test only; commit fixes if any)

- [ ] **Step 1: Run install.sh in a Debian container**

This downloads ~500 MB of SPT server files to `/tmp/spt-test`. Takes 2–5 minutes.

```bash
mkdir -p /tmp/spt-test
docker run --rm \
    -e SPT_VERSION=4.0.13-40087-2891fd4 \
    -e FIKA_MODE=disabled \
    -e LISTEN_ALL_NETWORKS=true \
    -v /tmp/spt-test:/mnt/server \
    -v "$(pwd)/scripts/install.sh:/install.sh" \
    debian:bookworm-slim \
    bash /install.sh
```

Expected: script exits cleanly with `=== Installation complete ===`

- [ ] **Step 2: Verify file structure**

```bash
ls /tmp/spt-test/SPT/
```

Expected to include: `SPT.Server.Linux  SPT_Data  user`

```bash
ls /tmp/spt-test/SPT/user/
```

Expected to include: `mods  profiles`

- [ ] **Step 3: Verify startup.sh was written and placeholder is gone**

```bash
head -1 /tmp/spt-test/startup.sh
grep -c '__STARTUP_SH__' /tmp/spt-test/startup.sh
```

Expected: first line is `#!/bin/bash -e`, grep count is `0`

- [ ] **Step 4: Verify http.json was patched**

```bash
python3 -c "
import json
with open('/tmp/spt-test/SPT/SPT_Data/configs/http.json') as f:
    cfg = json.load(f)
assert cfg['ip'] == '0.0.0.0', f'ip is {cfg[\"ip\"]}'
assert cfg['backendIp'] == '0.0.0.0', f'backendIp is {cfg[\"backendIp\"]}'
print('http.json patched correctly: OK')
"
```

Expected output: `http.json patched correctly: OK`

- [ ] **Step 5: Syntax check the written startup.sh**

```bash
bash -n /tmp/spt-test/startup.sh && echo "startup.sh syntax OK"
```

Expected output: `startup.sh syntax OK`

- [ ] **Step 6: Clean up**

```bash
rm -rf /tmp/spt-test
```

- [ ] **Step 7: Rebuild egg and commit if any script fixes were made**

Only needed if steps 1–5 revealed bugs requiring script changes:

```bash
python3 build.py
git add scripts/ egg-spt-fika.json
git commit -m "fix: correct install/startup script issues found in smoke test"
```

---

## Self-review

**Spec coverage:**
- ✓ All 13 env vars in `egg-template.json` with correct defaults (LISTEN_ALL_NETWORKS=true)
- ✓ Runtime image: `ghcr.io/zhliau/fika-spt-server-docker:latest`
- ✓ Installer container: `debian:bookworm-slim`
- ✓ Startup command: `bash /home/container/startup.sh`
- ✓ All paths use `/home/container` instead of `/opt/server`
- ✓ `enforce_spt_4_structure` included for migration support
- ✓ `validate` covers SPT version check + all four `FIKA_MODE` branches
- ✓ SPT auto-update: `install_spt` / `try_update_spt` / `backup_spt_user_dirs`
- ✓ Fika management: `install_fika_mod` / `try_update_fika` / `backup_fika`
- ✓ `spt_listen_on_all_networks` patches both `http.json` and Fika config
- ✓ `set_num_headless_profiles` patches `fika.jsonc`
- ✓ `install_requested_mods` calls `/usr/bin/download_unzip_install_mods` (in runtime image)
- ✓ `start_crond` writes custom `/home/container/backup.sh` (not `/usr/bin/backup`)
- ✓ `set_timezone` from env var or `/etc/timezone`
- ✓ Backwards-compat mapping for deprecated `INSTALL_FIKA` / `AUTO_UPDATE_FIKA`
- ✓ UID/GID and chown/chmod dropped
- ✓ Volume mount check dropped
- ✓ `su -` wrapper dropped; binary run directly
- ✓ `build.py` assembles final egg from template + scripts
- ✓ All 6 validation checks in Task 6
- ✓ Smoke test in Task 7

**Type/name consistency:** All function names defined in Task 2–4 match call sites. `SPT_DIR`, `SPT_DATA_DIR`, `FIKA_MOD_DIR`, `FIKA_CONFIG_PATH` are declared once in Task 2 and used consistently. `install_spt` calls `make_spt_dirs` (defined in same task). `try_update_spt` calls `backup_spt_user_dirs` and `install_spt` (same task). `try_update_fika` calls `backup_fika` and `install_fika_mod` (same task). `validate` calls `enforce_spt_4_structure`, `try_update_spt`, `try_update_fika` (all defined before).
