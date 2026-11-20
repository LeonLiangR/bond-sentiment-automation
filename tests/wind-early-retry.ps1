$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/wps-common.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
function Good([string]$Id,[string]$Name){return [ordered]@{sampleId=$Id;name=$Name;issuer='Issuer';windType='Type';term=3;guarantor=0;option=0;green='No';science='No';subordinate='No';bookrunner=0}}
$testState=@{retried=$false;calls=0;reads=0}
$testClock=[Diagnostics.Stopwatch]::StartNew()
$r=Wait-WindRows -ExpectedCount 2 -TimeoutSeconds 3 -PollMilliseconds 50 -AllowPartial -EarlyRetrySeconds 0.15 -OnEarlyRetry {param($rows,$ids) $testState.retried=$true;$testState.calls++;Assert ($ids.Count -eq 1 -and $ids[0] -eq 'a') 'Wrong early retry ID'} -ReadRows {
 $testState.reads++;$a=Good 'a' 'TestA';if(-not $testState.retried){$a.issuer=0};$a
 $b=Good 'b' 'Other';if($testClock.Elapsed.TotalSeconds -lt 0.6){$b.bookrunner='Fetching...'};$b
}
Assert ($testState.calls -eq 1 -and $r.stable -and $r.elapsedSeconds -ge 0.6 -and $r.elapsedSeconds -lt 2) 'Early retry repeated or truncated other pending rows'
$testState=@{calls=0};$pending=Wait-WindRows -ExpectedCount 1 -TimeoutSeconds 1 -PollMilliseconds 50 -AllowPartial -EarlyRetrySeconds 0.1 -OnEarlyRetry {param($rows,$ids) $testState.calls++} -ReadRows {$a=Good 'a' 'TestA';$a.issuer=0;$a.bookrunner='Fetching...';$a}
Assert ($testState.calls -eq 0 -and $pending.rows[0].windFailure) 'Fetching sample retried prematurely'
$original=Good 'a' 'TestA';$retry=Good 'a' 'TestA';$retry.issuer='Retry issuer';$samples=@([ordered]@{sampleId='a';name='TestA';query='Test'})
$joined=@(Join-WindNameRetryRows @($original) @($retry) $samples);Assert ($joined[0].issuer -eq 'Issuer' -and -not $joined[0].windRetry) 'Recovered original was not preferred'
$original.issuer=0;$joined=@(Join-WindNameRetryRows @($original) @($retry) $samples);Assert ($joined[0].windRetry.queryName -eq 'Test' -and $joined[0].name -eq 'TestA') 'Retry changed original identity'
'Stable-zero early retry, unchanged Fetching wait, one retry per ID and recovered-original preference passed'
