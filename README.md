# SPT + Fika — Pterodactyl Egg

A [Pterodactyl](https://pterodactyl.io/) egg for running a **Single Player Tarkov (SPT) 4.x** server with the optional **[Fika](https://github.com/project-fika)** multiplayer mod, with full feature parity to the [`zhliau/fika-spt-server-docker`](https://github.com/zhliau/fika-spt-server-docker) image but adapted to run natively under Pterodactyl.

The egg ships everything as a single importable file (`egg-spt-fika.json`) and is backed by a small custom Docker image so the server starts automatically and SPT's HTTPS works out of the box.

---

## Features

- 📦 **One-file import** — `egg-spt-fika.json` into any Pterodactyl panel.
- 🎛️ **13 configurable variables** — SPT/Fika versions, auto-update, headless profiles, timezone, and more.
- 🤝 **Optional Fika** — install or auto-update the Fika server mod (`FIKA_MODE`).
- ⬆️ **Auto-update** — optionally update SPT and/or Fika on a version mismatch at startup.
- ⬇️ **Mod auto-installer** — download and install additional mods from a URL list.
- 🌐 **Port-aware** — binds SPT to the Pterodactyl-allocated port automatically.
- 🐳 **Custom runtime image** — .NET 9 ASP.NET runtime + tools, published to GHCR via CI.

---

## Requirements

- A Pterodactyl panel + Wings node.
- The custom runtime image published and **public** (see [Runtime image](#runtime-image)).

---

## Quick start

1. **Publish the runtime image** (one-time — see [Runtime image](#runtime-image)).
2. In the panel: **Admin → Nests → Import Egg** → upload `egg-spt-fika.json`.
3. Create a server using the **SPT + Fika** egg. Set `FIKA_MODE` to `install` or `auto-update` if you want Fika.
4. The install script downloads SPT (and Fika), then the server starts automatically.
5. Connect your SPT launcher to `https://<node-ip>:<allocated-port>`.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `SPT_VERSION` | `4.0.13-40087-2891fd4` | SPT release string (`VERSION-EFT_BUILD-GIT_SHA`). |
| `FIKA_VERSION` | `2.2.6` | Fika server mod version. |
| `FIKA_MODE` | `disabled` | `disabled` / `install` / `auto-update` / `custom`. |
| `AUTO_UPDATE_SPT` | `0` | Auto-update SPT on a version mismatch at startup. |
| `FORCE_SPT_VERSION` | *(empty)* | Force a specific SPT version (disables auto-update). |
| `LISTEN_ALL_NETWORKS` | `1` | Bind SPT to `0.0.0.0` so it is reachable in the container. |
| `ENABLE_PROFILE_BACKUP` | `1` | Write a profile backup helper (SPT's built-in backup is primary). |
| `TAKE_OWNERSHIP` | `1` | Kept for upstream compatibility; no effect under Pterodactyl. |
| `CHANGE_PERMISSIONS` | `1` | Kept for upstream compatibility; no effect under Pterodactyl. |
| `NUM_HEADLESS_PROFILES` | *(empty)* | Auto-generate this many Fika headless profiles. |
| `INSTALL_OTHER_MODS` | `0` | Enable the mod auto-installer. |
| `MOD_URLS_TO_DOWNLOAD` | *(empty)* | Space-separated mod download URLs. |
| `TZ` | *(empty)* | Timezone (TZ database identifier, e.g. `America/New_York`). |

> The server port is taken automatically from Pterodactyl's primary allocation (`SERVER_PORT`); it is not a user-editable variable.

---

## Mod auto-installer

Set `INSTALL_OTHER_MODS=1` and put space-separated URLs in `MOD_URLS_TO_DOWNLOAD` (or one per line in `SPT/mod_download/mod_urls_to_download.txt`). On each start the server will:

- Download new URLs (skipping ones already recorded in `mod_urls_downloaded.txt`).
- Extract `.zip` / `.7z` / `.tar*` archives.
- Place `BepInEx/plugins`, `SPT/`, and `user/` trees and loose `.dll`s into the right locations.
- Move anything it can't auto-place into `SPT/mod_download/remains/` for manual handling.

Full details are logged to `SPT/mod_download/download_unzip_install_mods.log`.

> ⚠️ Like upstream, this is a best-effort drag-and-drop installer — it does **not** check mod versions or compatibility. Server-side mods configured by external tools (e.g. ServerValueModifier) should be copied over from a working install along with their config.

---

## Runtime image

Pterodactyl launches a server by injecting the startup command into the `STARTUP` environment variable and relying on the image's entrypoint to execute it. No prebuilt image has **both** the .NET 9 runtime SPT needs **and** that Pterodactyl entrypoint, so this repo builds a small one:

- Base: `mcr.microsoft.com/dotnet/aspnet:9.0-bookworm-slim` (ASP.NET 9 runtime, OpenSSL 3, ICU).
- Adds: `jq`, `7zz`, `curl`, `exiftool`, `unzip`, `tar`.
- Adds: a non-root `container` user and a Pterodactyl-style entrypoint that evaluates `$STARTUP`.

The GitHub Actions workflow (`.github/workflows/build-image.yml`) builds `image/` and publishes it to `ghcr.io/<owner>/<repo>:latest` on every push that touches `image/`.

**Make the package public** after the first publish (GitHub → Packages → *package* → Package settings → Change visibility → Public) so Wings can pull it without authentication.

---

## Repository layout

| Path | Purpose |
|---|---|
| `egg-spt-fika.json` | The built egg (import this). |
| `egg-template.json` | Egg skeleton with variables; the install script is injected at build. |
| `scripts/install.sh` | Runs in the install container: downloads SPT/Fika, writes `startup.sh`. |
| `scripts/startup.sh` | Runs at server start: validation, updates, Fika, mods, then launches SPT. |
| `build.py` | Inlines `startup.sh` into `install.sh` and assembles `egg-spt-fika.json`. |
| `image/` | `Dockerfile` + `entrypoint.sh` for the custom runtime image. |
| `.github/workflows/build-image.yml` | Builds and publishes the runtime image to GHCR. |

### Building the egg

```bash
python3 build.py   # regenerates egg-spt-fika.json from the template + scripts
```

---

## Credits

- SPT — <https://sp-tarkov.com/>
- Fika — <https://github.com/project-fika>
- Upstream Docker reference — [`zhliau/fika-spt-server-docker`](https://github.com/zhliau/fika-spt-server-docker)

---

## Disclosure: built with Claude

This project — the egg, the build tooling, the install/startup scripts, the custom Docker image, and this README — was created with the assistance of **Anthropic's Claude** (via Claude Code). It was developed and iterated through an AI-assisted workflow.

Please keep that in mind when using it:

- **Review before you run it.** Read the scripts (`scripts/`, `image/`) and the egg before importing into your panel. Don't run code you haven't reviewed, regardless of who or what wrote it.
- **Test in a throwaway environment first.** Validate on a non-production server and **back up your profiles and server files** before pointing it at anything you care about.
- **No warranty.** This is provided as-is, with no guarantee of correctness, security, or fitness for any purpose. You are responsible for what you deploy.
- **Report issues responsibly.** If you find a bug or a security problem, please open an issue (or, for anything sensitive, contact the maintainer privately) rather than disclosing it publicly before it can be addressed.

AI-generated code can contain mistakes or outdated assumptions — human review is expected, not optional.
