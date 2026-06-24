# fabroq — the thin run-it-yourself launcher for Windows (PUBLIC shim; FABROQ-765).
#
# This is the ENTIRE public surface of the CLI on Windows. It contains NO engine: no planner,
# no verifier, no checker, no prompts, no secrets. It only: (1) `fabroq login` stores your
# account token, (2) ensures the engine RUNTIME is present by AUTHED-downloading
# host-runtime-win32-<arch>.zip from the api using your token (verify SHA-256, extract once,
# cache), and (3) delegates every other command to the REAL `fabroqctl` inside that runtime.
# The engine (moat + paid Engine Pro tier) is never public — an anonymous download gets 401.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Args)
$ErrorActionPreference = 'Stop'

$Api        = if ($env:FABROQ_API) { $env:FABROQ_API } else { 'https://api.fabroq.com' }
$Prefix     = if ($env:FABROQ_PREFIX) { $env:FABROQ_PREFIX } else { Join-Path $HOME '.fabroq' }
$RuntimeDir = if ($env:FABROQ_HOST_RUNTIME_DIR) { $env:FABROQ_HOST_RUNTIME_DIR }
              else { Join-Path (Join-Path $env:LOCALAPPDATA 'Fabroq') 'engine-runtime' }  # shared with the desktop app
$TokenFile  = if ($env:FABROQ_TOKEN_FILE) { $env:FABROQ_TOKEN_FILE } else { Join-Path $Prefix 'token' }

function Die($m) { Write-Host "fabroq: $m" -ForegroundColor Red; exit 1 }

function Get-Arch {
  switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'arm64' } default { 'x64' } }
}
function Read-Token {
  if ($env:FABROQ_TOKEN) { return $env:FABROQ_TOKEN }
  if (Test-Path $TokenFile) { return (Get-Content -Raw $TokenFile).Trim() }
  return $null
}

function Invoke-Login($rest) {
  $tok = $env:FABROQ_TOKEN
  for ($i = 0; $i -lt $rest.Count; $i++) { if ($rest[$i] -eq '--token' -and $i + 1 -lt $rest.Count) { $tok = $rest[$i + 1] } }
  if (-not $tok) {
    Write-Host "Sign in at $($Api -replace '/api$','')/account (or fabroq.com) and copy your CLI token."
    $tok = Read-Host 'Paste your Fabroq token'
  }
  if (-not $tok) { Die 'no token provided. Run: fabroq login --token <your-token>' }
  New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
  Set-Content -Path $TokenFile -Value $tok -NoNewline
  # Verify the token before claiming success. Works on Windows PowerShell 5.1 (Invoke-WebRequest
  # throws on non-2xx) AND PowerShell 7 — we read the status from the thrown response either way.
  $code = 0
  try {
    $r = Invoke-WebRequest -Uri "$Api/me" -Headers @{ Authorization = "Bearer $tok" } -UserAgent 'fabroq-cli/1.0' -UseBasicParsing
    $code = [int]$r.StatusCode
  } catch {
    if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 } }
  }
  if ($code -eq 200) { Write-Host "Signed in. Token saved to $TokenFile." }
  elseif ($code -eq 401 -or $code -eq 403) { Remove-Item -Force $TokenFile; Die "the api rejected that token (HTTP $code). Get a fresh token and retry." }
  else { Write-Host "Saved token to $TokenFile (could not verify; HTTP $code)." }
}

