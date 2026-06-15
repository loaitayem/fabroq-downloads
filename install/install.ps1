# Fabroq installer for Windows — run-it-yourself gateway host.
#   irm https://get.fabroq.com/install.ps1 | iex
#
# Installs the Fabroq engine (Python) + the `fabroq` CLI (the gateway host) and the
# OpenClaw gateway component (the device-mesh hub), then prints how to start it.
# Idempotent: safe to re-run. Requires Python 3.10+ and Node 22+ (it tells you how
# to get them if missing).

$ErrorActionPreference = 'Stop'

# ---- config (override via env) -------------------------------------------
# FABROQ_REPO = the fetchable source for the Fabroq engine + `fabroq` CLI.
# NOTE (owner decision pending): how much of the engine is public for
# run-it-yourself is an OWNER call. Until that's resolved there is NO public
# engine source, so FABROQ_REPO has no working default — set it to any reachable
# git URL or tarball to install today:
#   $env:FABROQ_REPO='https://github.com/you/your-engine.git'; irm https://get.fabroq.com/install.ps1 | iex
# When the owner publishes the engine, the default below will resolve and the
# bare one-liner works with no override.
$Repo    = if ($env:FABROQ_REPO)   { $env:FABROQ_REPO }   else { '' }
# The repo the owner will publish the engine to. Probed each run; used auto-
# matically once it exists, and named in the clean-fail message until then.
$DefaultRepo  = 'https://github.com/loaitayem/fabroq-engine.git'
$ReleasesUrl  = 'https://github.com/loaitayem/fabroq-downloads/tree/main/install#engine-source'
$Ref     = if ($env:FABROQ_REF)    { $env:FABROQ_REF }    else { 'main' }
$Prefix  = if ($env:FABROQ_PREFIX) { $env:FABROQ_PREFIX } else { Join-Path $HOME '.fabroq' }
# Gateway component pinned to the version the shipped Fabroq desktop bundles (v4).
$OcPkg   = if ($env:OPENCLAW_PKG)  { $env:OPENCLAW_PKG }  else { 'openclaw@2026.6.6' }
$MinNode = 22
$MinPy   = 10  # 3.10+

$AppDir = Join-Path $Prefix 'app'
$BinDir = Join-Path $Prefix 'bin'
$Venv   = Join-Path $Prefix 'venv'

function Say  ($m) { Write-Host $m }
function OK   ($m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; exit 1 }
function Have ($n) { [bool](Get-Command $n -ErrorAction SilentlyContinue) }

Say ''
Say 'Fabroq — installing your own gateway host (Windows)'
Say ''

# ---- prerequisites -------------------------------------------------------
$python = $null
foreach ($cand in @('python', 'py')) {
  if (Have $cand) {
    try {
      $v = & $cand -c 'import sys;print(sys.version_info[0]*100+sys.version_info[1])' 2>$null
      if ([int]$v -ge (300 + $MinPy)) { $python = $cand; break }
    } catch { }
  }
}
if (-not $python) { Die "Python 3.$MinPy+ is required. Install from https://www.python.org/downloads/ (check 'Add to PATH'), then re-run." }
OK ("python: " + (& $python --version 2>&1))

if (-not (Have node)) { Die "Node.js >= $MinNode is required for the gateway. Install from https://nodejs.org , then re-run." }
$nodeMajor = [int]((node -p 'parseInt(process.versions.node,10)') 2>$null)
if ($nodeMajor -lt $MinNode) { Die "Node >= $MinNode required (found $(node --version)). Upgrade and re-run." }
OK ("node: " + (node --version))

if (-not (Have git)) { Die "git is required to fetch Fabroq. Install from https://git-scm.com/download/win , then re-run." }
OK ("git: " + ((git --version) 2>&1))
if (-not (Have npm)) { Die "npm is required (ships with Node). Re-install Node and re-run." }

New-Item -ItemType Directory -Force -Path $Prefix, $BinDir | Out-Null

# ---- resolve the engine source (NEVER a confusing raw 404) ---------------
function Src-Reachable ($s) {
  if ($s -match '\.(tar\.gz|tgz|zip)$') {
    try { (Invoke-WebRequest -Uri $s -Method Head -UseBasicParsing -TimeoutSec 20).StatusCode -eq 200 } catch { $false }
  } else {
    git ls-remote $s 2>$null | Out-Null
    $LASTEXITCODE -eq 0
  }
}

