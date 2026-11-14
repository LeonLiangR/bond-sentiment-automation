param([string]$SettingsFile,[string]$InputFile,[string]$OutputDirectory,[int]$TimeoutSeconds=120,[switch]$SkipWind)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
$settings=Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8|ConvertFrom-Json
$engine=if($settings.spreadsheetEngine){$settings.spreadsheetEngine}else{'wps'}
$env:SENTIMENT_OFFICE_ENGINE=$engine;$env:SENTIMENT_OFFICE_PATH=if($engine -eq 'excel'){$settings.excelExe}else{$settings.wpsExe}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$sentinel=$null;$book=$null;$sheet=$null
try{
 # Create a test-owned sentinel, then treat it as pre-existing for a separate worker.
 $sentinel=Open-OwnedSpreadsheet $OutputDirectory;$book=$sentinel.Workbooks.Add();$sheet=$book.Worksheets.Item(1);$sheet.Range('A1').Value2='native-preservation-sentinel';$sheet.Range('G3').Value2=123456
 $sentinelProcess=Get-SpreadsheetProcess $sentinel
 $initial=[ordered]@{pid=$sentinelProcess.Id;visible=$sentinel.Visible;alerts=$sentinel.DisplayAlerts;calculation=$sentinel.Calculation;workbook=$sentinel.ActiveWorkbook.Name}
 $output=Join-Path $OutputDirectory 'wind-live.json'
 $scriptFile=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src/wind.ps1')).Replace("'","''")
 $commonFile=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src/wps-common.ps1')).Replace("'","''")
 $code="[Console]::OutputEncoding=[Text.UTF8Encoding]::new(`$false);`$source=[IO.File]::ReadAllText('$scriptFile',[Text.Encoding]::UTF8);`$common=[IO.File]::ReadAllText('$commonFile',[Text.Encoding]::UTF8);`$source=`$source.Replace("". (Join-Path ```$PSScriptRoot 'wps-common.ps1')"",`$common);& ([scriptblock]::Create(`$source)) -InputFile '"+$InputFile.Replace("'","''")+"' -OutputFile '"+$output.Replace("'","''")+"'"
 if($SkipWind){
  $parameters=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{directory=$OutputDirectory;file=(Join-Path $OutputDirectory 'engine-check.xlsx')}|ConvertTo-Json -Compress)))
  # Dot-source so the factory functions survive in the worker scope.
  $code="[Console]::OutputEncoding=[Text.UTF8Encoding]::new(`$false);. ([scriptblock]::Create([IO.File]::ReadAllText('$commonFile',[Text.Encoding]::UTF8)));`$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$parameters'))|ConvertFrom-Json;" + @'
$a=$null;$b=$null;try{$a=Open-OwnedSpreadsheet $p.directory;$b=$a.Workbooks.Add();$s=$b.Worksheets.Item(1);$s.Range('A1').Value2=6;$s.Range('A2').Value2=7;$s.Range('A3').Formula='=A1*A2';$a.Calculate();if($s.Range('A3').Value2 -ne 42){throw 'Formula check failed'};$b.SaveAs($p.file,51);$b.Close($false);Release-SpreadsheetCom $b;$b=$a.Workbooks.Open($p.file,0,$true);if($b.Worksheets.Item(1).Range('A3').Value2 -ne 42){throw 'Reopen check failed'};'{"passed":true,"formula":42,"reopened":true}'}finally{Release-SpreadsheetCom $s;Close-OwnedSpreadsheet $a $b}
'@
 }
 $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName='powershell.exe';$start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code));$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $worker=[Diagnostics.Process]::Start($start);$stdout=$worker.StandardOutput.ReadToEndAsync();$stderr=$worker.StandardError.ReadToEndAsync();if(-not $worker.WaitForExit($TimeoutSeconds*1000)){$worker.Kill();throw 'Wind check timeout'}
 if($worker.ExitCode -ne 0){throw $stderr.Result};$rows=@();if(-not $SkipWind){$rows=Get-Content -LiteralPath $output -Raw -Encoding UTF8|ConvertFrom-Json;if(-not @($rows|Where-Object {$_.code -match '^\d{6,9}\.(IB|SH|SZ)$' -and $_.issuer -is [string]}).Count){throw 'Wind returned no valid code or issuer'}}
 $preserved=$sentinel.Visible -eq $initial.visible -and $sentinel.DisplayAlerts -eq $initial.alerts -and $sentinel.Calculation -eq $initial.calculation -and $sentinel.ActiveWorkbook.Name -eq $initial.workbook -and $sentinel.Workbooks.Count -eq 1 -and $sheet.Range('A1').Value2 -eq 'native-preservation-sentinel' -and $sheet.Range('G3').Value2 -eq 123456
 if(-not $preserved){throw 'Existing workbook changed'}
 [ordered]@{passed=$true;kind='native';engine=$engine;windTested=(-not $SkipWind);windRows=$rows.Count;validCodes=@($rows|Where-Object {$_.code -match '^\d{6,9}\.(IB|SH|SZ)$'}).Count;preExistingWorkbookPreserved=$preserved;sentinelPid=$initial.pid;workerOutput=$stdout.Result}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $OutputDirectory 'native-verification.json') -Encoding UTF8
 Write-Output ($engine+' native worker and pre-existing workbook preservation passed')
}finally{Release-SpreadsheetCom $sheet;Close-OwnedSpreadsheet $sentinel $book;& (Join-Path $PSScriptRoot '../src/process-policy.ps1') -Mode cleanup -RunDirectory $OutputDirectory -SettingsFile $SettingsFile|Out-Null;$env:SENTIMENT_OFFICE_ENGINE=$null;$env:SENTIMENT_OFFICE_PATH=$null}
