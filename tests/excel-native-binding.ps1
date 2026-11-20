param([string]$OutputDirectory=(Join-Path $PSScriptRoot '../test-results/excel-direct-native'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory);New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$exe=Join-Path $OutputDirectory 'EXCEL.EXE';$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
& (Join-Path $framework 'csc.exe') /nologo /target:winexe /platform:x64 ('/r:'+(Join-Path $framework 'System.Windows.Forms.dll')) ('/out:'+$exe) (Join-Path $PSScriptRoot 'FakeExcelNativeServer.cs')
if($LASTEXITCODE -ne 0){throw 'Test native server compilation failed'}
$env:SENTIMENT_FAKE_EXCEL_STATE=$OutputDirectory;$env:SENTIMENT_OFFICE_ENGINE='excel';$env:SENTIMENT_OFFICE_PATH=$exe
$script:launcher=${function:Start-ExcelProcess};$script:reader=${function:Read-ExcelNativeWindow};$script:launched=@();$script:rejectCount=0;$script:other=$null
function New-SpreadsheetProgId {throw 'Excel must never use a ProgID'}
function Start-ExcelProcess([string]$Exe,[string]$Bootstrap){$p=& $script:launcher $Exe $Bootstrap;$script:launched+=@($p);return $p}
function Read-ExcelNativeWindow([IntPtr]$Handle,[int]$ProcessId){
 if($null -ne $script:other){return [pscustomobject]@{Application=$script:other}}
 if($script:rejectCount -gt 0){$script:rejectCount--;throw [Runtime.InteropServices.COMException]::new('busy',-2147418111)}
 return & $script:reader $Handle $ProcessId
}
$existingProcess=$null;$existing=$null;$app=$null;$cases=@()
try{
 Initialize-ExcelNative
 $existingProcess=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
 $timer=[Diagnostics.Stopwatch]::StartNew();$handles=@();while(-not $handles.Count -and $timer.Elapsed.TotalSeconds -lt 10){$handles=@(Get-ExcelNativeWindows $existingProcess.Id);Start-Sleep -Milliseconds 100}
 Assert ($handles.Count -gt 0) 'Existing test EXCEL7 window not found'
 $window=& $script:reader $handles[0] $existingProcess.Id;$existing=$window.Application;Release-SpreadsheetCom $window
 Assert ($existing.Visible -and $existing.DisplayAlerts) ('Existing native test state invalid; window='+[string]($null -ne $window)+' app='+[string]($null -ne $existing)+' hwnd='+[string]$existing.Hwnd+' visible='+[string]$existing.Visible+' alerts='+[string]$existing.DisplayAlerts)
 $app=Open-OwnedSpreadsheet $OutputDirectory;$owned=Get-SpreadsheetProcess $app
 Assert ($owned.Id -ne $existingProcess.Id -and -not $app.Visible -and -not $app.DisplayAlerts) 'Native binding selected wrong process or did not hide owned instance'
 Assert ($existing.Visible -and $existing.DisplayAlerts) 'Existing native instance modified'
 Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class TestWindowVisibility{[DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);}'
 $unownedPopup=[IntPtr]$existing.RevealWindow()
 for($i=0;$i -lt 5;$i++){
  $popup=[IntPtr]$app.RevealWindow();$wait=[Diagnostics.Stopwatch]::StartNew()
  while([TestWindowVisibility]::IsWindowVisible($popup) -and $wait.ElapsedMilliseconds -lt 1500){Start-Sleep -Milliseconds 20}
  Assert (-not [TestWindowVisibility]::IsWindowVisible($popup)) 'New owned popup was not hidden by the persistent guard'
  Assert ([TestWindowVisibility]::IsWindowVisible($unownedPopup)) 'Guard hid a pre-existing process window'
 }
 $cases+='persistent-guard-hides-new-owned-windows-and-preserves-unowned-windows'
 Close-OwnedSpreadsheet $app $null;$app=$null;Assert ($script:launched[-1].WaitForExit(4000)) 'Owned native instance not closed'
 $cases+='windows-nativeom-target-process-and-existing-instance-preserved'
 $script:rejectCount=2;$before=$script:launched.Count
 $app=Open-OwnedSpreadsheet $OutputDirectory;Assert ($script:launched.Count-$before -eq 1 -and $script:rejectCount -eq 0) 'Busy binding started duplicate Excel processes'
 Close-OwnedSpreadsheet $app $null;$app=$null;Assert ($script:launched[-1].WaitForExit(4000)) 'Busy native instance not closed'
 $cases+='busy-native-binding-retries-within-one-process'
 $env:SENTIMENT_FAKE_EXCEL_MODE='no-window';$caught=$false
 try{$null=New-ExcelDirect (Get-SpreadsheetSpec) $OutputDirectory -TimeoutSeconds 2}catch{$failure=$_.Exception.Message;$caught=$failure -match 'timed out'}
 Assert ($caught -and $script:launched[-1].WaitForExit(4000) -and -not $existingProcess.HasExited) ('Binding timeout leaked process or closed existing instance: '+$failure)
 $cases+='no-native-window-times-out-and-cleans-owned-process'
 $env:SENTIMENT_FAKE_EXCEL_MODE=$null;$script:other=$existing;$caught=$false
 try{$null=New-ExcelDirect (Get-SpreadsheetSpec) $OutputDirectory -TimeoutSeconds 2}catch{$caught=$_.Exception.Message -match 'different or pre-existing process'}
 Assert ($caught -and $script:launched[-1].WaitForExit(4000) -and -not $existingProcess.HasExited) 'Wrong native application was accepted or an unrelated instance was closed'
 $script:other=$null;$existing=$null
 $window=& $script:reader $handles[0] $existingProcess.Id;$existing=$window.Application;Release-SpreadsheetCom $window
 Assert ($existing.Visible -and $existing.DisplayAlerts) 'Wrong native binding touched existing application'
 $cases+='wrong-native-process-rejected-without-quitting-existing-instance'
 $entries=@(Get-Content -LiteralPath (Join-Path $OutputDirectory 'office-instances.jsonl')|ForEach-Object {$_|ConvertFrom-Json})
 foreach($p in $script:launched){Assert (@($entries|Where-Object {$_.processId -eq $p.Id -and $_.activationMethod -eq 'direct-exe-nativeom'}).Count -eq 1) 'Activation was not journaled before binding'}
 $cases+='every-direct-process-journaled-before-binding'
 [ordered]@{passed=$true;kind='Windows native OM test server, not Microsoft Excel';nativeExcelVerified=$false;cases=$cases}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $OutputDirectory 'native-binding.json') -Encoding UTF8
 Write-Output ('Windows native OM binding cases passed: '+$cases.Count+' (test server; not Microsoft Excel)')
}finally{
 Close-OwnedSpreadsheet $app $null
 if($existing){try{$existing.Quit()}catch{};Release-SpreadsheetCom $existing}
 foreach($p in @($script:launched)+@($existingProcess)){if($p){try{$p.Refresh();if(-not $p.HasExited -and [string]::Equals($p.Path,$exe,[StringComparison]::OrdinalIgnoreCase)){Stop-Process -Id $p.Id -Force}}catch{}}}
 $env:SENTIMENT_FAKE_EXCEL_STATE=$null;$env:SENTIMENT_FAKE_EXCEL_MODE=$null;$env:SENTIMENT_OFFICE_ENGINE=$null;$env:SENTIMENT_OFFICE_PATH=$null
}
