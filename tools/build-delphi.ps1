param(
  [Parameter(Mandatory = $true)][string]$Project,
  [ValidateSet('Win32', 'Win64')][string]$Platform = 'Win32',
  [ValidateSet('Debug', 'Release')][string]$Config = 'Debug'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Project)) { throw "Project not found: $Project" }
$msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
if (-not $msbuild) { throw 'MSBuild not found; launch from an initialized RAD Studio environment.' }
& $msbuild.Source $Project "/p:Config=$Config" "/p:Platform=$Platform" '/t:Build' '/v:minimal'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
