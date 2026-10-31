<#
.SYNOPSIS
  Rebuilds the video-editing studio on this machine: ReelMimic (pinned) + its Python venv + web app, the shared
  editing libraries (anime.js, GSAP, three.js, Remotion, Motion Canvas, playwright-core, ...), the pinned skill packs
  (Remotion + iart-ai motion skills), and the OpenFilm / youtube-clipper user skills. Safe to rerun: finished steps
  are detected and skipped.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -CheckOnly
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -InstallRoot D:\studio\reelmimic -InstallPrereqs
#>
[CmdletBinding()]
param(
  [string]$InstallRoot = (Join-Path $HOME 'reelmimic'),
  [string]$SkillsDir = (Join-Path $HOME '.claude\skills'),
  [string]$SecretsPath = (Join-Path $HOME '.reelmimic\secrets.json'),
  [string]$Python,
  [switch]$CheckOnly,
  [switch]$InstallPrereqs,
  [switch]$ForceSkills
)

# pip and npm write progress to stderr; under Windows PowerShell 5.1 'Stop' turns that into errors, so native
# failures are caught through exit codes (Invoke-Native) and cmdlets that must succeed pass -ErrorAction Stop.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # the 5.1 progress bar makes Invoke-WebRequest crawl
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Kit = Split-Path -Parent $PSScriptRoot
$Versions = Get-Content (Join-Path $Kit 'lock\versions.json') -Raw | ConvertFrom-Json
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$Utf8 = New-Object Text.UTF8Encoding $false   # no BOM: Node's JSON.parse rejects one
$script:Problems = @()
$WingetIds = @{ node = 'OpenJS.NodeJS.LTS'; python = 'Python.Python.3.12'; ffmpeg = 'Gyan.FFmpeg'; chrome = 'Google.Chrome' }

function Say($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "  ..   $msg" }
function Ok($msg) { Write-Host "  OK   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow; $script:Problems += "WARN $msg" }
function Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:Problems += "FAIL $msg" }

function Invoke-Native([string]$What, [scriptblock]$Cmd) {
  & $Cmd
  if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)" }
}

# ---------- prerequisites ----------

function Test-Python([string]$Exe, [string[]]$Pre) {
  if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) { return $null }
  $out = & $Exe @Pre -c "import sys; print(sys.executable if sys.version_info >= (3, 10) else '')" 2>$null
  if ($LASTEXITCODE -eq 0 -and $out) { return ([string]($out | Select-Object -Last 1)).Trim() }
  return $null
}

function Find-Python {
  if ($Python) { return (Test-Python $Python @()) }
  foreach ($c in @(@{ e = 'python'; a = @() }, @{ e = 'py'; a = @('-3') }, @{ e = 'python3'; a = @() })) {
    $p = Test-Python $c.e $c.a
    if ($p) { return $p }
  }
  return $null
}

function Get-NodeVersion {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }
  $v = & node -p "process.versions.node" 2>$null
  if ($LASTEXITCODE -eq 0 -and $v) { return [version]([string]$v).Trim() }
  return $null
}

