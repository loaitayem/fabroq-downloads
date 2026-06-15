#!/bin/sh
# Fabroq installer — run-it-yourself gateway host.
#   curl -fsSL https://get.fabroq.com | sh
#
# Installs:
#   * the Fabroq engine (Python) + the `fabroq` CLI (the gateway host),
#   * the OpenClaw gateway component (the device-mesh hub the CLI runs),
# then prints the one command to start it.
#
# Safe to re-run (idempotent). POSIX sh; works on macOS and Linux.
# Windows users: use the PowerShell one-liner at https://get.fabroq.com/install.ps1
set -eu

# ---- config (override via env) -------------------------------------------
# FABROQ_REPO = the fetchable source for the Fabroq engine + `fabroq` CLI.
# NOTE (owner decision pending): how much of the engine is public for
# run-it-yourself is an OWNER call. Until that's resolved there is NO public
# engine source, so FABROQ_REPO has no working default — set it to any reachable
# git URL or tarball to install today:
#   FABROQ_REPO=https://github.com/you/your-engine.git curl -fsSL https://get.fabroq.com | sh
# When the owner publishes the engine, this default will point at it and the
# bare one-liner will work with no override. (See the clean-fail message below.)
FABROQ_REPO="${FABROQ_REPO:-}"
# The repo the owner will publish the engine to. Used ONLY for messaging until
# it exists; the installer probes it and, if reachable, uses it automatically.
FABROQ_DEFAULT_REPO="https://github.com/loaitayem/fabroq-engine.git"
FABROQ_RELEASES_URL="https://github.com/loaitayem/fabroq-downloads/tree/main/install#engine-source"
FABROQ_REF="${FABROQ_REF:-main}"
FABROQ_PREFIX="${FABROQ_PREFIX:-$HOME/.fabroq}"
# Gateway component (the device-mesh hub). Pinned to the same version the shipped
# Fabroq desktop bundles (protocol v4). Override with OPENCLAW_PKG=openclaw@<ver>.
OPENCLAW_PKG="${OPENCLAW_PKG:-openclaw@2026.6.6}" # npm package for the gateway (pinned, v4)
MIN_NODE_MAJOR=22
MIN_PY_MINOR=10                                   # need python 3.10+

INSTALL_DIR="$FABROQ_PREFIX/app"
BIN_DIR="$FABROQ_PREFIX/bin"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

say ""
say "Fabroq — installing your own gateway host"
say ""

# ---- detect OS/arch ------------------------------------------------------
OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)      die "Unsupported OS '$OS'. On Windows run: irm https://get.fabroq.com/install.ps1 | iex" ;;
esac
ok "platform: $PLATFORM"

# ---- prerequisites: python3, node, git -----------------------------------
PYTHON=""
for cand in python3 python; do
  if have "$cand"; then
    v="$("$cand" -c 'import sys;print(sys.version_info[0]*100+sys.version_info[1])' 2>/dev/null || echo 0)"
    if [ "$v" -ge $((300 + MIN_PY_MINOR)) ]; then PYTHON="$cand"; break; fi
  fi
done
[ -n "$PYTHON" ] || die "Python 3.$MIN_PY_MINOR+ is required. Install it (macOS: brew install python; Linux: apt/dnf install python3) and re-run."
ok "python: $("$PYTHON" --version 2>&1)"

if ! have node; then
  warn "Node.js not found — the gateway needs Node >= $MIN_NODE_MAJOR."
  warn "Install it: https://nodejs.org  (macOS: brew install node ; Linux: use nodesource/nvm), then re-run."
  die "Node.js missing"
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
[ "$NODE_MAJOR" -ge "$MIN_NODE_MAJOR" ] || die "Node >= $MIN_NODE_MAJOR required (found $(node --version)). Upgrade and re-run."
ok "node: $(node --version)"

have git || die "git is required to fetch Fabroq. Install git and re-run."
ok "git: $(git --version 2>&1 | head -n1)"

# npm/npx for the gateway component
have npm || die "npm is required (ships with Node). Re-install Node and re-run."

# ---- resolve the engine source (NEVER a confusing raw 404) ---------------
# git-reachable? (works for git URLs; tarball URLs are handled separately below)
src_reachable() {
  case "$1" in
    *.tar.gz|*.tgz|*.zip) curl -fsIL "$1" >/dev/null 2>&1 ;;
    *)                    git ls-remote "$1" >/dev/null 2>&1 ;;
  esac
}

# Tell the user exactly why we can't proceed + the precise owner action, instead
# of letting `git clone` spit a raw "Repository not found" 404.
engine_not_public() {
  say ""
  die "$(printf '%s' "\
Fabroq engine source is not public yet.

The run-it-yourself engine package has not been published, so there is no
default source to install from. This is a pending OWNER decision, not a bug in
this installer.

You have two options:

  1. Install from your own reachable source NOW (override the default):
       FABROQ_REPO=https://github.com/you/your-engine.git \\
         curl -fsSL https://get.fabroq.com | sh
     (FABROQ_REPO also accepts a .tar.gz / .tgz / .zip tarball URL.)

  2. Wait for the public release: $FABROQ_RELEASES_URL

OWNER ACTION (one-time): publish the engine source, then this installer
auto-works with no override. Either —
  - create public repo $FABROQ_DEFAULT_REPO
    (trimmed CLI + gateway-host + a model backend; no planner/verifier moat), or
  - publish a release tarball and set FABROQ_REPO to its URL by default.
The installer probes $FABROQ_DEFAULT_REPO on every run, so once it exists the
bare one-liner just works.")"
}

