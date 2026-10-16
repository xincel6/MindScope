# tap.ps1 - Drive the HarmonyOS emulator UI from hdc (tap / type / swipe / fling).
#
# Why: driving this emulator by hand with guessed coordinates wasted several attempts.
# The reliable loop is: `uidump.ps1` to read real bounds -> tap.ps1 to act.
# Keeping both in one place also documents the exact hdc command shapes.
#
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 without a BOM as ANSI).
#
# Usage:
#   pwsh -File harmony/scripts/tap.ps1 -X 658 -Y 1208
#   pwsh -File harmony/scripts/tap.ps1 -X 658 -Y 1208 -Text "harmony_probe"
#   pwsh -File harmony/scripts/tap.ps1 -Swipe "658 2200 658 900 400"
#   pwsh -File harmony/scripts/tap.ps1 -Fling "0 1 900"
param(
  [int]$X = 0,
  [int]$Y = 0,
  [string]$Text = "",
  [string]$Swipe = "",
  [string]$Fling = "",
  [int]$SettleMs = 900
)

$ErrorActionPreference = 'Stop'
$hdc = "E:\HarmonyOS\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
if (-not (Test-Path $hdc)) { throw "hdc not found: $hdc" }

function Invoke-UiInput([string]$command) {
  # NOTE: never name a parameter `$args` here - it collides with PowerShell's
  # automatic $args variable and every call silently loses its arguments.
  $out = & $hdc shell "uitest uiInput $command" 2>&1
  Write-Output ("uiInput $command -> " + ($out -join ' ').Trim())
}

if ($Fling.Length -gt 0) {
  Invoke-UiInput "dircFling $Fling"
} elseif ($Swipe.Length -gt 0) {
  Invoke-UiInput "swipe $Swipe"
} else {
  Invoke-UiInput "click $X $Y"
  if ($Text.Length -gt 0) {
    Start-Sleep -Milliseconds $SettleMs
    Invoke-UiInput "inputText $X $Y $Text"
  }
}
Start-Sleep -Milliseconds $SettleMs