function Ensure-Runtime {
  if (Test-Path (Join-Path $RuntimeDir 'manifest.json')) { return }   # cached; downloaded once
  $tok = Read-Token; if (-not $tok) { Die 'not signed in. Run: fabroq login' }
  $arch = Get-Arch
  $url    = if ($env:FABROQ_HOST_RUNTIME_URL) { $env:FABROQ_HOST_RUNTIME_URL } else { "$Api/engine/runtime?platform=win32&arch=$arch" }
  $shaUrl = if ($env:FABROQ_HOST_RUNTIME_SHA_URL) { $env:FABROQ_HOST_RUNTIME_SHA_URL } else { "$Api/engine/runtime/sha256?platform=win32&arch=$arch" }
  New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
  $zip = Join-Path $Prefix "host-runtime.download.$PID.zip"
  $tmp = Join-Path $Prefix "host-runtime.tmp.$PID"
  Remove-Item -Recurse -Force $zip, $tmp -ErrorAction SilentlyContinue

  Write-Host 'Downloading the Fabroq engine runtime (signed in)...'
  $code = 0
  try {
    Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $tok" } -UserAgent 'fabroq-cli/1.0' -OutFile $zip -UseBasicParsing
    $code = 200
  } catch {
    if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 } }
  }
  switch ($code) {
    200 { }
    401 { Die 'the runtime download was refused — you are not signed in (HTTP 401). Run: fabroq login' }
    403 { Die "this account isn't entitled to the engine runtime yet (HTTP 403). Upgrade to Engine Pro, or ask to be let into the beta." }
    404 { Die "no engine runtime is published for win32-$arch yet." }
    default { Die "runtime download failed (HTTP $code)." }
  }
  try {
    $expected = ((Invoke-WebRequest -Uri $shaUrl -Headers @{ Authorization = "Bearer $tok" } -UserAgent 'fabroq-cli/1.0' -UseBasicParsing).Content -replace '[^a-fA-F0-9]','').Substring(0,64).ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($expected -and $actual -ne $expected) { Die "runtime checksum mismatch (expected $($expected.Substring(0,8))..., got $($actual.Substring(0,8))...)." }
    if ($expected) { Write-Host 'Checksum OK.' }
  } catch { }

  Write-Host 'Installing the engine runtime...'
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
  $root = $tmp
  if (-not (Test-Path (Join-Path $root 'manifest.json'))) {
    $m = Get-ChildItem -Path $tmp -Recurse -Depth 2 -Filter manifest.json | Select-Object -First 1
    if ($m) { $root = $m.Directory.FullName }
  }
  if (-not (Test-Path (Join-Path $root 'manifest.json'))) { Die 'runtime archive is missing manifest.json.' }
  Remove-Item -Recurse -Force $RuntimeDir -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path (Split-Path $RuntimeDir) | Out-Null
  Move-Item $root $RuntimeDir
  Remove-Item -Recurse -Force $zip, $tmp -ErrorAction SilentlyContinue
  if (-not (Test-Path (Join-Path $RuntimeDir 'manifest.json'))) { Die 'runtime failed validation after extract.' }
  Write-Host "Engine runtime ready at $RuntimeDir"
}

function Invoke-Fabroqctl($rest) {
  $py = Join-Path $RuntimeDir 'python\python.exe'
  if (-not (Test-Path $py)) { Die "the bundled Python was not found in $RuntimeDir." }
  $env:PYTHONPATH = (Join-Path $RuntimeDir 'engine') + $(if ($env:PYTHONPATH) { ";$env:PYTHONPATH" } else { '' })
  $env:PYTHONIOENCODING = 'utf-8'
  $ocdir = Join-Path $RuntimeDir 'openclaw\node_modules\openclaw'
  if (Test-Path $ocdir) { $env:FABROQ_OPENCLAW_DIR = $ocdir }
  $nodedir = Join-Path $RuntimeDir 'node'
  if (Test-Path $nodedir) { $env:PATH = "$nodedir;$env:PATH" }
  & $py -m fabroqctl @rest
  exit $LASTEXITCODE
}

$cmd = if ($Args.Count -gt 0) { $Args[0] } else { '' }
$rest = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }
switch ($cmd) {
  'login' { Invoke-Login $rest }
  { $_ -in '', '-h', '--help', 'help' } {
    Write-Host "fabroq - run your own AI."
    Write-Host ""
    Write-Host "  fabroq login      Sign in (stores your account token)."
    Write-Host "  fabroq up         Download (once) + start the gateway + engine."
    Write-Host "  fabroq down       Stop the local gateway + engine."
    Write-Host "  fabroq status     Show gateway/engine health."
    Write-Host "  fabroq <cmd> ...  Any other command runs in the downloaded engine runtime."
  }
  default { Ensure-Runtime; Invoke-Fabroqctl $Args }
}