function Engine-Not-Public {
  Say ''
  Die @"
Fabroq engine source is not public yet.

The run-it-yourself engine package has not been published, so there is no
default source to install from. This is a pending OWNER decision, not a bug in
this installer.

You have two options:

  1. Install from your own reachable source NOW (override the default):
       `$env:FABROQ_REPO='https://github.com/you/your-engine.git'
       irm https://get.fabroq.com/install.ps1 | iex
     (FABROQ_REPO also accepts a .tar.gz / .tgz / .zip tarball URL.)

  2. Wait for the public release: $ReleasesUrl

OWNER ACTION (one-time): publish the engine source, then this installer
auto-works with no override. Either create public repo
  $DefaultRepo
(trimmed CLI + gateway-host + a model backend; no planner/verifier moat), or
publish a release tarball and set FABROQ_REPO to its URL by default. The
installer probes $DefaultRepo on every run, so once it exists the bare
one-liner just works.
"@
}

if ($Repo) {
  Say 'Checking engine source...'
  if (-not (Src-Reachable $Repo)) {
    Die "FABROQ_REPO is not reachable: $Repo`nCheck the URL (and that it is public or you have access), then re-run."
  }
  OK "engine source: $Repo"
} elseif (Src-Reachable $DefaultRepo) {
  $Repo = $DefaultRepo
  OK "engine source: $Repo"
} else {
  Engine-Not-Public
}

# ---- fetch / update the Fabroq engine + CLI ------------------------------
if (Test-Path (Join-Path $AppDir '.git')) {
  Say 'Updating Fabroq...'
  git -C $AppDir fetch --depth 1 origin $Ref 2>$null | Out-Null
  git -C $AppDir checkout -q $Ref 2>$null
  git -C $AppDir pull -q --ff-only origin $Ref 2>$null | Out-Null
} else {
  Say 'Downloading Fabroq...'
  try { git clone --depth 1 --branch $Ref $Repo $AppDir 2>$null | Out-Null }
  catch { git clone --depth 1 $Repo $AppDir 2>$null | Out-Null }
  if (-not (Test-Path (Join-Path $AppDir '.git'))) { Die "could not clone $Repo (ref '$Ref'). The source was reachable but the clone failed -- check the ref/branch and access, then re-run." }
}
OK "Fabroq source at $AppDir"

# ---- isolated venv + install (engine + host extra) -----------------------
if (-not (Test-Path (Join-Path $Venv 'Scripts\python.exe'))) {
  & $python -m venv $Venv
  if (-not (Test-Path (Join-Path $Venv 'Scripts\python.exe'))) { Die "could not create venv at $Venv" }
}
$vpy = Join-Path $Venv 'Scripts\python.exe'
Say 'Installing the Fabroq engine + CLI (isolated venv)...'
& $vpy -m pip install --quiet --upgrade pip 2>$null
$installed = $false
try { & $vpy -m pip install --quiet ("$AppDir" + '[host]') 2>$null; $installed = $true } catch { }
if (-not $installed) { try { & $vpy -m pip install --quiet -e ("$AppDir" + '[host]') 2>$null; $installed = $true } catch { } }
if (-not $installed) { Die 'pip install failed' }
OK 'engine + CLI installed'

# ---- install the OpenClaw gateway component ------------------------------
Say 'Installing the gateway component...'
$globalOk = $false
try { npm install -g $OcPkg 2>$null | Out-Null; $globalOk = $true } catch { }
if ($globalOk -and (Have openclaw)) {
  OK 'gateway component installed globally (openclaw)'
} else {
  Warn "global npm install unavailable; installing the gateway under $Prefix instead"
  $gwDir = Join-Path $Prefix 'gateway-pkg'
  New-Item -ItemType Directory -Force -Path $gwDir | Out-Null
  Push-Location $gwDir
  try {
    npm init -y 2>$null | Out-Null
    npm install $OcPkg 2>$null | Out-Null
  } finally { Pop-Location }
  $gwEntry = Join-Path $gwDir ("node_modules\$OcPkg\openclaw.mjs")
  if (-not (Test-Path $gwEntry)) { Die "could not install the gateway component ($OcPkg)" }
  New-Item -ItemType Directory -Force -Path (Join-Path $Prefix 'openclaw') | Out-Null
  Copy-Item -Force $gwEntry (Join-Path $Prefix 'openclaw\openclaw.mjs')
  # The CLI auto-discovers a vendored gateway under $Prefix\openclaw.
  OK "gateway component installed under $Prefix"
}

# ---- expose the `fabroq` command -----------------------------------------
$fabroqExe = Join-Path $Venv 'Scripts\fabroq.exe'
if (Test-Path $fabroqExe) {
  Copy-Item -Force $fabroqExe (Join-Path $BinDir 'fabroq.exe')
  $fabroqd = Join-Path $Venv 'Scripts\fabroqd.exe'
  if (Test-Path $fabroqd) { Copy-Item -Force $fabroqd (Join-Path $BinDir 'fabroqd.exe') }
  OK "fabroq command -> $(Join-Path $BinDir 'fabroq.exe')"
}

# PATH (user scope) — add the bin dir if missing.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $BinDir), 'User')
  Warn 'Added Fabroq to your PATH. Open a new terminal for `fabroq` to be found.'
}

Say ''
OK 'Fabroq is installed.'
Say ''
Say 'Start your gateway host:'
Say "    $(Join-Path $BinDir 'fabroq.exe') up"
Say ''
Say 'Then on your phone (same Wi-Fi): open Fabroq -> Connect -> Nearby gateway,'
Say 'and run `fabroq pair` here to approve it.'
Say ''
