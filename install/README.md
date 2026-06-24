# Fabroq — run-it-yourself installer

Public home of the one-command Fabroq launcher installer. These scripts are
served at **https://get.fabroq.com** (Cloudflare → this repo's raw files).

```sh
# macOS / Linux
curl -fsSL https://get.fabroq.com | sh

# Windows (PowerShell)
irm https://get.fabroq.com/install.ps1 | iex
```

Both install the thin **`fabroq` launcher** — a small, open downloader with **no
engine** in it. You then sign in and start it:

```
fabroq login   # sign in to your Fabroq account
fabroq up      # downloads your engine runtime (once) + starts the gateway + engine
fabroq pair    # approve a phone that's connecting
```

## How it works (and why the engine stays private)

The Fabroq **engine** (the planner / verifier / checker — the moat, and the paid
**Engine Pro** tier) is **never published publicly**: not its source, not its
runtime. Instead:

1. `curl … | sh` installs only the thin `fabroq` launcher (this repo) — it
   contains no engine, no prompts, no secrets.
2. `fabroq login` stores your Fabroq account token.
3. `fabroq up` **authed-downloads** your engine runtime
   (`host-runtime-<platform>-<arch>.zip`) from **`api.fabroq.com/engine/runtime`**
   using your token, verifies its SHA-256, and extracts it to a machine-local dir
   (downloaded **once**, then cached). An **anonymous** download is **rejected
   (HTTP 401)**; if the server requires entitlement, a non-entitled account gets
   **HTTP 403**.
4. The runtime is a self-contained bundle (a portable Python + Node + the gateway
   component + the engine), so there are **no system Python/Node/git
   prerequisites**. The launcher delegates `up` / `down` / `status` / `pair` / …
   to the real `fabroqctl` inside the downloaded runtime.

`fabroq up` then starts two real local processes:

1. the **gateway** — the mesh hub the Fabroq mobile app discovers (mDNS), pairs
   with, and connects to over the device-mesh WebSocket protocol (v4); and
2. the **Fabroq engine** behind it as the brain, wired in as an OpenAI-compatible
   model provider, so every turn flows `phone → gateway → engine → model → back`.

On your phone (same Wi-Fi): open Fabroq → Connect → Nearby gateway, and run
`fabroq pair` on the host to approve it.

## Environment overrides

All scripts are idempotent and honor:

| var | default | purpose |
|---|---|---|
| `FABROQ_API` | `https://api.fabroq.com` | the api that serves the authed engine-runtime download |
| `FABROQ_TOKEN` / `FABROQ_TOKEN_FILE` | `~/.fabroq/token` | account token used for the authed download |
| `FABROQ_PREFIX` | `~/.fabroq` | install prefix (launcher + token) |
| `FABROQ_HOST_RUNTIME_DIR` | `%LOCALAPPDATA%\Fabroq\engine-runtime` (Win) / `~/.fabroq/engine-runtime` | where the runtime is cached |
| `FABROQ_LAUNCHER_URL` | `https://get.fabroq.com/fabroq.{sh,ps1}` | launcher source (override for testing) |

There is **no `FABROQ_REPO`** any more: the engine is not fetched from a git repo
— it is the authed runtime download above.

## Files

| file | served at | contains |
|---|---|---|
| `get.fabroq.com.sh` | `https://get.fabroq.com` (and `/`) | macOS/Linux installer (drops the launcher) |
| `install.ps1` | `https://get.fabroq.com/install.ps1` | Windows installer (drops the launcher) |
| `fabroq.sh` | `https://get.fabroq.com/fabroq.sh` | the thin macOS/Linux launcher (no engine) |
| `fabroq.ps1` | `https://get.fabroq.com/fabroq.ps1` | the thin Windows launcher (no engine) |
