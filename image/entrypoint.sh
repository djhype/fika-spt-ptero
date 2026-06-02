#!/bin/bash
# Pterodactyl-style entrypoint: Wings passes the server's startup command in the
# $STARTUP environment variable and expects the image to run it. This mirrors the
# behaviour of the official Pterodactyl "yolks" images.

cd /home/container || exit 1

# Best-effort internal IP (some eggs reference {{INTERNAL_IP}}); never fail if absent.
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2); exit}')
export INTERNAL_IP

# Convert "{{VARIABLE}}" tokens to "${VARIABLE}" and expand against the container env.
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$PARSED"

# shellcheck disable=SC2086
exec env ${PARSED}
