#!/bin/bash
set -e

# Runtime tools (jq, 7zz, curl, exiftool, unzip, tar) and the .NET 9 ASP.NET
# runtime are provided by the custom image (ghcr.io/djhype/fika-spt-ptero).
# The container root filesystem is read-only; only /home/container is writable.

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

# Other settings
LISTEN_ALL_NETWORKS=${LISTEN_ALL_NETWORKS:-true}
ENABLE_PROFILE_BACKUP=${ENABLE_PROFILE_BACKUP:-true}
INSTALL_OTHER_MODS=${INSTALL_OTHER_MODS:-false}
NUM_HEADLESS_PROFILES=${NUM_HEADLESS_PROFILES:+"$NUM_HEADLESS_PROFILES"}

# Pterodactyl sends "1"/"0" for boolean variables; normalise to "true"/"false"
[[ "$LISTEN_ALL_NETWORKS"  == "1" ]] && LISTEN_ALL_NETWORKS=true
[[ "$ENABLE_PROFILE_BACKUP" == "1" ]] && ENABLE_PROFILE_BACKUP=true
[[ "$AUTO_UPDATE_SPT"      == "1" ]] && AUTO_UPDATE_SPT=true
[[ "$INSTALL_OTHER_MODS"   == "1" ]] && INSTALL_OTHER_MODS=true

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

# -----------------------------------------------------------------------
# SPT Functions
# -----------------------------------------------------------------------