if [ -n "$FABROQ_REPO" ]; then
  # User supplied an explicit source — verify it before we try to clone.
  say "Checking engine source…"
  src_reachable "$FABROQ_REPO" \
    || die "FABROQ_REPO is not reachable: $FABROQ_REPO
Check the URL (and that it is public or you have access), then re-run."
  ok "engine source: $FABROQ_REPO"
elif src_reachable "$FABROQ_DEFAULT_REPO"; then
  # No override, but the owner has since published the default — use it.
  FABROQ_REPO="$FABROQ_DEFAULT_REPO"
  ok "engine source: $FABROQ_REPO"
else
  # No override AND no public source yet -> clean, actionable failure.
  engine_not_public
fi

# ---- fetch / update the Fabroq engine + CLI ------------------------------
mkdir -p "$FABROQ_PREFIX" "$BIN_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
  say "Updating Fabroq…"
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$FABROQ_REF" >/dev/null 2>&1 || true
  git -C "$INSTALL_DIR" checkout -q "$FABROQ_REF" 2>/dev/null || true
  git -C "$INSTALL_DIR" pull -q --ff-only origin "$FABROQ_REF" >/dev/null 2>&1 || true
else
  say "Downloading Fabroq…"
  git clone --depth 1 --branch "$FABROQ_REF" "$FABROQ_REPO" "$INSTALL_DIR" >/dev/null 2>&1 \
    || git clone --depth 1 "$FABROQ_REPO" "$INSTALL_DIR" >/dev/null 2>&1 \
    || die "could not clone $FABROQ_REPO (ref '$FABROQ_REF'). The source was reachable but the clone failed — check the ref/branch and access, then re-run."
fi
ok "Fabroq source at $INSTALL_DIR"

# ---- isolated venv + install (engine + host extra) -----------------------
VENV="$FABROQ_PREFIX/venv"
if [ ! -x "$VENV/bin/python" ]; then
  "$PYTHON" -m venv "$VENV" || die "could not create venv at $VENV"
fi
VPY="$VENV/bin/python"
say "Installing the Fabroq engine + CLI (isolated venv)…"
"$VPY" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
# Install the engine package with the gateway-host extra (fastapi/uvicorn/httpx).
"$VPY" -m pip install --quiet "$INSTALL_DIR"'[host]' >/dev/null 2>&1 \
  || "$VPY" -m pip install --quiet -e "$INSTALL_DIR"'[host]' >/dev/null 2>&1 \
  || die "pip install failed"
ok "engine + CLI installed"

# ---- install the OpenClaw gateway component ------------------------------
# Prefer a global npm install so `openclaw` is on PATH; fall back to a local
# install under the Fabroq prefix that the CLI can locate.
say "Installing the gateway component…"
if npm install -g "$OPENCLAW_PKG" >/dev/null 2>&1; then
  ok "gateway component installed globally (openclaw)"
else
  warn "global npm install needs sudo; installing the gateway under $FABROQ_PREFIX instead"
  GW_DIR="$FABROQ_PREFIX/gateway-pkg"
  mkdir -p "$GW_DIR"
  ( cd "$GW_DIR" && npm init -y >/dev/null 2>&1 && npm install "$OPENCLAW_PKG" >/dev/null 2>&1 ) \
    || die "could not install the gateway component ($OPENCLAW_PKG)"
  # Point the CLI at the vendored gateway entrypoint.
  GW_ENTRY="$GW_DIR/node_modules/$OPENCLAW_PKG/openclaw.mjs"
  [ -f "$GW_ENTRY" ] || die "gateway entry not found at $GW_ENTRY"
  mkdir -p "$FABROQ_PREFIX/openclaw"
  ln -sf "$GW_ENTRY" "$FABROQ_PREFIX/openclaw/openclaw.mjs"
  ok "gateway component installed under $FABROQ_PREFIX"
fi

# ---- expose the `fabroq` command -----------------------------------------
# The venv installs the `fabroq` console script; symlink it onto a stable bin dir.
if [ -x "$VENV/bin/fabroq" ]; then
  ln -sf "$VENV/bin/fabroq" "$BIN_DIR/fabroq"
  ln -sf "$VENV/bin/fabroqd" "$BIN_DIR/fabroqd" 2>/dev/null || true
  ok "fabroq command -> $BIN_DIR/fabroq"
fi

# PATH hint
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    warn "add Fabroq to your PATH:"
    say  "    echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.profile && . ~/.profile"
    ;;
esac

say ""
ok "Fabroq is installed."
say ""
say "Start your gateway host:"
say "    $BIN_DIR/fabroq up"
say ""
say "Then on your phone (same Wi-Fi): open Fabroq → Connect → Nearby gateway,"
say "and run \`fabroq pair\` here to approve it."
say ""
