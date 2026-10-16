# capture.ps1 - Grab a screenshot from the HarmonyOS emulator/device and pull it locally.
#
# Why a script: `hdc file recv` does NOT resolve a relative destination against the
# caller's cwd (measured: it landed in `E:/Git/...`). So we must Set-Location to the
# target directory first. Wrapping it means repeated manual runs cannot hit that trap.
#
# NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads .ps1
# without a BOM as ANSI, which mangles non-ASCII comments into a parse error.
#
# Usage:
#   pwsh -File harmony/scripts/capture.ps1 -Name shot1
#   pwsh -File harmony/scripts/capture.ps1 -Name shot2 -SleepMs 3000
param(
  [Parameter(Mandatory = $true)][string]$Name,
  [int]$SleepMs = 1500,
  [string]$OutDir = "E:\MindScope\_materials\_verify"
)

$ErrorActionPreference = 'Stop'
$hdc = "E:\HarmonyOS\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
if (-not (Test-Path $hdc)) { throw "hdc not found: $hdc" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$remote = "/data/local/tmp/$Name.jpeg"
$local = Join-Path $OutDir "$Name.jpeg"

if ($SleepMs -gt 0) { Start-Sleep -Milliseconds $SleepMs }

& $hdc shell "snapshot_display -f $remote" | Out-Null
Push-Location $OutDir
try {
  & $hdc file recv $remote "$Name.jpeg" | Out-Null
} finally {
  Pop-Location
}

if (Test-Path $local) {
  $size = (Get-Item $local).Length
  Write-Output "saved: $local ($size bytes)"
} else {
  throw "capture failed, missing: $local"
}
