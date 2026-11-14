param([Parameter(Mandatory=$true)][string]$NodeBinDirectory)
# Run only when a colleague package is explicitly requested.
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version=(Get-Content -LiteralPath (Join-Path $project 'package.json') -Raw|ConvertFrom-Json).version
$distRoot=Join-Path $project 'dist'
$buildRoot=Join-Path $distRoot ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$folder=Join-Path $buildRoot ('BondSentiment-'+$version+'-win-x64')
& (Join-Path $project 'scripts/build-desktop.ps1') -Destination $folder -NodeBinDirectory $NodeBinDirectory | Out-Null
if($LASTEXITCODE -ne 0){throw 'Desktop build failed'}
$manifest=@(Get-ChildItem -LiteralPath $folder -File -Recurse|ForEach-Object {[ordered]@{path=$_.FullName.Substring($folder.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()}})
[IO.File]::WriteAllText((Join-Path $folder 'manifest.json'),($manifest|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=Join-Path $buildRoot ('BondSentiment-'+$version+'-win-x64.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($folder,$zip,[IO.Compression.CompressionLevel]::Optimal,$true)
[ordered]@{folder=$folder;zip=$zip;zipBytes=(Get-Item -LiteralPath $zip).Length;files=$manifest.Count;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()}|ConvertTo-Json -Compress