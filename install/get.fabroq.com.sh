#!/bin/sh
# Fabroq installer — run-it-yourself gateway host.
#   curl -fsSL https://get.fabroq.com | sh
#
# Installs the thin `fabroq` CLI launcher (a small, open downloader — NO engine, no moat).
# You then sign in and `fabroq up`, which AUTHED-downloads your engine runtime from
# api.fabroq.com (your account only) and starts the gateway + engine locally.
#
# Why a thin launcher instead of cloning an engine repo (FABROQ-765): the Fabroq engine is the
# moat + the paid Engine Pro tier — it is NEVER published publicly (source OR runtime). The
# packaged runtime is delivered ONLY to a signed-in account over an authenticated endpoint, so
# `curl|sh` works without ever exposing the engine. Safe to re-run. POSIX sh; macOS + Linux.
# Windows: irm https://get.fabroq.com/install.ps1 | iex
set -eu

FABROQ_PREFIX="${FABROQ_PREFIX:-$HOME/.fabroq}"
BIN_DIR="$FABROQ_PREFIX/bin"
# The launcher this installer drops onto your PATH. Overridable for testing against a local copy
# (FABROQ_LAUNCHER_URL=file:///path/to/fabroq.sh or a staging URL). Default = the PUBLIC raw source:
# the get.fabroq.com edge only maps / and /install.ps1, so the launcher is fetched from raw directly.
LAUNCHER_URL="${FABROQ_LAUNCHER_URL:-https://raw.githubusercontent.com/loaitayem/fabroq-downloads/main/install/fabroq.sh}"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

say ""
say "Fabroq — installing the run-it-yourself launcher"
say ""

# ---- platform -------------------------------------------------------------
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) PLATFORM="macOS" ;;
  Linux)  PLATFORM="Linux" ;;
  *)      die "Unsupported OS. On Windows run: irm https://get.fabroq.com/install.ps1 | iex" ;;
esac
ok "platform: $PLATFORM"

# ---- prerequisites --------------------------------------------------------
# The engine runtime ships its OWN Python + Node (self-contained bundle), so the launcher needs
# only curl (to download) + unzip (to extract). No system Python/Node/git required, and we NEVER
# clone an engine repo.
have curl  || die "curl is required. Install it and re-run."
ok "curl: $(curl --version 2>/dev/null | head -n1 | cut -d' ' -f1-2)"
have unzip || warn "unzip not found — needed by 'fabroq up' to extract the runtime. Install it (macOS has it; Linux: apt/dnf install unzip)."

# ---- fetch + install the thin launcher ------------------------------------
mkdir -p "$BIN_DIR"
launcher="$BIN_DIR/fabroq"
say "Installing the fabroq launcher…"
case "$LAUNCHER_URL" in
  file://*) cp "${LAUNCHER_URL#file://}" "$launcher" ;;
  /*)       cp "$LAUNCHER_URL" "$launcher" ;;
  *)        curl -fsSL "$LAUNCHER_URL" -o "$launcher" || die "could not download the launcher from $LAUNCHER_URL" ;;
esac
chmod +x "$launcher"
ok "fabroq launcher -> $launcher"

# ---- PATH hint ------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    warn "add Fabroq to your PATH:"
    say  "    echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.profile && . ~/.profile"
    ;;
esac

say ""
say "Done. Next:"
say "  1. fabroq login      # sign in to your Fabroq account"
say "  2. fabroq up         # downloads your engine runtime (once) + starts it"
say ""
say "Your engine runs on YOUR machine. The runtime is downloaded only to your signed-in"
say "account over an authenticated channel — your AI, your off switch."
