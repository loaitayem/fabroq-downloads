# Fabroq installer for Windows — run-it-yourself gateway host.
#   irm https://get.fabroq.com/install.ps1 | iex
#
# Installs the thin `fabroq` CLI launcher (a small, open downloader — NO engine, no moat). You
# then sign in and `fabroq up`, which AUTHED-downloads your engine runtime from api.fabroq.com
# (your account only) and starts the gateway + engine locally.
#
# Why a thin launcher instead of cloning an engine repo (FABROQ-765): the Fabroq engine is the
# moat + the paid Engine Pro tier — NEVER published publicly (source OR runtime). The packaged
# runtime is delivered ONLY to a signed-in account over an authenticated endpoint, so the
# one-liner works without ever exposing the engine. Idempotent: safe to re-run.
$ErrorActionPreference = 'Stop'

$Prefix      = if ($env:FABROQ_PREFIX) { $env:FABROQ_PREFIX } else { Join-Path $HOME '.fabroq' }
$BinDir      = Join-Path $Prefix 'bin'
# The launcher this installer drops onto your PATH. Overridable for testing against a local copy
# (e.g. $env:FABROQ_LAUNCHER_URL='C:\path\to\fabroq.ps1' or a staging URL). Default = the PUBLIC raw
# source: the get.fabroq.com edge only maps / and /install.ps1, so fetch the launcher from raw directly.
$LauncherUrl = if ($env:FABROQ_LAUNCHER_URL) { $env:FABROQ_LAUNCHER_URL } else { 'https://raw.githubusercontent.com/loaitayem/fabroq-downloads/main/install/fabroq.ps1' }

function Say  ($m) { Write-Host $m }
function OK   ($m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; exit 1 }

Say ''
Say 'Fabroq — installing the run-it-yourself launcher (Windows)'
Say ''

# The engine runtime ships its OWN Python + Node (self-contained bundle), so there are NO system
# Python/Node/git prerequisites here, and we NEVER clone an engine repo.
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# ---- fetch + install the thin launcher ------------------------------------
$launcher = Join-Path $BinDir 'fabroq.ps1'
Say 'Installing the fabroq launcher...'
if (Test-Path $LauncherUrl) {
  Copy-Item -Force $LauncherUrl $launcher
} else {
  try { Invoke-WebRequest -Uri $LauncherUrl -OutFile $launcher -UseBasicParsing }
  catch { Die "could not download the launcher from $LauncherUrl" }
}
OK "fabroq launcher -> $launcher"

# A tiny .cmd shim so `fabroq ...` works from cmd.exe / PowerShell / the Run box.
$shim = Join-Path $BinDir 'fabroq.cmd'
Set-Content -Path $shim -Encoding ASCII -Value @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fabroq.ps1" %*
"@
OK "fabroq command -> $shim"

# ---- PATH (user scope) ----------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $BinDir), 'User')
  Warn 'Added Fabroq to your PATH. Open a new terminal for `fabroq` to be found.'
}

Say ''
OK 'Fabroq launcher is installed.'
Say ''
Say 'Next:'
Say '  1. fabroq login      # sign in to your Fabroq account'
Say '  2. fabroq up         # downloads your engine runtime (once) + starts it'
Say ''
Say 'Your engine runs on YOUR machine. The runtime is downloaded only to your signed-in'
Say 'account over an authenticated channel — your AI, your off switch.'
Say ''
