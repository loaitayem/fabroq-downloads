# Fabroq — run-it-yourself installer

Public home of the one-command Fabroq gateway-host installer. These scripts are
served at **https://get.fabroq.com** (Cloudflare → this repo's raw files).

```sh
# macOS / Linux
curl -fsSL https://get.fabroq.com | sh

# Windows (PowerShell)
irm https://get.fabroq.com/install.ps1 | iex
```

Both install the **Fabroq engine + the `fabroq` CLI** (the gateway host) and the
gateway component (the device-mesh hub), then print:

```
fabroq up      # start your gateway + engine
fabroq pair    # approve a phone that's connecting
```

## What gets installed

`fabroq up` starts two real local processes:

1. the **gateway** — the mesh hub the Fabroq mobile app discovers (mDNS), pairs
   with, and connects to over the device-mesh WebSocket protocol (v4); and
2. the **Fabroq engine** behind it as the brain, wired in as an OpenAI-compatible
   model provider, so every chat/agent turn flows
   `phone → gateway → Fabroq engine → model → back`.

Then on your phone (same Wi-Fi): open Fabroq → Connect → Nearby gateway, and run
`fabroq pair` on the host to approve it.

## Environment overrides

Both scripts are idempotent and honor:

| var | default | purpose |
|---|---|---|
| `FABROQ_REPO`   | *(none yet — see Engine source)* | git URL (or tarball) the engine + CLI are fetched from |
| `FABROQ_REF`    | `main` | branch/tag/ref to install |
| `FABROQ_PREFIX` | `~/.fabroq` | install prefix |
| `OPENCLAW_PKG`  | `openclaw@2026.6.6` | npm package + version for the gateway component (pinned, protocol v4) |

## Engine source

Which parts of the engine are public for run-it-yourself is a pending **owner
decision**, so there is **no public engine package yet** and therefore no
working default source. The installer handles this honestly: it probes the
intended default repo and, if it is not yet public, **fails with a clear
message** (it never throws a confusing raw `git` 404).

Install today by pointing `FABROQ_REPO` at any reachable source:

```sh
# macOS / Linux
FABROQ_REPO=https://github.com/you/your-engine.git curl -fsSL https://get.fabroq.com | sh
```
```powershell
# Windows
$env:FABROQ_REPO='https://github.com/you/your-engine.git'; irm https://get.fabroq.com/install.ps1 | iex
```

`FABROQ_REPO` also accepts a release tarball URL (`.tar.gz`, `.tgz`, `.zip`).

**Owner action (one-time) to make the bare one-liner work:** publish the engine
source — either create the public repo
`https://github.com/loaitayem/fabroq-engine.git` (trimmed CLI + gateway-host +
a model backend; **no** planner/verifier/decision-ledger moat), or publish a
release tarball and set it as the `FABROQ_REPO` default in the two scripts. The
installer probes the default repo on every run, so **the moment that repo
exists the bare `curl … | sh` / `irm … | iex` one-liner just works** with no
override.

## Files

| file | served at |
|---|---|
| `get.fabroq.com.sh` | `https://get.fabroq.com` (and `/`) |
| `install.ps1` | `https://get.fabroq.com/install.ps1` |
