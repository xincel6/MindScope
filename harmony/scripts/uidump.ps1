# uidump.ps1 - Dump the HarmonyOS UI layout tree and print element bounds.
#
# Why: this emulator renders through a letterboxed window, so screen coordinates in a
# screenshot do NOT map 1:1 onto the values that `uitest uiInput click` expects.
# Guessing coordinates wasted several attempts; reading the real bounds from the
# layout dump is the reliable way to drive the UI from hdc.
#
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 without a BOM as ANSI).
#
# Usage:
#   pwsh -File harmony/scripts/uidump.ps1                        # clickable elements only
#   pwsh -File harmony/scripts/uidump.ps1 -Filter "热力"          # keep only matching text
#   pwsh -File harmony/scripts/uidump.ps1 -All                    # every element with text
param(
  [string]$Filter = "",
  [switch]$All
)

$ErrorActionPreference = 'Stop'
$hdc = "E:\HarmonyOS\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
$out = "E:\MindScope\_materials\_verify"
New-Item -ItemType Directory -Force -Path $out | Out-Null

& $hdc shell "uitest dumpLayout -p /data/local/tmp/layout.json" | Out-Null
Push-Location $out
try { & $hdc file recv "/data/local/tmp/layout.json" "layout.json" | Out-Null } finally { Pop-Location }

$raw = Get-Content (Join-Path $out 'layout.json') -Raw

# NOTE: `ConvertFrom-Json` is not reliable here - the dump contains malformed JSON
# fragments (measured: `"r":"HitTestMode.Default"` where a key went missing), and the
# file's encoding can be misread by Windows PowerShell. Plain regex over the raw text
# is robust against both, and all we need is (text, bounds, clickable).
$pattern = '"bounds":"\[(\d+),(\d+)\]\[(\d+),(\d+)\]".{0,600}?"text":"([^"]*)"'
$rows = New-Object System.Collections.Generic.List[object]
foreach ($m in [regex]::Matches($raw, $pattern)) {
  $text = $m.Groups[5].Value
  if ($text.Length -eq 0) { continue }
  $x1 = [int]$m.Groups[1].Value; $y1 = [int]$m.Groups[2].Value
  $x2 = [int]$m.Groups[3].Value; $y2 = [int]$m.Groups[4].Value
  $rows.Add([pscustomobject]@{
    text  = $text
    cx    = [int](($x1 + $x2) / 2)
    cy    = [int](($y1 + $y2) / 2)
    bounds = "$x1,$y1-$x2,$y2"
  })
}

$result = $rows
if ($Filter.Length -gt 0) { $result = $rows | Where-Object { $_.text -like "*$Filter*" } }
$lines = New-Object System.Collections.Generic.List[string]
foreach ($r in $result) {
  $lines.Add(("{0,6},{1,6}  {2}" -f $r.cx, $r.cy, $r.text))
}
$lines | ForEach-Object { Write-Output $_ }
Write-Output "total matched: $($lines.Count)"
