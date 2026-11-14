param([string]$Destination = (Join-Path $PSScriptRoot '../local-app/v0.5.1'), [string]$NodeBinDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
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
$references = @('System.dll','System.Core.dll','System.Xaml.dll','System.Web.Extensions.dll','System.Drawing.dll','WPF/WindowsBase.dll','WPF/PresentationCore.dll','WPF/PresentationFramework.dll') | ForEach-Object { '/r:' + (Join-Path $framework $_) }
$sources = @($policy.source | Where-Object { $_ -match '^src/desktop/.+\.cs$' -or $_ -eq 'src/Plot.cs' } | ForEach-Object { Join-Path $projectRoot $_ })
$exe = Join-Path $destinationRoot '一级市场情绪指数.exe'
& (Join-Path $framework 'csc.exe') /nologo /target:winexe /optimize+ /platform:x64 /utf8output ('/win32icon:' + (Join-Path $projectRoot 'assets/app.ico')) ('/win32manifest:' + (Join-Path $projectRoot 'src/desktop/app.manifest')) ('/out:' + $exe) @references @sources
if ($LASTEXITCODE -ne 0) { throw '桌面程序编译失败' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'src/desktop/app.config') -Destination ($exe + '.config') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'package.json') -Destination (Join-Path $destinationRoot 'package.json') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'PORTABLE-README.txt') -Destination (Join-Path $destinationRoot '使用说明.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/EXCEL-TESTING.md') -Destination (Join-Path $destinationRoot 'Excel测试说明.md') -Force
Write-Output $exe
