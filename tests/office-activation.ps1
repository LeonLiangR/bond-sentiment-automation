param([string]$OutputDirectory=(Join-Path $PSScriptRoot '../test-results/office-activation'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$script:progIds=@();$script:directCalls=@();$script:directFails=$false
function New-SpreadsheetProgId([string]$ProgId){$script:progIds+=@($ProgId);return [pscustomobject]@{engine='wps';origin='redirected-progid'}}
function New-SpreadsheetClsid {throw 'CLSID activation is forbidden in Excel direct mode'}
function New-ExcelDirect($Spec,[string]$TrackerDirectory){
 $script:directCalls+=@([pscustomobject]@{spec=$Spec;directory=$TrackerDirectory})
 if($script:directFails){throw 'Direct Excel is unavailable'}
 return [pscustomobject]@{engine='excel';origin='direct-exe-nativeom'}
}
$env:SENTIMENT_OFFICE_ENGINE='excel';$env:SENTIMENT_OFFICE_PATH='C:\Office\EXCEL.EXE'
$cases=@()
# Neither the ProgID nor a redirected CLSID may be used for Excel activation.
$app=New-SpreadsheetCom 'Excel.Application' $OutputDirectory
Assert ($app.engine -eq 'excel' -and $script:progIds.Count -eq 0) 'Excel used the redirected ProgID'
Assert ($script:directCalls.Count -eq 1 -and $script:directCalls[0].spec.exe -eq 'C:\Office\EXCEL.EXE' -and $script:directCalls[0].directory -eq $OutputDirectory) 'Direct Excel did not receive the selected path/tracker'
$cases+='excel-direct-launch-bypasses-progid-and-clsid'
$app=New-SpreadsheetCom 'excel.application'
Assert ($app.engine -eq 'excel' -and $script:progIds.Count -eq 0) 'Case variation bypassed fixed CLSID'
$cases+='excel-case-insensitive-routing'
$app=New-SpreadsheetCom 'ket.Application'
Assert ($app.engine -eq 'wps' -and $script:progIds.Count -eq 1 -and $script:progIds[0] -eq 'ket.Application') 'WPS activation changed'
$cases+='wps-specific-progid-preserved'
$script:directFails=$true;$caught=$false
try{$null=New-SpreadsheetCom 'Excel.Application'}catch{$caught=$_.Exception.Message -match 'Direct Excel'}
Assert ($caught -and $script:progIds.Count -eq 1) 'Missing Excel fell back to WPS'
$cases+='missing-excel-does-not-use-wps'
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
[ordered]@{passed=$true;kind='simulated-activation-routing';nativeExcelVerified=$false;cases=$cases}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $OutputDirectory 'activation.json') -Encoding UTF8
Write-Output ('Office activation cases passed: '+$cases.Count+' (simulation, not native Excel)')
$env:SENTIMENT_OFFICE_ENGINE=$null;$env:SENTIMENT_OFFICE_PATH=$null
