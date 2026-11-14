param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target = [IO.Path]::GetFullPath($Destination)
. (Join-Path $PSScriptRoot 'release-common.ps1')
New-EmptyReleaseDirectory $target
$policy = Get-Content -LiteralPath (Join-Path $root 'release-files.json') -Raw | ConvertFrom-Json
foreach ($file in @($policy.runtime) + @($policy.source)) { Copy-ReleaseFile $root $target $file }
foreach ($file in $policy.templates) { Copy-CleanTemplate $root $target $file }
Write-Output $target
