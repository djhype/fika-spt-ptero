#!/bin/bash
# SPT + Fika Pterodactyl installer
# Runs in: debian:bookworm-slim
# Server files destination: /mnt/server (= /home/container at runtime)
set -e

SPT_DIR=/mnt/server/SPT
SPT_VERSION=${SPT_VERSION:-4.0.13-40087-2891fd4}
FIKA_VERSION=${FIKA_VERSION:-2.2.6}
FIKA_MODE=${FIKA_MODE:-disabled}
LISTEN_ALL_NETWORKS=${LISTEN_ALL_NETWORKS:-true}

# Normalise Pterodactyl boolean values ("1" -> "true")
[[ "$LISTEN_ALL_NETWORKS" == "1" ]] && LISTEN_ALL_NETWORKS=true

echo "=== SPT + Fika Installer ==="
echo "SPT_VERSION=$SPT_VERSION"
echo "FIKA_MODE=$FIKA_MODE"
echo "FIKA_VERSION=$FIKA_VERSION"
echo "LISTEN_ALL_NETWORKS=$LISTEN_ALL_NETWORKS"
echo ""

# Install tools needed during the install phase (runtime tools live in the image)
echo "Installing tools..."
apt-get update -y -q
apt-get install -y -q --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    p7zip-full \
    unzip
echo "Tools installed"

# Install SPT if not already present
# SPT archive extracts with a top-level SPT/ directory, so binary lands at /mnt/server/SPT/SPT.Server.Linux
if [[ -f "$SPT_DIR/SPT.Server.Linux" ]]; then
    echo "SPT server binary found at $SPT_DIR, skipping download"
else
    echo "Downloading SPT $SPT_VERSION..."
    mkdir -p /mnt/server
    curl -L "https://spt-releases.modd.in/SPT-${SPT_VERSION}.7z" -o /mnt/server/spt.7z
    7za x /mnt/server/spt.7z -o/mnt/server
    rm /mnt/server/spt.7z
    mkdir -p "$SPT_DIR/user/mods" "$SPT_DIR/user/profiles"
    echo "SPT installed to $SPT_DIR"
fi

# Write version marker so startup.sh can check SPT version without exiftool
echo "$SPT_VERSION" > "$SPT_DIR/.spt-version"

# Install Fika server mod if requested and not already present
FIKA_MOD_DIR=$SPT_DIR/user/mods/fika-server
if [[ "$FIKA_MODE" == "install" || "$FIKA_MODE" == "auto-update" ]]; then
    if [[ -d "$FIKA_MOD_DIR" ]]; then
        echo "Fika server mod already present at $FIKA_MOD_DIR, skipping download"
    else
        echo "Downloading Fika server mod $FIKA_VERSION..."
        FIKA_ARTIFACT=Fika.Server.Release.$FIKA_VERSION.zip
        FIKA_URL="https://github.com/project-fika/Fika-Server-CSharp/releases/download/v${FIKA_VERSION}/${FIKA_ARTIFACT}"
        mkdir -p "$SPT_DIR/user/mods"
        cd /tmp
        curl -L "$FIKA_URL" -o "$FIKA_ARTIFACT"
        unzip -q "$FIKA_ARTIFACT" -d /tmp/fika_temp/
        mv /tmp/fika_temp/SPT/user/mods/fika-server "$FIKA_MOD_DIR"
        rm -rf /tmp/fika_temp "/tmp/$FIKA_ARTIFACT"
        echo "Fika server mod installed to $FIKA_MOD_DIR"
    fi
fi

# Patch http.json for listen-on-all-interfaces if the config file exists.
# backendIp (advertised to clients) uses BACKEND_IP when set; startup.sh re-applies
# this on every boot, so this is just the initial value.
HTTP_JSON=$SPT_DIR/SPT_Data/configs/http.json
if [[ "$LISTEN_ALL_NETWORKS" == "true" && -f "$HTTP_JSON" ]]; then
    BACKEND_IP=${BACKEND_IP:-0.0.0.0}
    echo "Configuring SPT to listen on all interfaces (backendIp=$BACKEND_IP)"
    modified=$(jq --arg ip "$BACKEND_IP" '.ip = "0.0.0.0" | .backendIp = $ip' "$HTTP_JSON")
    echo -E "$modified" > "$HTTP_JSON"
fi

# Write startup.sh — build.py inlines scripts/startup.sh here at build time
echo "Writing /mnt/server/startup.sh..."
cat > /mnt/server/startup.sh << 'STARTUP_SCRIPT_EOF'
__STARTUP_SH__
STARTUP_SCRIPT_EOF
chmod +x /mnt/server/startup.sh
echo "startup.sh written"

echo ""
echo "=== Installation complete ==="
