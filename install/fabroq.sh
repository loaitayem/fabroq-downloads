#!/bin/sh
# fabroq — the thin run-it-yourself launcher (PUBLIC shim; FABROQ-765).
#
# This script is the ENTIRE public surface of the CLI. It contains NO engine: no planner,
# no verifier, no checker, no prompts, no secrets. It only knows how to:
#   1. `fabroq login`  — store your Fabroq account token (the key to the authed download),
#   2. ensure the engine RUNTIME is present — AUTHED-download host-runtime-<plat>-<arch>.zip
#      from the api (api.fabroq.com/engine/runtime) using your token, verify its SHA-256,
#      and extract it to a machine-local dir (downloaded ONCE; cached after),
#   3. delegate every other command (`up`, `down`, `status`, `chat`, `pair`, …) to the REAL
#      `fabroqctl` that lives INSIDE the downloaded runtime.
#
# The engine (the moat + the paid Engine Pro tier) is NEVER public: it is fetched only for a
# signed-in (and, when the server requires it, entitled) account. An anonymous download is
# rejected by the api with 401. POSIX sh; works on macOS and Linux.
set -eu

FABROQ_API="${FABROQ_API:-https://api.fabroq.com}"
FABROQ_PREFIX="${FABROQ_PREFIX:-$HOME/.fabroq}"
RUNTIME_DIR="${FABROQ_HOST_RUNTIME_DIR:-$FABROQ_PREFIX/engine-runtime}"
TOKEN_FILE="${FABROQ_TOKEN_FILE:-$FABROQ_PREFIX/token}"
UA="fabroq-cli/1.0"   # a clean, identifiable UA (NOT curl/wget — the api bot filter blocks those)

say()  { printf '%s\n' "$*"; }
err()  { printf '%s\n' "$*" >&2; }
die()  { err "fabroq: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- platform / arch (the node process.platform/arch the artifact is named for) ----------
detect_platform() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) echo macos ;; Linux) echo linux ;; *) echo unsupported ;;
  esac
}
# The host-runtime artifact uses node's process.platform: darwin|linux (win32 is the .ps1 path).
artifact_platform() {
  case "$(uname -s 2>/dev/null)" in Darwin) echo darwin ;; *) echo linux ;; esac
}
artifact_arch() {
  case "$(uname -m 2>/dev/null)" in
    arm64|aarch64) echo arm64 ;; x86_64|amd64) echo x64 ;; *) echo x64 ;;
  esac
}

# ---- token ---------------------------------------------------------------------------------
read_token() {
  if [ -n "${FABROQ_TOKEN:-}" ]; then printf '%s' "$FABROQ_TOKEN"; return 0; fi
  if [ -f "$TOKEN_FILE" ]; then cat "$TOKEN_FILE"; return 0; fi
  return 1
}

cmd_login() {
  # `fabroq login` — store the account token used for the authed runtime download.
  #   • `fabroq login --token <jwt>` or FABROQ_TOKEN=<jwt> fabroq login  → non-interactive,
  #   • otherwise prompt for a token pasted from the web sign-in (Settings → CLI token).
  # (A browser device-code flow is the planned UX enhancement; the token path works today.)
  tok="${FABROQ_TOKEN:-}"
  if [ "${1:-}" = "--token" ] && [ -n "${2:-}" ]; then tok="$2"; fi
  if [ -z "$tok" ]; then
    say "Sign in at ${FABROQ_API%/api}/account (or fabroq.com) and copy your CLI token."
    printf 'Paste your Fabroq token: '
    IFS= read -r tok || true
  fi
  [ -n "$tok" ] || die "no token provided. Run: fabroq login --token <your-token>"
  mkdir -p "$FABROQ_PREFIX"
  umask 077; printf '%s' "$tok" > "$TOKEN_FILE"
  # Verify the token is accepted by the api before claiming success.
  code="$(curl -s -A "$UA" -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" "$FABROQ_API/me" || echo 000)"
  case "$code" in
    200) say "Signed in. Your token is saved to $TOKEN_FILE." ;;
    401|403) rm -f "$TOKEN_FILE"; die "the api rejected that token (HTTP $code). Get a fresh token and retry." ;;
    *) say "Saved token to $TOKEN_FILE (could not reach $FABROQ_API/me to verify; HTTP $code)." ;;
  esac
}

