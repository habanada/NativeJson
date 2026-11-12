param(
  [Parameter(Mandatory = $true)][ValidateSet('Win32', 'Win64')][string]$Platform
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pattern = "(<Platform Condition=""'\`$\(Platform\)'==''"">)(Win32|Win64)(</Platform>)"
$changed = 0
Get-ChildItem -Path $root -Recurse -Filter '*.dproj' |
  Where-Object { $_.FullName -notmatch '[\\/]_dev[\\/]' } |
  ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($_.FullName)
    $updated = [regex]::Replace($text, $pattern, "`${1}$Platform`${3}")
    if ($updated -ne $text) {
      [IO.File]::WriteAllText($_.FullName, $updated, (New-Object Text.UTF8Encoding $hasBom))
      $changed++
    }
  }
Write-Host "Default platform set to $Platform in $changed project(s)."
