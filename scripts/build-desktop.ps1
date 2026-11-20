param([string]$Destination, [string]$NodeBinDirectory, [string]$HistorySeedFile, [string]$DesktopExeFile, [string]$ChartRendererFile)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'package.json') -Raw | ConvertFrom-Json).version
if (-not $Destination) { $Destination = Join-Path $projectRoot ('local-app/v'+$version) }
$destinationRoot = [IO.Path]::GetFullPath($Destination)
. (Join-Path $PSScriptRoot 'release-common.ps1')
New-EmptyReleaseDirectory $destinationRoot
$policy = Get-Content -LiteralPath (Join-Path $projectRoot 'release-files.json') -Raw | ConvertFrom-Json
foreach ($file in $policy.runtime) { Copy-ReleaseFile $projectRoot $destinationRoot $file }
foreach ($file in $policy.templates) { Copy-CleanTemplate $projectRoot $destinationRoot $file }
$runtimeTarget = Join-Path $destinationRoot 'runtime/node/node.exe'
if (-not (Test-Path -LiteralPath $runtimeTarget)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $runtimeTarget) -Force | Out-Null
    $runtimeSource = if ($NodeBinDirectory) { Join-Path $NodeBinDirectory 'node.exe' } elseif (Get-Command node.exe -ErrorAction SilentlyContinue) { (Get-Command node.exe).Source } else { Join-Path $projectRoot 'local-app/v0.3.0/runtime/node/node.exe' }
    if (-not (Test-Path -LiteralPath $runtimeSource)) { throw '未找到Node.js运行环境，请安装Node.js 24或通过-NodeBinDirectory指定node.exe所在目录。' }
    Copy-Item -LiteralPath $runtimeSource -Destination $runtimeTarget
}
$framework = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
if ($HistorySeedFile) {
    & $runtimeTarget (Join-Path $projectRoot 'scripts/export-history-seed.mjs') $HistorySeedFile (Join-Path $destinationRoot 'assets/history-seed.json') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw '绘图历史种子导出失败' }
}
$references = @('System.dll','System.Core.dll','System.Xaml.dll','System.Web.Extensions.dll','System.Drawing.dll','WPF/WindowsBase.dll','WPF/PresentationCore.dll','WPF/PresentationFramework.dll') | ForEach-Object { '/r:' + (Join-Path $framework $_) }
$sources = @($policy.source | Where-Object { $_ -match '^src/desktop/.+\.cs$' -or $_ -eq 'src/Plot.cs' } | ForEach-Object { Join-Path $projectRoot $_ })
$exe = Join-Path $destinationRoot '一级市场情绪指数.exe'
if ($DesktopExeFile) {
    $expectedVersion=$version+'.0'
    if ((Get-Item -LiteralPath $DesktopExeFile).VersionInfo.FileVersion -ne $expectedVersion) { throw '桌面exe版本与源码不一致，请重新编译而非复用旧exe。' }
    Copy-Item -LiteralPath $DesktopExeFile -Destination $exe
} else {
& (Join-Path $framework 'csc.exe') /nologo /target:winexe /optimize+ /platform:x64 /utf8output ('/win32icon:' + (Join-Path $projectRoot 'assets/app.ico')) ('/win32manifest:' + (Join-Path $projectRoot 'src/desktop/app.manifest')) ('/out:' + $exe) @references @sources
if ($LASTEXITCODE -ne 0) { throw '桌面程序编译失败' }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'src/desktop/app.config') -Destination ($exe + '.config') -Force
$chartCache=Join-Path $projectRoot 'local-app/chart-renderer/ChartRenderer.exe'
$chartTarget=Join-Path $destinationRoot 'runtime/ChartRenderer.exe'
if($ChartRendererFile){
    New-Item -ItemType Directory -Path (Split-Path -Parent $chartCache) -Force|Out-Null
    Copy-Item -LiteralPath $ChartRendererFile -Destination $chartCache -Force
}
if(Test-Path -LiteralPath $chartCache){Copy-Item -LiteralPath $chartCache -Destination $chartTarget -Force}
else {
    & (Join-Path $framework 'csc.exe') /nologo /target:winexe /optimize+ /platform:x64 /utf8output ('/win32manifest:'+(Join-Path $projectRoot 'src/desktop/app.manifest')) ('/out:'+$chartTarget) @references (Join-Path $projectRoot 'src/ChartProgram.cs') (Join-Path $projectRoot 'src/Plot.cs')
    if($LASTEXITCODE -ne 0){throw '绘图组件编译失败'}
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'src/desktop/app.config') -Destination ($chartTarget+'.config') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'package.json') -Destination (Join-Path $destinationRoot 'package.json') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'PORTABLE-README.txt') -Destination (Join-Path $destinationRoot '使用说明.txt') -Force
& $runtimeTarget (Join-Path $projectRoot 'scripts/verify-runtime.mjs') $destinationRoot (Join-Path $projectRoot 'release-files.json') | Out-Host
if ($LASTEXITCODE -ne 0) { throw '运行目录完整性核验失败，禁止发布不完整程序。' }
Write-Output $exe
