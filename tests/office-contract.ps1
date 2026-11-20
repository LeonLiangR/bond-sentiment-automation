param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
Add-Type -TypeDefinition 'public class FakeOfficeApp { public long Hwnd=1; public bool Visible=true; public bool DisplayAlerts=true; public bool ScreenUpdating=true; public bool Interactive=true; public bool EnableEvents=true; public int QuitCount=0; public void Quit(){QuitCount++;} } public class FakeOfficeBook { public bool Saved=false; public int CloseCount=0; public void Close(bool save){CloseCount++;} }'
function Hide-ExcelWindows([int]$ProcessId){}
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function New-SpreadsheetCom([string]$ProgId){$script:lastProgId=$ProgId;if($script:factoryFails){throw 'Class not registered'};return $script:fake}
function Get-SpreadsheetProcesses {return $script:previous}
function Get-SpreadsheetProcess($Application){return $script:identity}
function Reset-Fake([string]$Engine,[string]$Name,[string]$Path){
 $env:SENTIMENT_OFFICE_ENGINE=$Engine;$env:SENTIMENT_OFFICE_PATH=$Path
 $script:fake=New-Object FakeOfficeApp;$script:identity=[pscustomobject]@{Id=99101;ProcessName=$Name;Path=$Path;StartTime=[datetime]'2026-11-13T10:00:00Z'};$script:previous=@();$script:factoryFails=$false
}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$results=@()
try{
 foreach($engine in @('excel','wps')){
  $name=if($engine -eq 'excel'){'EXCEL'}else{'et'};$path=if($engine -eq 'excel'){'C:\Office\EXCEL.EXE'}else{'C:\WPS\et.exe'}
  Reset-Fake $engine $name $path;$app=Open-OwnedSpreadsheet $OutputDirectory
  Assert (-not $app.Visible -and -not $app.DisplayAlerts) 'Owned instance was not configured hidden'
  Assert ($script:lastProgId -eq (Get-SpreadsheetSpec).progId) 'Wrong COM class selected'
  $book=New-Object FakeOfficeBook;Close-OwnedSpreadsheet $app $book
  Assert ($script:fake.QuitCount -eq 1 -and $book.CloseCount -eq 1) 'Owned instance not released'
  $results+=$engine+'-owned-instance'
  Reset-Fake $engine $name $path;$script:previous=@($script:identity);$caught=$false
  try{$null=Open-OwnedSpreadsheet $OutputDirectory}catch{$caught=$_.Exception.Message -match 'pre-existing'}
  Assert ($caught -and $script:fake.Visible -and $script:fake.DisplayAlerts -and $script:fake.QuitCount -eq 0) 'Pre-existing instance was touched'
  Close-OwnedSpreadsheet $script:fake $null;Assert ($script:fake.QuitCount -eq 0) 'Close changed an unowned application'
  $results+=$engine+'-pre-existing-preserved'
 }
 Reset-Fake 'excel' 'et' 'C:\Office\EXCEL.EXE';$caught=$false
 try{$null=Open-OwnedSpreadsheet $OutputDirectory}catch{$caught=$_.Exception.Message -match 'no fallback'}
 Assert ($caught -and $script:fake.QuitCount -eq 1) 'Wrong engine was accepted or leaked';$results+='wrong-engine-rejected'
 Reset-Fake 'excel' 'EXCEL' 'C:\Office\EXCEL.EXE';$script:identity.Path='C:\Other\EXCEL.EXE';$caught=$false
 try{$null=Open-OwnedSpreadsheet $OutputDirectory}catch{$caught=$_.Exception.Message -match 'different executable'}
 Assert ($caught -and $script:fake.QuitCount -eq 1) 'Wrong registered path accepted';$results+='wrong-path-rejected'
 Reset-Fake 'excel' 'EXCEL' 'C:\Office\EXCEL.EXE';$script:factoryFails=$true;$caught=$false
 try{$null=Open-OwnedSpreadsheet $OutputDirectory}catch{$caught=$_.Exception.Message -match 'Excel automation is unavailable'}
 Assert ($caught -and $script:fake.QuitCount -eq 0 -and $script:lastProgId -eq 'Excel.Application') 'Missing Excel silently used another engine';$results+='missing-excel-no-fallback'
 [ordered]@{passed=$true;kind='simulated-contract-only';cases=$results;nativeExcelVerified=$false}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $OutputDirectory 'contract.json') -Encoding UTF8
 Write-Output ('Office contract cases passed: '+$results.Count+' (simulation, not native Excel)')
}finally{$env:SENTIMENT_OFFICE_ENGINE=$null;$env:SENTIMENT_OFFICE_PATH=$null}
