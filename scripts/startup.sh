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