# ---- ensure the engine runtime (AUTHED download → verify → extract) ------------------------
ensure_runtime() {
  if [ -f "$RUNTIME_DIR/manifest.json" ]; then return 0; fi   # cached; downloaded once
  tok="$(read_token)" || die "not signed in. Run: fabroq login"
  plat="$(artifact_platform)"; arch="$(artifact_arch)"
  url="${FABROQ_HOST_RUNTIME_URL:-$FABROQ_API/engine/runtime?platform=$plat&arch=$arch}"
  shaurl="${FABROQ_HOST_RUNTIME_SHA_URL:-$FABROQ_API/engine/runtime/sha256?platform=$plat&arch=$arch}"
  have curl || die "curl is required."
  have unzip || die "unzip is required to install the engine runtime."

  mkdir -p "$FABROQ_PREFIX"
  zip="$FABROQ_PREFIX/host-runtime.download.$$.zip"
  tmp="$FABROQ_PREFIX/host-runtime.tmp.$$"
  rm -rf "$zip" "$tmp"
  trap 'rm -rf "$zip" "$tmp"' EXIT

  say "Downloading the Fabroq engine runtime (signed in)…"
  code="$(curl -s -A "$UA" -L -w '%{http_code}' -H "Authorization: Bearer $tok" -o "$zip" "$url" || echo 000)"
  case "$code" in
    200) : ;;
    401) die "the runtime download was refused — you're not signed in (HTTP 401). Run: fabroq login" ;;
    403) die "this account isn't entitled to the engine runtime yet (HTTP 403). Upgrade to Engine Pro, or ask to be let into the beta." ;;
    404) die "no engine runtime is published for $plat-$arch yet." ;;
    *)   die "runtime download failed (HTTP $code)." ;;
  esac

  # Verify the SHA-256 (the api serves the digest to the same signed-in account).
  expected="$(curl -s -A "$UA" -H "Authorization: Bearer $tok" "$shaurl" 2>/dev/null | tr -dc 'a-fA-F0-9' | cut -c1-64)"
  if [ -n "$expected" ]; then
    actual="$( { sha256sum "$zip" 2>/dev/null || shasum -a 256 "$zip"; } | cut -d' ' -f1 )"
    [ "$actual" = "$expected" ] || die "runtime checksum mismatch (expected ${expected%${expected#????????}}…, got ${actual%${actual#????????}}…)."
    say "Checksum OK."
  fi

  say "Installing the engine runtime…"
  mkdir -p "$tmp"; unzip -q -o "$zip" -d "$tmp"
  root="$tmp"; [ -f "$root/manifest.json" ] || root="$(dirname "$(find "$tmp" -maxdepth 2 -name manifest.json | head -n1)")"
  [ -f "$root/manifest.json" ] || die "runtime archive is missing manifest.json."
  rm -rf "$RUNTIME_DIR"; mkdir -p "$(dirname "$RUNTIME_DIR")"; mv "$root" "$RUNTIME_DIR"
  [ -f "$RUNTIME_DIR/manifest.json" ] || die "runtime failed validation after extract."
  rm -rf "$zip" "$tmp"; trap - EXIT
  say "Engine runtime ready at $RUNTIME_DIR"
}

# ---- resolve the bundled interpreter + delegate to fabroqctl -------------------------------
bundled_python() {
  for p in "$RUNTIME_DIR/python/bin/python3" "$RUNTIME_DIR/python/bin/python" "$RUNTIME_DIR/python/python.exe"; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

run_fabroqctl() {
  py="$(bundled_python)" || die "the bundled Python was not found in $RUNTIME_DIR."
  ocdir="$RUNTIME_DIR/openclaw/node_modules/openclaw"
  nodedir="$RUNTIME_DIR/node"
  export PYTHONPATH="$RUNTIME_DIR/engine${PYTHONPATH:+:$PYTHONPATH}"
  export PYTHONIOENCODING="utf-8"
  [ -d "$ocdir" ] && export FABROQ_OPENCLAW_DIR="$ocdir"
  [ -d "$nodedir" ] && export PATH="$nodedir:$PATH"
  exec "$py" -m fabroqctl "$@"
}

case "${1:-}" in
  login)  shift; cmd_login "$@" ;;
  ""|-h|--help|help)
    say "fabroq — run your own AI."
    say ""
    say "  fabroq login            Sign in (stores your account token)."
    say "  fabroq up               Download (once) + start the gateway + engine."
    say "  fabroq down             Stop the local gateway + engine."
    say "  fabroq status           Show gateway/engine health."
    say "  fabroq <cmd> …          Any other command runs in the downloaded engine runtime."
    ;;
  *) ensure_runtime; run_fabroqctl "$@" ;;
esac
