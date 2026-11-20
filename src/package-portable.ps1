[CmdletBinding(DefaultParameterSetName='Public')]
param(
 [Parameter(Mandatory=$true)][string]$NodeBinDirectory,
 [Parameter(ParameterSetName='Public')][switch]$PublicRelease,
 [Parameter(Mandatory=$true,ParameterSetName='Internal')][string]$HistorySeedFile,
 [string]$DesktopExeFile
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version=(Get-Content -LiteralPath (Join-Path $project 'package.json') -Raw|ConvertFrom-Json).version
$distRoot=Join-Path $project 'dist'
$buildRoot=Join-Path $distRoot ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
$internal=$PSCmdlet.ParameterSetName -eq 'Internal'
$suffix=if($internal){'-internal'}else{''}
$folder=Join-Path $buildRoot ('BondSentiment-'+$version+'-win-x64'+$suffix)
& (Join-Path $project 'scripts/build-desktop.ps1') -Destination $folder -NodeBinDirectory $NodeBinDirectory -HistorySeedFile $HistorySeedFile -DesktopExeFile $DesktopExeFile | Out-Null
if($LASTEXITCODE -ne 0){throw 'Desktop build failed'}
$seedPath=Join-Path $folder 'assets/history-seed.json'
$seed=@()
if($internal){
 $seed=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($seedPath,[Text.Encoding]::UTF8))
 if(-not ($seed -is [Array]) -or $seed.Count -eq 0 -or $seed[0].date -isnot [string] -or $seed[-1].date -isnot [string]){throw 'Invalid exported history seed metadata'}
}elseif(Test-Path -LiteralPath $seedPath){throw 'Public release must not contain a history seed'}
$commit=(& git -C $project rev-parse HEAD).Trim();if($LASTEXITCODE -ne 0){throw 'Source revision unavailable'}
$buildInfo=[ordered]@{version=$version;sourceCommit=$commit;sourceDirty=([bool](& git -C $project status --porcelain));buildDate=[DateTime]::UtcNow.ToString('yyyy-MM-dd');channel=$(if($internal){'internal'}else{'public'});includesPrivateConfiguration=$false;includesRawSamples=$false;includesAuthorizedAggregateHistory=$internal;historyRows=$seed.Count;historyFirstDate=$(if($seed.Count){$seed[0].date});historyLastDate=$(if($seed.Count){$seed[-1].date});excelActivation='direct-exe-nativeom';excelFixedClsidActivation=$false;excelBackgroundWindowGuard=$true;excelBootstrapClosedWithoutSaving=$true;dmWholeSampleFallback=$true;dmEmptyThemeDefaultsToNone=$true;windFinalABRetry=$true;windStableZeroRetrySeconds=10;perRunUtilityWorker=$true;reportXlsxSaveCopy=$true;desktopExecutableReused=[bool]$DesktopExeFile;additionalRuntimeTestsRunForThisPackage=$false;excelComHotfixNativeExcelVerified=$false}
[IO.File]::WriteAllText((Join-Path $folder 'build-info.json'),($buildInfo|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
$manifest=@(Get-ChildItem -LiteralPath $folder -File -Recurse|ForEach-Object {[ordered]@{path=$_.FullName.Substring($folder.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()}})
[IO.File]::WriteAllText((Join-Path $folder 'manifest.json'),($manifest|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=Join-Path $buildRoot ('BondSentiment-'+$version+'-win-x64'+$suffix+'.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($folder,$zip,[IO.Compression.CompressionLevel]::Optimal,$true)
[ordered]@{folder=$folder;zip=$zip;zipBytes=(Get-Item -LiteralPath $zip).Length;files=$manifest.Count;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()}|ConvertTo-Json -Compress
