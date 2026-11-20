$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Start-Sleep {param($Milliseconds)}
$script:attempts=0
$value=Invoke-SpreadsheetReady {$script:attempts++;if($script:attempts -lt 3){throw [Runtime.InteropServices.COMException]::new('busy',-2147418111)};'ready'}
Assert ($value -eq 'ready' -and $script:attempts -eq 3) 'Busy activation did not recover'
$script:attempts=0;$caught=$false
try{Invoke-SpreadsheetReady {$script:attempts++;throw [Runtime.InteropServices.COMException]::new('not registered',-2147221164)}}catch{$caught=$true}
Assert ($caught -and $script:attempts -eq 1) 'Permanent registration error retried'
$script:attempts=0;$caught=$false
try{Invoke-SpreadsheetReady {$script:attempts++;throw [Runtime.InteropServices.COMException]::new('retry later',-2147417846)}}catch{$caught=Test-SpreadsheetBusy $_}
Assert ($caught -and $script:attempts -eq 5) 'Busy retry did not terminate at the bound'
$wrapped=[InvalidOperationException]::new('wrapper',[Runtime.InteropServices.COMException]::new('busy',-2147418111))
Assert (Test-SpreadsheetBusy $wrapped) 'Wrapped HRESULT not recognized'
Write-Output 'COM busy recovery, wrapped HRESULT, permanent error and retry bound checks passed'
$started=[DateTime]::UtcNow
$spec=[pscustomobject]@{engine='wps';exe='C:\FakeOffice\et.exe'}
$script:candidates=@(
 [pscustomobject]@{ProcessId=101;ParentProcessId=$PID;ExecutablePath=$spec.exe;CreationDate=$started.AddSeconds(1)},
 [pscustomobject]@{ProcessId=102;ParentProcessId=$PID;ExecutablePath=$spec.exe;CreationDate=$started.AddSeconds(1)},
 [pscustomobject]@{ProcessId=103;ParentProcessId=0;ExecutablePath=$spec.exe;CreationDate=$started.AddSeconds(1)},
 [pscustomobject]@{ProcessId=104;ParentProcessId=$PID;ExecutablePath='C:\Other\et.exe';CreationDate=$started.AddSeconds(1)},
 [pscustomobject]@{ProcessId=105;ParentProcessId=$PID;ExecutablePath=$spec.exe;CreationDate=$started.AddSeconds(-1)}
)
function Get-CimInstance {param($Filter,$ErrorAction) $script:candidates}
function Get-Process {param($Id,$ErrorAction) [pscustomobject]@{Id=$Id;ProcessName='et';StartTime=$started.AddSeconds(1);Path=$spec.exe}}
$directory=Join-Path $PSScriptRoot ('../test-results/activation-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory -Force|Out-Null
Register-ActivationProcesses $spec @(102) $started $directory
$records=@(Get-Content -LiteralPath (Join-Path $directory 'office-instances.jsonl')|ForEach-Object {$_|ConvertFrom-Json})
Assert ($records.Count -eq 1 -and $records[0].processId -eq 101) 'Activation tracking claimed an unrelated or pre-existing process'
Write-Output 'Activation tracking ownership passed: exact child, executable, timestamp and pre-existing PID protection'