enforce_spt_4_structure() {
    # If SPT.Server.Linux is loose in MOUNTED_DIR this is a migrated install.
    # Move all loose files into the SPT/ subdirectory.
    if [[ -f $MOUNTED_DIR/$SPT_BINARY ]]; then
        echo "Enforcing SPT 4.0 directory structure"
        mkdir -p $SPT_DIR
        for item in "$MOUNTED_DIR"/*; do
            base_item=$(basename "$item")
            if [[ "$base_item" != "SPT" ]]; then
                mv "$item" "$SPT_DIR"
            fi
        done
    fi
}

make_spt_dirs() {
    mkdir -p "$SPT_DIR/user/mods"
    mkdir -p "$SPT_DIR/user/profiles"
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
        echo "Downloading SPT $SPT_VERSION"
        curl -sL "https://spt-releases.modd.in/SPT-${SPT_VERSION}.7z" -o "${MOUNTED_DIR}/spt.7z"
        7zz x "${MOUNTED_DIR}/spt.7z" -o${MOUNTED_DIR} -aoa
        rm "${MOUNTED_DIR}/spt.7z"
    fi
    make_spt_dirs
    # Write version marker so validate() doesn't need exiftool for basic checks
    echo "$SPT_VERSION" > "$SPT_DIR/.spt-version"
}

backup_spt_user_dirs() {
    mkdir -p "$SPT_BACKUP_DIR"
    cp -r "$SPT_DIR/user" "$SPT_BACKUP_DIR/"
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

# -----------------------------------------------------------------------
# Fika Functions
# -----------------------------------------------------------------------

install_fika_mod() {
    echo "Installing Fika server mod $FIKA_VERSION"
    mkdir -p "$SPT_DIR/user/mods"
    cd /tmp
    curl -sL "$FIKA_RELEASE_URL" -O
    # Use 7zz to extract (unzip not available; 7-zip handles zip format)
    7zz x "$FIKA_ARTIFACT" -o/tmp/fika_temp/ -y
    mv /tmp/fika_temp/SPT/user/mods/fika-server "$FIKA_MOD_DIR"
    rm -rf /tmp/fika_temp "/tmp/$FIKA_ARTIFACT"
    echo "Fika installation complete"
}

backup_fika() {
    mkdir -p "$FIKA_BACKUP_DIR"
    cp -r "$FIKA_MOD_DIR" "$FIKA_BACKUP_DIR"
}

try_update_fika() {
    echo "Updating Fika server mod to $FIKA_VERSION"
    backup_fika
    rm -rf "$FIKA_MOD_DIR"
    install_fika_mod
    # Restore previous config if it exists
    mkdir -p "$FIKA_MOD_DIR/assets/configs"
    local existing_config=$FIKA_BACKUP_DIR/fika-server/$FIKA_CONFIG_PATH
    if [[ -f $existing_config ]]; then
        cp "$existing_config" "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH"
    fi
    echo "Successfully updated Fika to $FIKA_VERSION"
}

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
        # Prefer version marker written by install_spt; fall back to exiftool if available
        if [[ -f "$SPT_DIR/.spt-version" ]]; then
            existing_version=$(cut -d '-' -f 1 < "$SPT_DIR/.spt-version")
        elif command -v exiftool &>/dev/null; then
            existing_version=$(exiftool -s -s -s -ProductVersion "$SPT_DIR/SPT.Server.dll" \
                | cut -d '-' -f 1 || echo "unknown")
        else
            echo "WARNING: No version info available (.spt-version missing, exiftool absent). Skipping version check."
            existing_version="$SPT_VERSION_SHORT"
        fi

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
                local fika_remote_sha=""
                if command -v curl &>/dev/null; then
                    fika_remote_sha=$(curl -s "https://api.github.com/repos/project-fika/Fika-Server-CSharp/git/refs/tags/v$FIKA_VERSION" | grep -oP '"sha":\s*"\K[^"]+' || true)
                fi
                if [[ -f "$FIKA_MOD_DIR/FikaServer.dll" ]] && command -v exiftool &>/dev/null; then
                    fika_local_sha=$(exiftool -s -s -s -ProductVersion \
                        "$FIKA_MOD_DIR/FikaServer.dll" | grep -oP '[0-9.]+\+\K.*' || true)
                fi
                if [[ -n "$fika_remote_sha" && "$fika_local_sha" != "$fika_remote_sha" ]]; then
                    echo "Fika SHA mismatch: local=$fika_local_sha expected=$fika_remote_sha"
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

# -----------------------------------------------------------------------
# Config + Runtime Functions
# -----------------------------------------------------------------------

spt_listen_on_all_networks() {
    local server_port=${SERVER_PORT:-6969}
    # 'ip' is what the server binds to (0.0.0.0 = all interfaces).
    # 'backendIp' is the address the server advertises to game clients — it MUST be
    # reachable by the client. For remote clients set BACKEND_IP to the server's
    # LAN/public IP; if blank, fall back to 0.0.0.0 (only works for a same-host client).
    local backend_ip=${BACKEND_IP:-0.0.0.0}
    local http_json=$SPT_DATA_DIR/configs/http.json
    if [[ ! -f $http_json ]]; then
        echo "WARNING: $http_json not found, skipping network config"
        return
    fi
    local modified
    modified="$(jq --arg ip "$backend_ip" --arg port "$server_port" \
        '.ip = "0.0.0.0" | .backendIp = $ip | .port = ($port | tonumber) | .backendPort = ($port | tonumber)' \
        "$http_json")"
    echo -E "${modified}" > "$http_json"
    echo "SPT bound to 0.0.0.0:$server_port; backend advertised to clients as $backend_ip:$server_port"
    if [[ "$backend_ip" == "0.0.0.0" ]]; then
        echo "  NOTE: BACKEND_IP is unset — remote clients will fail to connect. Set BACKEND_IP to this server's reachable IP."
    fi

    if [[ -f "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH" ]]; then
        echo "Applying network config to Fika config"
        local modified_fika
        modified_fika="$(jq --arg ip "$backend_ip" --arg port "$server_port" \
            '.server.SPT.http.ip = "0.0.0.0" | .server.SPT.http.backendIp = $ip | .server.SPT.http.port = ($port | tonumber) | .server.SPT.http.backendPort = ($port | tonumber)' \
            "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH")"
        echo -E "${modified_fika}" > "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH"
    fi
}

set_num_headless_profiles() {
    if [[ ${NUM_HEADLESS_PROFILES:+1} && -f "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH" ]]; then
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
    # Best-effort: never abort server startup because a mod failed to download/extract.
    set +e

    local mod_dl_dir=$SPT_DIR/mod_download
    local remains_dir=$mod_dl_dir/remains
    local urls_file=$mod_dl_dir/mod_urls_to_download.txt
    local downloaded_file=$mod_dl_dir/mod_urls_downloaded.txt
    local log_file=$mod_dl_dir/download_unzip_install_mods.log
    local plugins_dir=$MOUNTED_DIR/BepInEx/plugins
    local tmp_dir=/tmp/download_mods
    local tmp_dl=$tmp_dir/downloaded
    local tmp_ex=$tmp_dir/extracted

    mkdir -p "$mod_dl_dir" "$tmp_dl" "$tmp_ex" "$SPT_DIR/user/mods"
    touch "$urls_file" "$downloaded_file" "$log_file"
    echo "Run $(date +'%d/%m/%Y %H:%M:%S')" >> "$log_file"

    # Collect requested URLs from the env var and the file, skip already-downloaded ones
    local all_urls=""
    [[ -n "${MOD_URLS_TO_DOWNLOAD}" ]] && all_urls="$MOD_URLS_TO_DOWNLOAD"
    if [[ -s "$urls_file" ]]; then
        all_urls="$all_urls $(tr '\n' ' ' < "$urls_file")"
    fi

    local new_urls="" url
    for url in $all_urls; do
        [[ -z "$url" ]] && continue
        grep -qF -- "$url" "$downloaded_file" && continue          # already downloaded
        case " $new_urls " in *" $url "*) continue ;; esac          # dedup within this run
        new_urls="$new_urls $url"
    done

    if [[ -z "${new_urls// }" ]]; then
        echo "  No new mod URLs to download"
        rm -rf "$tmp_dir"
        set -e
        return
    fi

    # Download each new URL with curl (-J -O honours content-disposition / URL filename)
    for url in $new_urls; do
        echo "  Downloading $url" | tee -a "$log_file"
        if curl -sL -J -O --output-dir "$tmp_dl" "$url" >> "$log_file" 2>&1; then
            echo "$url" >> "$downloaded_file"
        else
            echo "  WARNING: failed to download $url" | tee -a "$log_file"
        fi
    done

    # Extract archives (.zip/.7z via 7zz, .tar* via tar)
    shopt -s nullglob
    local archive
    for archive in "$tmp_dl"/*.zip "$tmp_dl"/*.7z; do
        echo "  Extracting $(basename "$archive")" >> "$log_file"
        7zz x "$archive" -o"$tmp_ex" -y >> "$log_file" 2>&1
        rm -f "$archive"
    done
    for archive in "$tmp_dl"/*.tar "$tmp_dl"/*.tar.gz "$tmp_dl"/*.tgz; do
        if command -v tar &>/dev/null; then
            echo "  Extracting $(basename "$archive")" >> "$log_file"
            tar -xf "$archive" -C "$tmp_ex" >> "$log_file" 2>&1
            rm -f "$archive"
        else
            echo "  WARNING: tar unavailable; cannot extract $(basename "$archive")" | tee -a "$log_file"
        fi
    done

    # Install extracted content to the correct locations
    mkdir -p "$plugins_dir"
    local f d
    # loose .dll files -> BepInEx/plugins
    for f in "$tmp_ex"/*.dll; do cp -f "$f" "$plugins_dir/"; rm -f "$f"; done
    # BepInEx/plugins (handle capitalised Plugins too) -> BepInEx/plugins
    for d in "$tmp_ex"/BepInEx/plugins "$tmp_ex"/BepInEx/Plugins; do
        [[ -d "$d" ]] && cp -rf "$d"/. "$plugins_dir/"
    done
    rm -rf "$tmp_ex"/BepInEx
    # SPT/ wrapper (contains user/mods etc.) -> merge into SPT dir
    [[ -d "$tmp_ex/SPT" ]]  && { cp -rf "$tmp_ex"/SPT/.  "$SPT_DIR/";      rm -rf "$tmp_ex"/SPT; }
    # bare user/ tree -> merge into SPT/user
    [[ -d "$tmp_ex/user" ]] && { cp -rf "$tmp_ex"/user/. "$SPT_DIR/user/"; rm -rf "$tmp_ex"/user; }
    # docs / executables -> server root
    for f in "$tmp_ex"/*.txt "$tmp_ex"/*.md "$tmp_ex"/*.exe; do cp -f "$f" "$SPT_DIR/"; rm -f "$f"; done
    # bare .dll downloads (not inside an archive) -> BepInEx/plugins
    for f in "$tmp_dl"/*.dll; do cp -f "$f" "$plugins_dir/"; rm -f "$f"; done

    # Anything we could not place -> mod_download/remains for manual handling
    if [[ -n "$(ls -A "$tmp_ex" 2>/dev/null)" || -n "$(ls -A "$tmp_dl" 2>/dev/null)" ]]; then
        mkdir -p "$remains_dir"
        cp -rf "$tmp_ex"/. "$remains_dir/" 2>/dev/null
        cp -rf "$tmp_dl"/. "$remains_dir/" 2>/dev/null
        echo "  Some files could not be auto-installed; moved to mod_download/remains" | tee -a "$log_file"
    fi
    shopt -u nullglob

    rm -rf "$tmp_dir"
    echo "  Mod installation complete. Log: mod_download/download_unzip_install_mods.log"
    set -e
}

start_crond() {
    # Write backup script to server volume (writable)
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

    # /etc/cron.d and /etc/init.d are on the read-only container fs; skip cron registration.
    # SPT Server has built-in profile backup which replaces this feature.
    echo "NOTE: cron-based profile backup not available (read-only container fs)."
    echo "      SPT Server's built-in backup system handles profile backups."
}

set_timezone() {
    # /etc is read-only in the Pterodactyl container; only set what we can.
    # .NET/SPT honour the TZ environment variable, so exporting it is sufficient.
    if [[ -z "${TZ}" ]]; then
        TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    fi
    export TZ
    # Best-effort: only attempt /etc writes if that path is writable (it usually is not)
    if [[ -w /etc/timezone ]]; then echo "$TZ" > /etc/timezone; fi
    if [[ -w /etc ]]; then ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime 2>/dev/null || true; fi
    echo "Timezone: $TZ"
}

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
        if [[ ! -d "$FIKA_MOD_DIR" ]]; then
            echo "No Fika mod found (FIKA_MODE=$FIKA_MODE). Installing."
            install_fika_mod
        else
            echo "Fika mod already present, skipping install"
        fi
        ;;
    custom)
        if [[ ! -d "$FIKA_MOD_DIR" ]]; then
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
cd "$SPT_DIR" && ./$SPT_BINARY
