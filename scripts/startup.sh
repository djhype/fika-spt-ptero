#!/bin/bash
set -e

# Install required tools if missing (only on fresh container; skipped on restart)
if ! command -v jq &>/dev/null || ! command -v 7zz &>/dev/null || ! command -v exiftool &>/dev/null; then
    echo "Installing required runtime tools (first start only)..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        p7zip-full \
        unzip \
        libimage-exiftool-perl \
        cron
    echo "Tools installed"
fi

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
    unzip -q "$FIKA_ARTIFACT" -d /tmp/fika_temp/
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
        existing_version=$(exiftool -s -s -s -ProductVersion "$SPT_DIR/SPT.Server.dll" \
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
                if [[ -f "$FIKA_MOD_DIR/FikaServer.dll" ]]; then
                    fika_local_sha=$(exiftool -s -s -s -ProductVersion \
                        "$FIKA_MOD_DIR/FikaServer.dll" | grep -oP '[0-9.]+\+\K.*')
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
    modified="$(jq '.ip = "0.0.0.0" | .backendIp = "0.0.0.0"' "$http_json")"
    echo -E "${modified}" > "$http_json"

    if [[ -f "$FIKA_MOD_DIR/$FIKA_CONFIG_PATH" ]]; then
        echo "Applying LISTEN_ALL_NETWORKS to Fika config"
        local modified_fika
        modified_fika="$(jq '.server.SPT.http.ip = "0.0.0.0" | .server.SPT.http.backendIp = "0.0.0.0"' \
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
    /usr/bin/download_unzip_install_mods "$SPT_DIR"
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
        echo "$TZ" > /etc/timezone
    else
        local before_hour
        before_hour=$(date +"%H")
        TZ=$(cat /etc/timezone)
    fi
    ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
    if [[ ${before_hour:-} != $(date +"%H") ]]; then
        echo "Timezone set to $TZ"
    fi
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
