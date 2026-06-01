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