function Find-Chrome {
  foreach ($p in @($env:CHROME_PATH, "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

function Test-Prereqs {
  Say 'Prerequisites'
  $missing = @()
  $nv = Get-NodeVersion
  if ($nv -and $nv -ge [version]'22.18.0') { Ok "Node.js $nv" }
  else { if ($nv) { Fail "Node.js $nv is older than 22.18" } else { Fail 'Node.js not found' }; $missing += 'node' }

  $script:Py = Find-Python
  if ($script:Py) { Ok "Python $(& $script:Py -c 'import platform; print(platform.python_version())') at $script:Py" }
  else { Fail 'Python 3.10+ not found (the Microsoft Store stub does not count; -Python <path> to point at one)'; $missing += 'python' }

  if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    $filters = & ffmpeg -hide_banner -filters 2>$null
    if (@($filters -match '\ssubtitles\s').Count) { Ok 'FFmpeg (with subtitles filter)' }
    else { Warn 'FFmpeg has no subtitles filter (libass): youtube-clipper cannot burn subtitles' }
  } else { Fail 'FFmpeg not found'; $missing += 'ffmpeg' }

  $chrome = Find-Chrome
  if ($chrome) { Ok "Chrome at $chrome" } else { Fail 'Google Chrome not found'; $missing += 'chrome' }

  if (Get-Command claude -ErrorAction SilentlyContinue) { Ok 'Claude Code CLI' }
  else { Warn 'Claude Code CLI (claude) not on PATH: the skills work, but the ReelMimic web app needs it (npm i -g @anthropic-ai/claude-code)' }

  # ReelMimic holds paths ~130 chars deep and Windows caps paths at 260 by default
  if ($InstallRoot.Length -gt 60) { Fail "InstallRoot is too long ($($InstallRoot.Length) chars, max 60): $InstallRoot"; $missing += 'path' }
  else { Ok "InstallRoot $InstallRoot" }
  return , $missing
}

function Install-Prereqs($missing) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget is not available; install the missing tools by hand' }
  foreach ($m in $missing) {
    if (-not $WingetIds.ContainsKey($m)) { continue }
    Say "Installing $m ($($WingetIds[$m])) with winget"
    & winget install --id $WingetIds[$m] -e --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { Warn "winget could not install $m (exit code $LASTEXITCODE)" }
  }
  # pick up the new tools without opening a new terminal
  $env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------- install steps ----------

# Extracts a pinned commit and returns its top folder. Uses the kit's bundled archive (payload\archives, made by
# build-bundle.ps1) when it matches the pin, so setup needs no GitHub; otherwise downloads it. Names stay short for
# the 260-char limit.
function Get-PinnedZip([string]$Repo, [string]$Commit, [string]$Tag) {
  $out = Join-Path $script:Work $Tag
  $zip = Join-Path $Kit ('payload\archives\{0}@{1}.zip' -f ($Repo -replace '/', '__'), $Commit.Substring(0, 7))
  if (Test-Path $zip) { Info "using bundled $Repo@$($Commit.Substring(0, 7))" }
  else {
    $zip = Join-Path $script:Work "$Tag.zip"
    Info "downloading $Repo@$($Commit.Substring(0, 7))"
    Invoke-WebRequest -UseBasicParsing "https://codeload.github.com/$Repo/zip/$Commit" -OutFile $zip -ErrorAction Stop
  }
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $out)
  return (Get-ChildItem $out -Directory | Select-Object -First 1).FullName
}

function Install-ReelMimic {
  Say "ReelMimic $($Versions.reelmimic.commit.Substring(0, 7)) -> $InstallRoot"
  if (Test-Path (Join-Path $InstallRoot 'app\package.json')) { Ok 'already present, reusing it'; return }
  if ((Test-Path $InstallRoot) -and (Get-ChildItem $InstallRoot -Force | Select-Object -First 1)) {
    throw "$InstallRoot is not empty and is not a ReelMimic folder; choose another -InstallRoot"
  }
  $src = Get-PinnedZip $Versions.reelmimic.repo $Versions.reelmimic.commit 'rm'
  if (Test-Path $InstallRoot) { Remove-Item $InstallRoot -Force -ErrorAction Stop }
  Move-Item $src $InstallRoot -ErrorAction Stop
  Ok "$((Get-ChildItem -Recurse -File $InstallRoot).Count) files"
}

function Install-SkillPacks {
  Say 'Skill packs (Remotion + iart-ai motion skills) -> project skills'
  $dst = Join-Path $InstallRoot '.claude\skills'
  $i = 0
  foreach ($pack in $Versions.skillPacks) {
    $i++
    $todo = @($pack.skills | Where-Object { -not (Test-Path (Join-Path $dst $_)) })
    if (-not $todo.Count) { Ok "$($pack.repo): all $(@($pack.skills).Count) already present"; continue }
    $src = Get-PinnedZip $pack.repo $pack.commit "p$i"
    $shared = Join-Path $src 'scripts'
    foreach ($n in $todo) {
      $d = Join-Path $dst $n
      if ($pack.include) {
        # the repo root is the skill: copy only the listed parts, leaving CI, evals and changelogs behind
        New-Item -ItemType Directory -Force $d | Out-Null
        foreach ($item in $pack.include) { Copy-Item (Join-Path $src $item) $d -Recurse -ErrorAction Stop }
      } else {
        Copy-Item (Join-Path $src "skills\$n") $d -Recurse -ErrorAction Stop
      }
      # iart packs keep their verify helpers at the pack root, while each SKILL.md calls them as scripts/...
      if ($pack.sharedScripts -and (Test-Path $shared)) {
        $sd = Join-Path $d 'scripts'
        if (-not (Test-Path $sd)) { New-Item -ItemType Directory $sd | Out-Null }
        Get-ChildItem $shared -File | Where-Object { -not (Test-Path (Join-Path $sd $_.Name)) } | Copy-Item -Destination $sd -ErrorAction Stop
      }
    }
    Remove-Item (Join-Path $script:Work "p$i"), (Join-Path $script:Work "p$i.zip") -Recurse -Force -ErrorAction SilentlyContinue
    Ok "$($pack.repo): installed $($todo.Count)"
  }
}

function Install-Venv {
  Say 'Python venv (OpenCV, librosa, faster-whisper, yt-dlp, ...)'
  $script:VenvPy = Join-Path $InstallRoot '.venv\Scripts\python.exe'
  if (-not (Test-Path $script:VenvPy)) { Invoke-Native 'venv creation' { & $script:Py -m venv (Join-Path $InstallRoot '.venv') } }
  Invoke-Native 'pip upgrade' { & $script:VenvPy -m pip install --upgrade pip --quiet --disable-pip-version-check }
  & $script:VenvPy -m pip install --disable-pip-version-check -r (Join-Path $Kit 'lock\requirements.lock.txt')
  if ($LASTEXITCODE -ne 0) {
    Warn 'pinned Python packages did not install on this Python; used the unpinned list from ReelMimic instead'
    Invoke-Native 'pip install' { & $script:VenvPy -m pip install --disable-pip-version-check -r (Join-Path $InstallRoot 'requirements.txt') }
  }
  Ok "venv at $(Split-Path (Split-Path $script:VenvPy))"
}

function Install-WebApp {
  Say 'ReelMimic web app'
  $app = Join-Path $InstallRoot 'app'
  if ((Test-Path (Join-Path $app 'node_modules')) -and (Test-Path (Join-Path $app 'dist\index.html'))) { Ok 'already built'; return }
  Push-Location $app
  try {
    Invoke-Native 'npm ci (app)' { & npm.cmd ci --no-fund --no-audit }
    Invoke-Native 'web build' { & npm.cmd run build }
  } finally { Pop-Location }
  Ok 'built app\dist'
}

function Install-EditingLibs {
  Say 'Editing libraries (anime.js, GSAP, three.js, Remotion, Motion Canvas)'
  $pj = Join-Path $InstallRoot 'package.json'
  if ((Test-Path $pj) -and ((Get-Content $pj -Raw | ConvertFrom-Json).name -ne 'reelmimic-editing-libs')) {
    Warn "$pj belongs to something else; skipped the editing libraries"; return
  }
  # .npmrc carries legacy-peer-deps: npm 11 otherwise loops forever on @motion-canvas/vite-plugin's vite peer
  foreach ($f in 'package.json', 'package-lock.json', '.npmrc') {
    Copy-Item (Join-Path $Kit "lock\editing-libs\$f") (Join-Path $InstallRoot $f) -Force -ErrorAction Stop
  }
  Push-Location $InstallRoot
  try { Invoke-Native 'npm ci (editing libs)' { & npm.cmd ci --no-fund --no-audit } } finally { Pop-Location }
  Ok "node_modules at $InstallRoot"
}

function Write-Config {
  Say 'Config'
  $dir = Split-Path $SecretsPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  $obj = New-Object PSObject
  if (Test-Path $SecretsPath) {
    # never rewrite a file we cannot parse: it may hold the user's API keys
    try { $obj = Get-Content $SecretsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "$SecretsPath is not valid JSON; fix it, then rerun" }
    if ($obj.PYTHON -and $obj.PYTHON -ne $script:VenvPy) { Info "PYTHON was $($obj.PYTHON)" }
  }
  $obj | Add-Member -NotePropertyName PYTHON -NotePropertyValue $script:VenvPy -Force
  [IO.File]::WriteAllText($SecretsPath, ($obj | ConvertTo-Json), $Utf8)
  Ok "PYTHON set in $SecretsPath"

  $local = Join-Path $InstallRoot 'CLAUDE.local.md'
  $text = [IO.File]::ReadAllText((Join-Path $Kit 'payload\CLAUDE.local.md.template'), $Utf8).Replace('{{VENV_PY}}', $script:VenvPy)
  if (-not (Test-Path $local)) { [IO.File]::WriteAllText($local, $text, $Utf8); Ok 'wrote CLAUDE.local.md' }
  elseif (-not ([IO.File]::ReadAllText($local, $Utf8).Contains($script:VenvPy))) { [IO.File]::AppendAllText($local, "`n" + $text, $Utf8); Ok 'added the venv note to CLAUDE.local.md' }
  else { Ok 'CLAUDE.local.md already points at the venv' }

  $packs = @($Versions.skillPacks | ForEach-Object { [ordered]@{ repo = $_.repo; commit = $_.commit } })
  $stamp = [ordered]@{ installed = (Get-Date -Format s); reelmimic = $Versions.reelmimic; skillPacks = $packs }
  [IO.File]::WriteAllText((Join-Path $InstallRoot '.studio-kit.json'), (New-Object PSObject -Property $stamp | ConvertTo-Json -Depth 5), $Utf8)
}

function Install-UserSkills {
  Say "User skills -> $SkillsDir"
  if (-not (Test-Path $SkillsDir)) { New-Item -ItemType Directory -Force $SkillsDir | Out-Null }
  foreach ($s in Get-ChildItem (Join-Path $Kit 'payload\skills') -Directory) {
    $dst = Join-Path $SkillsDir $s.Name
    if (Test-Path $dst) {
      if (-not $ForceSkills) { Ok "$($s.Name) already installed, left as is"; continue }
      $bak = "$dst.bak-$(Get-Date -Format yyyyMMddHHmmss)"
      Move-Item $dst $bak -ErrorAction Stop
      Info "moved the old $($s.Name) to $bak"
    }
    Copy-Item $s.FullName $dst -Recurse -ErrorAction Stop
    # bundled as _SKILL.md so they don't load as extra skills inside this kit
    Rename-Item (Join-Path $dst '_SKILL.md') 'SKILL.md' -ErrorAction Stop
    Ok "installed $($s.Name)"
  }
  # youtube-clipper runs with the user's normal Python, not the venv; both packages are small and dependency-light
  & $script:Py -m pip install --user --quiet --disable-pip-version-check yt-dlp pysrt
  if ($LASTEXITCODE -ne 0) { Warn 'could not install yt-dlp + pysrt for youtube-clipper' } else { Ok 'yt-dlp + pysrt for youtube-clipper' }
  # pre-warm the npx cache so OpenFilm's first use doesn't wait on a download
  $null = & npx.cmd -y openfilm@latest 2>$null
  if ($LASTEXITCODE -ne 0) { Warn 'npx openfilm@latest did not run; OpenFilm will fetch itself on first use' } else { Ok 'OpenFilm cached' }
}

# ---------- verification ----------

function Test-Install {
  Say 'Verification'
  & $script:VenvPy -I -c "import numpy, cv2, scenedetect, librosa, scipy, PIL, yt_dlp, faster_whisper, opencc"
  if ($LASTEXITCODE -eq 0) { Ok 'venv imports: numpy cv2 scenedetect librosa scipy PIL yt_dlp faster_whisper opencc' } else { Fail 'venv imports failed (see the error above)' }

  $libs = foreach ($m in 'animejs', 'gsap', 'three', 'remotion', '@remotion/cli', '@motion-canvas/core', '@motion-canvas/2d', 'vite') {
    $pj = Join-Path $InstallRoot "node_modules\$m\package.json"
    if (Test-Path $pj) { "$m@$((Get-Content $pj -Raw | ConvertFrom-Json).version)" } else { Fail "node module $m missing" }
  }
  if ($libs) { Ok "editing libs: $($libs -join '  ')" }

  $env:PYTHON = $script:VenvPy
  Push-Location (Join-Path $InstallRoot 'app')
  & node scripts\doctor.mjs
  $dc = $LASTEXITCODE
  Pop-Location
  if ($dc -eq 0) { Ok 'ReelMimic doctor passed' } else { Warn "ReelMimic doctor reported problems (exit code $dc), see above" }

  $proj = @(Get-ChildItem (Join-Path $InstallRoot '.claude\skills') -Directory).Count
  $absent = @($Versions.skillPacks | ForEach-Object { $_.skills } | Where-Object { -not (Test-Path (Join-Path $InstallRoot ".claude\skills\$_\SKILL.md")) })
  if ($absent.Count) { Fail "pack skills missing: $($absent -join ', ')" } else { Ok "$proj ReelMimic project skills (all pinned pack skills present)" }
  foreach ($s in Get-ChildItem (Join-Path $Kit 'payload\skills') -Directory) {
    if (Test-Path (Join-Path $SkillsDir "$($s.Name)\SKILL.md")) { Ok "user skill $($s.Name)" } else { Fail "user skill $($s.Name) missing" }
  }
}

function Show-Summary {
  Say 'Summary'
  if ($script:Problems.Count) { $script:Problems | ForEach-Object { Write-Host "  $_" } }
  else { Write-Host '  everything checked out' -ForegroundColor Green }
}

# ---------- main ----------

$missing = Test-Prereqs
if ($CheckOnly) { Show-Summary; exit ([int]($missing.Count -gt 0)) }
if ($missing -contains 'path') { Show-Summary; exit 1 }
if ($missing.Count) {
  if (-not $InstallPrereqs) {
    Write-Host "`nMissing: $($missing -join ', '). Install them, or rerun with -InstallPrereqs to use winget."
    exit 1
  }
  Install-Prereqs $missing
  $script:Problems = @()
  $missing = Test-Prereqs
  if ($missing.Count) { Show-Summary; exit 1 }
}

$script:Work = Join-Path (Split-Path $InstallRoot) '_vk'
try {
  if (Test-Path $script:Work) { Remove-Item $script:Work -Recurse -Force -ErrorAction Stop }
  New-Item -ItemType Directory -Force $script:Work | Out-Null
  Install-ReelMimic
  Install-SkillPacks
  Install-Venv
  Install-WebApp
  Install-EditingLibs
  Write-Config
  Install-UserSkills
} catch {
  Fail $_.Exception.Message
  Show-Summary
  exit 1
} finally {
  if (Test-Path $script:Work) { Remove-Item $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Install
Show-Summary
Write-Host @"

Next:
  - Open Claude Code in $InstallRoot to use ReelMimic's skills (they are project skills).
  - Web app: double-click $InstallRoot\start.bat, then http://localhost:4318 (needs the claude CLI, logged in).
  - Optional API keys: $SecretsPath (format: $InstallRoot\secrets.example.json).
"@
if (@($script:Problems | Where-Object { $_ -like 'FAIL*' }).Count) { exit 1 }
exit 0
