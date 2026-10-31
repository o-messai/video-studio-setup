<#
.SYNOPSIS
  Builds payload\archives\: slim, pinned copies of ReelMimic and every skill pack in lock\versions.json, so setup
  works without GitHub. Kit maintenance only; rerun it after changing the pins (stale archives are removed).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File build-bundle.ps1
#>
[CmdletBinding()]
param([string]$WorkDir)

$ErrorActionPreference = 'Stop'   # only cmdlets and .NET calls here, no native tools
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$Kit = Split-Path -Parent $PSScriptRoot
$Versions = Get-Content (Join-Path $Kit 'lock\versions.json') -Raw | ConvertFrom-Json
$Out = Join-Path $Kit 'payload\archives'
# keep the work dir short: ReelMimic's deepest paths plus GitHub's folder prefix approach Windows' 260-char limit
if (-not $WorkDir) { $WorkDir = Join-Path (Split-Path $Kit) '_kb' }
New-Item -ItemType Directory -Force $Out, $WorkDir | Out-Null

# Same naming as Get-PinnedZip in setup.ps1 / pinned_zip in setup.sh
function Get-ArchiveName([string]$Repo, [string]$Commit) { '{0}@{1}.zip' -f ($Repo -replace '/', '__'), $Commit.Substring(0, 7) }

function Build-Archive([string]$Repo, [string]$Commit, [scriptblock]$Keep) {
  $name = Get-ArchiveName $Repo $Commit
  $dest = Join-Path $Out $name
  if (Test-Path $dest) { Write-Host "  kept   $name"; return }
  $zip = Join-Path $WorkDir 'dl.zip'
  $x = Join-Path $WorkDir 'x'
  if (Test-Path $x) { Remove-Item $x -Recurse -Force }
  Invoke-WebRequest -UseBasicParsing "https://codeload.github.com/$Repo/zip/$Commit" -OutFile $zip
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $x)
  $root = (Get-ChildItem $x -Directory | Select-Object -First 1).FullName
  $top = ($Repo -split '/')[1]
  $tmp = "$dest.partial"
  $archive = [IO.Compression.ZipFile]::Open($tmp, 'Create')
  try {
    foreach ($f in Get-ChildItem $root -Recurse -File -Force) {
      # forward slashes: backslash entry names break extraction on macOS/Linux
      $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
      if (& $Keep $rel) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, "$top/$rel", 'Optimal') }
    }
  } finally { $archive.Dispose() }
  Move-Item $tmp $dest
  Write-Host ('  built  {0}  {1:N1} MB' -f $name, ((Get-Item $dest).Length / 1MB))
}

$isLicense = { param($r) $r -match '^(LICEN[CS]E|NOTICE|THIRD_PARTY)' }

Write-Host '== ReelMimic'
# everything except the README screenshots and demo GIFs in docs/assets
Build-Archive $Versions.reelmimic.repo $Versions.reelmimic.commit { param($r) -not $r.StartsWith('docs/assets/') }

Write-Host '== Skill packs'
foreach ($pack in $Versions.skillPacks) {
  $skills = @($pack.skills)
  $include = @($pack.include)
  $shared = [bool]$pack.sharedScripts
  $keep = {
    param($r)
    if (& $isLicense $r) { return $true }
    if ($include.Count -and $include[0]) { return [bool]($include | Where-Object { $r -eq $_ -or $r.StartsWith("$_/") }) }
    if ($shared -and $r.StartsWith('scripts/')) { return $true }
    return [bool]($skills | Where-Object { $r.StartsWith("skills/$_/") })
  }.GetNewClosure()
  Build-Archive $pack.repo $pack.commit $keep
}

# drop archives for commits that are no longer pinned
$wanted = @(Get-ArchiveName $Versions.reelmimic.repo $Versions.reelmimic.commit) + @($Versions.skillPacks | ForEach-Object { Get-ArchiveName $_.repo $_.commit })
Get-ChildItem $Out -Filter *.zip | Where-Object { $wanted -notcontains $_.Name } | ForEach-Object { Remove-Item $_.FullName; Write-Host "  removed stale $($_.Name)" }
Remove-Item $WorkDir -Recurse -Force
$all = Get-ChildItem $Out -Filter *.zip
Write-Host ('== {0} archives, {1:N1} MB total' -f $all.Count, (($all | Measure-Object Length -Sum).Sum / 1MB))
